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
import 'booking_status_screen.dart';

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
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  // ^ default tomorrow; today is allowed but past slots are disabled
  final _addressCtrl = TextEditingController();
  final _landmarkCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _loading = false;
  double? _customerLat;
  double? _customerLng;
  String _city = '';

  final List<String> _timeSlots = [
    '07:00 AM','08:00 AM','09:00 AM','10:00 AM',
    '11:00 AM','12:00 PM','01:00 PM','02:00 PM',
    '03:00 PM','04:00 PM','05:00 PM','06:00 PM',
  ];
  String _selectedSlot = '09:00 AM';

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Start time of a slot like '09:00 AM' on [day].
  static DateTime _slotStart(DateTime day, String slot) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})\s*(AM|PM)$').firstMatch(slot.trim());
    if (m == null) return DateTime(day.year, day.month, day.day);
    var h = int.parse(m.group(1)!) % 12;
    if (m.group(3) == 'PM') h += 12;
    return DateTime(day.year, day.month, day.day, h, int.parse(m.group(2)!));
  }

  /// A slot is selectable if it starts at least 30 minutes from now.
  bool _slotAvailable(String slot) {
    if (!_sameDay(_selectedDate, DateTime.now())) return true;
    return _slotStart(_selectedDate, slot)
        .isAfter(DateTime.now().add(const Duration(minutes: 30)));
  }

  void _fixSelectedSlot() {
    if (_selectedSlot.isNotEmpty && _slotAvailable(_selectedSlot)) return;
    _selectedSlot = _timeSlots.firstWhere(_slotAvailable, orElse: () => '');
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

  void _openMapView() {
    if (_customerLat == null || _customerLng == null) return;
    // Open Google Maps at detected location so user can verify
    launchUrl(Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=$_customerLat,$_customerLng'));
  }

  String get _slotDate =>
      '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';

  bool _validateStep(int step) {
    if (step == 0) {
      if (_selectedSlot.isEmpty || !_slotAvailable(_selectedSlot)) {
        _showError('Please pick an available time slot');
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
        slotTime:     _selectedSlot,
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

  String _stepTitle() => ['Select Date & Time', 'Enter Address', 'Confirm Booking'][_step];

  Widget _buildDateTimeStep() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Select Date', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink)),
      const SizedBox(height: 12),
      Container(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)]),
        child: CalendarDatePicker(
          initialDate: _selectedDate,
          firstDate: DateTime.now(),
          lastDate: DateTime.now().add(const Duration(days: 60)),
          onDateChanged: (d) {
            HapticFeedback.selectionClick();
            setState(() { _selectedDate = d; _fixSelectedSlot(); });
          })),
      const SizedBox(height: 20),
      const Text('Select Time Slot', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink)),
      const SizedBox(height: 12),
      Wrap(spacing: 10, runSpacing: 10,
        children: _timeSlots.map((slot) {
          final available = _slotAvailable(slot);
          final sel = available && slot == _selectedSlot;
          return GestureDetector(
            onTap: available
                ? () { HapticFeedback.selectionClick(); setState(() => _selectedSlot = slot); }
                : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: sel ? AppColors.teal : (available ? Colors.white : AppColors.line.withOpacity(0.5)),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: sel ? AppColors.teal : AppColors.line)),
              child: Text(slot, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                color: sel ? Colors.white : (available ? AppColors.ink2 : AppColors.muted),
                decoration: available ? null : TextDecoration.lineThrough))));
        }).toList()),
      if (!_timeSlots.any(_slotAvailable)) ...[
        const SizedBox(height: 10),
        const Text('No slots left for today — please pick another date.',
          style: TextStyle(fontSize: 12, color: AppColors.red, fontWeight: FontWeight.w600)),
      ],
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
            _customerLat != null ? 'GPS location loaded ✓' : 'Location not detected — enter your address below',
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
      _infoCard(Icons.calendar_today_rounded, 'Date & Time', '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year} at $_selectedSlot'),
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
