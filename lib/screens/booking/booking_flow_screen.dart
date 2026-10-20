import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/api_service.dart';
import '../../utils/booking_format.dart';
import '../../utils/theme.dart';
import '../map_picker_screen.dart';
import 'booking_status_screen.dart';

/// A "When?" option: Now / ASAP, or a preferred window on a chosen day.
/// Same options and slot_time format as the website (app/customer.html).
class _TimeWindow {
  final String key;   // 'Now / ASAP' | 'Morning' | 'Afternoon' | 'Evening'
  final String emoji;
  final String sub;   // '8 AM – 12 PM'
  final int from;     // window start hour (0 for ASAP)
  final int to;       // window end hour (0 for ASAP)
  const _TimeWindow(this.key, this.emoji, this.sub, [this.from = 0, this.to = 0]);
  bool get isAsap => to == 0;
  String get label => '$emoji $key';
}

class BookingFlowScreen extends StatefulWidget {
  final Map<String, dynamic> service;
  final int basePrice;
  final List<String> summary;
  const BookingFlowScreen({
    super.key,
    required this.service,
    required this.basePrice,
    this.summary = const [],
  });
  @override
  State<BookingFlowScreen> createState() => _BookingFlowScreenState();
}

class _BookingFlowScreenState extends State<BookingFlowScreen> {
  int _step = 0;
  final _addressCtrl = TextEditingController();
  final _landmarkCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _loading = false;
  double? _customerLat;
  double? _customerLng;
  bool _pinnedOnMap = false;
  String _city = '';

  // ── When? ──
  static const _asap = 'Now / ASAP';
  static const List<_TimeWindow> _windows = [
    _TimeWindow(_asap, '⚡', 'Nearest free provider'),
    _TimeWindow('Morning', '🌅', '8 AM – 12 PM', 8, 12),
    _TimeWindow('Afternoon', '☀️', '12 – 4 PM', 12, 16),
    _TimeWindow('Evening', '🌇', '4 – 8 PM', 16, 20),
  ];
  String _selWindow = _asap;
  int _selDay = 0;     // 0 = today, 1 = tomorrow, 2 = day after
  String _selHour = ''; // optional, e.g. '9 AM'

  _TimeWindow get _window =>
      _windows.firstWhere((w) => w.key == _selWindow, orElse: () => _windows.first);

  DateTime _day(int offset) {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day + offset);
  }

  static String _hourLabel(int h) => '${h % 12 == 0 ? 12 : h % 12} ${h < 12 ? 'AM' : 'PM'}';

  /// Today a window needs at least 1 h left; later days are always open.
  bool _windowOpen(_TimeWindow w, int day) =>
      w.isAsap || day > 0 || DateTime.now().hour < w.to - 1;

  /// Hours offered for the chosen window/day (past hours of today hidden).
  List<String> get _hours {
    final w = _window;
    if (w.isAsap) return const [];
    final now = DateTime.now().hour;
    return [
      for (var h = w.from; h < w.to; h++)
        if (!(_selDay == 0 && h <= now)) _hourLabel(h),
    ];
  }

  void _pickWindow(String key) {
    HapticFeedback.selectionClick();
    setState(() {
      _selWindow = key;
      _selHour = '';
      final w = _window;
      if (!w.isAsap && _selDay == 0 && !_windowOpen(w, 0)) _selDay = 1;
    });
  }

  void _pickDay(int i) {
    HapticFeedback.selectionClick();
    setState(() {
      _selDay = i;
      if (!_windowOpen(_window, i)) _selWindow = _asap;
      if (!_hours.contains(_selHour)) _selHour = '';
    });
  }

  String _dayName(int i) {
    if (i == 0) return 'Today';
    if (i == 1) return 'Tomorrow';
    const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const mo = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final d = _day(i);
    return '${wd[d.weekday - 1]}, ${d.day} ${mo[d.month - 1]}';
  }

  /// slot_date: the chosen day (today for ASAP), YYYY-MM-DD.
  String get _slotDate {
    final d = _day(_window.isAsap ? 0 : _selDay);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  /// slot_time, exactly like the web: 'Now / ASAP' or
  /// 'Morning (8 AM – 12 PM) · 9 AM' (the hour part is optional).
  String get _slotTime {
    final w = _window;
    if (w.isAsap) return _asap;
    return '${w.key} (${w.sub})${_selHour.isNotEmpty ? ' · $_selHour' : ''}';
  }

  String get _whenSummary {
    final w = _window;
    if (w.isAsap) return '⚡ Now / ASAP — nearest available provider';
    return '${_dayName(_selDay)}, ${w.key} (${w.sub})${_selHour.isNotEmpty ? ' · around $_selHour' : ''}';
  }

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _addressCtrl.dispose();
    _landmarkCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    _nameCtrl.text = user?.displayName ?? '';
    try {
      final prefs = await SharedPreferences.getInstance();
      _city = prefs.getString('user_city') ?? '';
    } catch (_) {}
    try {
      final profile = await ApiService.getCustomer();
      if (profile != null && mounted) {
        final lat = asDouble(profile['lat']);
        final lng = asDouble(profile['lng']);
        final savedAddress = asStr(profile['address']);
        final city = asStr(profile['city']);
        setState(() {
          if (lat != null && lng != null && lat != 0 && lng != 0) {
            _customerLat = lat;
            _customerLng = lng;
          }
          if (city.isNotEmpty) _city = city;
          if (_addressCtrl.text.isEmpty) {
            _addressCtrl.text = savedAddress.isNotEmpty ? savedAddress : city;
          }
          if (_nameCtrl.text.isEmpty) _nameCtrl.text = asStr(profile['name']);
          if (_phoneCtrl.text.isEmpty) _phoneCtrl.text = asStr(profile['phone']);
        });
      }
    } on ApiException catch (e) {
      debugPrint('Profile load failed: ${e.message}');
    }
    if (_phoneCtrl.text.isEmpty) {
      _phoneCtrl.text = normalizeIndianMobile(user?.phoneNumber ?? '');
    }
    // No saved coordinates — capture GPS now
    if (_customerLat == null) await _captureGPS();
  }

  Future<void> _captureGPS() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) return;

      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 10));

      String addr = '';
      String city = '';
      try {
        final placemarks = await placemarkFromCoordinates(
            pos.latitude, pos.longitude);
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          addr = [p.street, p.subLocality, p.locality]
              .whereType<String>()
              .where((s) => s.isNotEmpty)
              .join(', ');
          city = p.locality ?? p.subAdministrativeArea ?? '';
        }
      } catch (_) {
        // reverse geocoding is optional
      }

      if (_pinnedOnMap) return; // a map pin is more exact than GPS
      if (mounted) {
        setState(() {
          _customerLat = pos.latitude;
          _customerLng = pos.longitude;
          if (city.isNotEmpty && _city.isEmpty) _city = city;
          if (_addressCtrl.text.isEmpty && addr.isNotEmpty) {
            _addressCtrl.text = addr;
          }
        });
      }
      // Save to profile for next time (best effort)
      try {
        await ApiService.updateCustomer({
          'lat': pos.latitude, 'lng': pos.longitude,
          if (city.isNotEmpty) 'city': city,
        });
      } on ApiException catch (e) {
        debugPrint('Saving location failed: ${e.message}');
      }
    } catch (e) {
      debugPrint('GPS capture failed: $e');
    }
  }

  /// Customer pins the service location on a map (more exact than GPS).
  Future<void> _pinOnMap() async {
    HapticFeedback.selectionClick();
    final r = await MapPickerScreen.open(context,
        lat: _customerLat, lng: _customerLng);
    if (r == null || !mounted) return;
    setState(() {
      _customerLat = r.lat;
      _customerLng = r.lng;
      _pinnedOnMap = true;
      if (r.address.isNotEmpty) _addressCtrl.text = r.address;
      if (r.city.isNotEmpty) _city = r.city;
    });
    try {
      await ApiService.updateCustomer({
        'lat': r.lat, 'lng': r.lng,
        if (r.city.isNotEmpty) 'city': r.city,
      });
    } on ApiException catch (e) {
      debugPrint('Saving pinned location failed: ${e.message}');
    }
  }

  void _openMapView() {
    if (_customerLat == null || _customerLng == null) return;
    // Open Google Maps at detected location so user can verify
    launchUrl(Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=$_customerLat,$_customerLng'));
  }

  bool _validateStep(int step) {
    if (step == 0) {
      if (!_windowOpen(_window, _selDay)) {
        _showError('This time window is over for today — pick another day or time');
        return false;
      }
    } else if (step == 1) {
      if (_addressCtrl.text.trim().isEmpty) {
        _showError('Please enter your address'); return false;
      }
      if (_landmarkCtrl.text.trim().isEmpty) {
        _showError('Landmark is required — helps provider find you'); return false;
      }
      if (_nameCtrl.text.trim().isEmpty) {
        _showError('Please enter your name'); return false;
      }
      if (!isValidIndianMobile(_phoneCtrl.text)) {
        _showError('Please enter a valid 10-digit Indian mobile number'); return false;
      }
    }
    return true;
  }

  Future<void> _confirmBooking() async {
    HapticFeedback.mediumImpact();
    if (!_validateStep(0)) { setState(() => _step = 0); return; }
    if (!_validateStep(1)) { setState(() => _step = 1); return; }
    final phone = normalizeIndianMobile(_phoneCtrl.text);

    setState(() => _loading = true);
    try {
      // The server requires a customer profile before booking (412).
      await ApiService.ensureCustomerProfile(
          name: _nameCtrl.text.trim(), phone: phone);

      final summary = widget.summary.isNotEmpty
          ? widget.summary
          : ['${widget.service['name']} > Service booking'];
      final bookingId = await ApiService.createBooking(
        svcId:        asStr(widget.service['id']),
        svcName:      asStr(widget.service['name']),
        svcIcon:      asStr(widget.service['icon']),
        address:      _addressCtrl.text.trim(),
        landmark:     _landmarkCtrl.text.trim(),
        city:         _city,
        lat:          _customerLat ?? 0,
        lng:          _customerLng ?? 0,
        slotDate:     _slotDate,
        slotTime:     _slotTime,
        notes:        _notesCtrl.text.trim(),
        contactName:  _nameCtrl.text.trim(),
        contactPhone: phone,
        estPrice:     widget.basePrice,
        summary:      summary,
      );
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(
        builder: (_) => BookingStatusScreen(bookingId: bookingId)));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      if (e.statusCode == 409) {
        _showActiveBookingDialog(e.message);
      } else {
        _showError(e.message);
      }
    }
  }

  Future<void> _showActiveBookingDialog(String message) async {
    final view = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('You already have a booking'),
        content: Text('$message\n\nFinish or cancel it before booking another service.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Close')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('View booking')),
        ],
      ),
    );
    if (view != true || !mounted) return;
    try {
      final active = await ApiService.getActiveBooking();
      final id = asStr(active?['id']);
      if (id.isEmpty || !mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(
        builder: (_) => BookingStatusScreen(bookingId: id)));
    } on ApiException catch (e) {
      _showError(e.message);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    HapticFeedback.heavyImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.red));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: Text(_stepTitle()), backgroundColor: AppColors.teal),
      body: Column(children: [
        // Step progress bar
        Container(color: AppColors.teal, padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Row(children: List.generate(3, (i) => Expanded(child: Row(children: [
            Expanded(child: Container(height: 4,
              decoration: BoxDecoration(
                color: i <= _step ? AppColors.brand : Colors.white30,
                borderRadius: BorderRadius.circular(2)))),
            if (i < 2) const SizedBox(width: 4),
          ])))),
        ),
        Expanded(child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: _step == 0 ? _buildDateTimeStep() : _step == 1 ? _buildAddressStep() : _buildConfirmStep(),
        )),
        // Bottom buttons
        Container(padding: const EdgeInsets.fromLTRB(20, 12, 20, 24), color: Colors.white,
          child: Row(children: [
            if (_step > 0) ...[
              OutlinedButton(
                onPressed: () { HapticFeedback.lightImpact(); setState(() => _step--); },
                style: OutlinedButton.styleFrom(minimumSize: const Size(80, 52),
                  side: const BorderSide(color: AppColors.teal),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                child: const Text('Back', style: TextStyle(color: AppColors.teal, fontWeight: FontWeight.w700))),
              const SizedBox(width: 12),
            ],
            Expanded(child: ElevatedButton(
              onPressed: _loading ? null : () {
                HapticFeedback.mediumImpact();
                if (_step < 2) {
                  if (_validateStep(_step)) setState(() => _step++);
                } else {
                  _confirmBooking();
                }
              },
              style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              child: _loading
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, valueColor: AlwaysStoppedAnimation(Colors.white)))
                  : Text(_step < 2 ? 'Next' : 'Confirm Booking',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)))),
          ])),
      ]),
    );
  }

  String _stepTitle() => ['When do you need it?', 'Enter Address', 'Confirm Booking'][_step];

  Widget _buildDateTimeStep() {
    final w = _window;
    final hours = _hours;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('When?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink)),
      const SizedBox(height: 12),
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 2.4,
        children: _windows.map((tw) {
          final open = _windowOpen(tw, _selDay);
          final sel = tw.key == _selWindow;
          return Opacity(
            opacity: open ? 1 : 0.45,
            child: GestureDetector(
              onTap: open ? () => _pickWindow(tw.key) : null,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: sel ? AppColors.teal : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: sel ? AppColors.teal : AppColors.line)),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(tw.label, textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800,
                      color: sel ? Colors.white : AppColors.ink)),
                  const SizedBox(height: 2),
                  Text(tw.sub, textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                      color: sel ? Colors.white70 : AppColors.muted)),
                ]))));
        }).toList()),
      if (!w.isAsap) ...[
        const SizedBox(height: 20),
        const Text('Which day?', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.ink)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: List.generate(3, (i) {
          final sel = i == _selDay;
          return ChoiceChip(
            label: Text(_dayName(i)),
            selected: sel,
            showCheckmark: false,
            selectedColor: AppColors.teal,
            backgroundColor: Colors.white,
            side: BorderSide(color: sel ? AppColors.teal : AppColors.line),
            labelStyle: TextStyle(fontWeight: FontWeight.w700,
              color: sel ? Colors.white : AppColors.ink2),
            onSelected: (_) => _pickDay(i));
        })),
        const SizedBox(height: 16),
        _label('PREFERRED HOUR (OPTIONAL)'),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          key: ValueKey('hour-$_selWindow-$_selDay'),
          value: hours.contains(_selHour) ? _selHour : '',
          isExpanded: true,
          decoration: InputDecoration(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
          items: [
            const DropdownMenuItem(value: '', child: Text('Any time in this window')),
            ...hours.map((h) => DropdownMenuItem(value: h, child: Text(h))),
          ],
          onChanged: (v) => setState(() => _selHour = v ?? '')),
      ],
      const SizedBox(height: 16),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.tealSoft,
          borderRadius: BorderRadius.circular(12)),
        child: Text(
          w.isAsap
              ? '⚡ We will send the nearest available provider right away.'
              : '🗓️ ${_dayName(_selDay)}, ${w.sub} — the provider confirms the exact time.',
          style: const TextStyle(fontSize: 12.5, color: AppColors.teal, fontWeight: FontWeight.w600))),
    ]);
  }

  Widget _buildAddressStep() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Service Address', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink)),
      const Text('Where should the provider come?', style: TextStyle(fontSize: 13, color: AppColors.muted)),
      const SizedBox(height: 14),

      // Location status — no re-fetch, just show saved status
      Container(padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _customerLat != null ? AppColors.greenSoft : AppColors.yellow.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _customerLat != null ? AppColors.green : AppColors.yellow)),
        child: Row(children: [
          Icon(_customerLat != null ? Icons.location_on_rounded : Icons.location_off_rounded,
              color: _customerLat != null ? AppColors.green : AppColors.yellow, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(
            _pinnedOnMap
                ? 'Location pinned on map ✓'
                : _customerLat != null
                    ? 'GPS location loaded ✓'
                    : 'Location not detected — pin it on the map or enter your address',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
              color: _customerLat != null ? AppColors.green : AppColors.yellow))),
          if (_customerLat != null)
            GestureDetector(
              onTap: _openMapView,
              child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: AppColors.green.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.map_rounded, color: AppColors.green, size: 14),
                  SizedBox(width: 4),
                  Text('View', style: TextStyle(fontSize: 12, color: AppColors.green, fontWeight: FontWeight.w700)),
                ]))),
        ])),

      const SizedBox(height: 10),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: _pinOnMap,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 46),
            side: const BorderSide(color: AppColors.teal),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          child: const Text('🗺️ Pin exact location on map',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.teal)))),

      const SizedBox(height: 14),
      _label('FULL ADDRESS *'),
      const SizedBox(height: 6),
      TextField(controller: _addressCtrl, maxLines: 3,
        decoration: InputDecoration(
          hintText: 'House no, Street, Area, City',
          helperText: 'Edit if needed',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),

      const SizedBox(height: 14),
      Row(children: [
        const Text('LANDMARK', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.muted, letterSpacing: 0.5)),
        const SizedBox(width: 6),
        Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(color: AppColors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
          child: const Text('REQUIRED', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: AppColors.red))),
      ]),
      const SizedBox(height: 6),
      TextField(controller: _landmarkCtrl,
        decoration: InputDecoration(
          hintText: 'Near school, temple, hospital, etc.',
          helperText: 'Helps provider find you easily',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),

      const SizedBox(height: 20),
      const Text('Your Contact Details', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink)),
      const SizedBox(height: 4),
      const Text('Pre-filled from your profile', style: TextStyle(fontSize: 12, color: AppColors.muted)),
      const SizedBox(height: 12),

      // Name — read only with edit icon
      _label('FULL NAME'),
      const SizedBox(height: 6),
      TextField(
        controller: _nameCtrl,
        decoration: InputDecoration(
          hintText: 'Your name',
          prefixIcon: const Icon(Icons.person_rounded, color: AppColors.teal, size: 18),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: AppColors.bg)),

      const SizedBox(height: 14),
      _label('MOBILE NUMBER'),
      const SizedBox(height: 6),
      TextField(
        controller: _phoneCtrl,
        keyboardType: TextInputType.phone,
        maxLength: 10,
        decoration: InputDecoration(
          hintText: '10-digit mobile number',
          counterText: '',
          prefixIcon: const Icon(Icons.phone_rounded, color: AppColors.teal, size: 18),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: AppColors.bg)),

      const SizedBox(height: 14),
      _label('NOTES FOR PROVIDER (OPTIONAL)'),
      const SizedBox(height: 6),
      TextField(
        controller: _notesCtrl,
        maxLines: 2,
        decoration: InputDecoration(
          hintText: 'Anything the provider should know',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
    ]);
  }

  Widget _buildConfirmStep() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Booking Summary', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink)),
      const SizedBox(height: 16),
      // Service card
      Container(padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)]),
        child: Row(children: [
          Container(width: 52, height: 52,
            decoration: BoxDecoration(color: Color(widget.service['color'] != null ? widget.service['color'] as int : 0xFF1B6B7A), borderRadius: BorderRadius.circular(12)),
            child: Center(child: Text(asStr(widget.service['icon']), style: const TextStyle(fontSize: 28)))),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(asStr(widget.service['name']), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.ink)),
            Text(asStr(widget.service['cat']), style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          ])),
        ])),
      const SizedBox(height: 12),
      _infoCard(Icons.calendar_today_rounded, 'When', _whenSummary),
      const SizedBox(height: 8),
      _infoCard(Icons.location_on_rounded, 'Address', _addressCtrl.text.trim()),
      const SizedBox(height: 8),
      _infoCard(Icons.place_rounded, 'Landmark', _landmarkCtrl.text.trim()),
      const SizedBox(height: 8),
      _infoCard(Icons.person_rounded, 'Contact', '${_nameCtrl.text.trim()} • ${_phoneCtrl.text.trim()}'),
      if (widget.summary.isNotEmpty) ...[
        const SizedBox(height: 12),
        Container(width: double.infinity, padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: AppColors.tealSoft, borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.teal.withOpacity(0.2))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('SELECTED SERVICES', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.teal, letterSpacing: 0.5)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: widget.summary.map((s) {
              final parts = s.split(' > ');
              return Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.teal.withOpacity(0.3))),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.check_circle_rounded, color: AppColors.teal, size: 14),
                  const SizedBox(width: 6),
                  Text(parts.length > 1 ? parts.sublist(1).join(' > ') : s,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.teal)),
                ]));
            }).toList()),
          ])),
      ],
      const SizedBox(height: 12),
      Container(padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppColors.tealSoft, borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.teal.withOpacity(0.3))),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Estimated price', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.teal)),
          Text(widget.basePrice > 0 ? '₹${widget.basePrice}' : 'Quoted by provider',
            style: TextStyle(fontSize: widget.basePrice > 0 ? 24 : 15, fontWeight: FontWeight.w800, color: AppColors.teal)),
        ])),
      const SizedBox(height: 8),
      const Text('Nothing is charged now. A provider will quote the final price, which you accept in the app before work starts. You pay after the service is completed.',
        style: TextStyle(fontSize: 12, color: AppColors.muted, height: 1.4)),
    ]);
  }

  Widget _label(String text) => Text(text,
    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.muted, letterSpacing: 0.5));

  Widget _infoCard(IconData icon, String title, String value) {
    return Container(padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)]),
      child: Row(children: [
        Icon(icon, color: AppColors.teal, size: 20),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 11, color: AppColors.muted, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 13, color: AppColors.ink, fontWeight: FontWeight.w600)),
        ])),
      ]));
  }
}
