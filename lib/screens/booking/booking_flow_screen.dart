import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/api_service.dart';
import '../../services/session.dart';
import '../../utils/booking_format.dart';
import '../../utils/theme.dart';
import '../../widgets/common.dart';
import '../map_picker_screen.dart';
import 'booking_status_screen.dart';

/// A "When?" option: Now / ASAP, or a preferred window on a chosen day.
/// Same options and slot_time format as the website (app/customer.html).
class _TimeWindow {
  final String key; // 'Now / ASAP' | 'Morning' | 'Afternoon' | 'Evening'
  final IconData icon;
  final String sub; // '8 AM – 12 PM'
  final int from; // window start hour (0 for ASAP)
  final int to; // window end hour (0 for ASAP)
  const _TimeWindow(this.key, this.icon, this.sub, [this.from = 0, this.to = 0]);
  bool get isAsap => to == 0;
}

/// Booking: When? → Address → Review & find provider. Sends exactly the
/// fields the web app sends to bookings.php?action=create.
class BookingFlowScreen extends StatefulWidget {
  final Map<String, dynamic> service;
  final int basePrice;
  final List<String> summary;

  /// Test-only: pre-filled profile; when set nothing is loaded.
  final Map<String, dynamic>? preview;
  final int initialStep;
  const BookingFlowScreen({
    super.key,
    required this.service,
    required this.basePrice,
    this.summary = const [],
    this.preview,
    this.initialStep = 0,
  });
  @override
  State<BookingFlowScreen> createState() => _BookingFlowScreenState();
}

class _BookingFlowScreenState extends State<BookingFlowScreen> {
  late int _step = widget.initialStep;
  final _addressCtrl = TextEditingController();
  final _flatCtrl = TextEditingController();
  final _landmarkCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _loading = false;
  bool _locating = false;
  double? _customerLat;
  double? _customerLng;
  bool _pinnedOnMap = false;
  String _city = '';
  // Name + phone already known (profile): shown as one line, editable on tap.
  bool _contactKnown = false;
  bool _editContact = false;

  // ── When? ──
  static const _asap = 'Now / ASAP';
  static const List<_TimeWindow> _windows = [
    _TimeWindow(_asap, Icons.bolt_rounded, 'Nearest free provider'),
    _TimeWindow('Morning', Icons.wb_twilight_rounded, '8 AM – 12 PM', 8, 12),
    _TimeWindow('Afternoon', Icons.wb_sunny_outlined, '12 – 4 PM', 12, 16),
    _TimeWindow('Evening', Icons.nights_stay_outlined, '4 – 8 PM', 16, 20),
  ];
  String _selWindow = _asap;
  int _selDay = 0; // 0 = today, 1 = tomorrow, 2 = day after
  String _selHour = ''; // optional, e.g. '9 AM'

  _TimeWindow get _window =>
      _windows.firstWhere((w) => w.key == _selWindow, orElse: () => _windows.first);

  DateTime _day(int offset) {
    final n = clock();
    return DateTime(n.year, n.month, n.day + offset);
  }

  static String _hourLabel(int h) => '${h % 12 == 0 ? 12 : h % 12} ${h < 12 ? 'AM' : 'PM'}';

  /// Today a window needs at least 1 h left; later days are always open.
  bool _windowOpen(_TimeWindow w, int day) =>
      w.isAsap || day > 0 || clock().hour < w.to - 1;

  /// Hours offered for the chosen window/day (past hours of today hidden).
  List<String> get _hours {
    final w = _window;
    if (w.isAsap) return const [];
    final now = clock().hour;
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
    const mo = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
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
    if (w.isAsap) return 'Now / ASAP — nearest available provider';
    return '${_dayName(_selDay)}, ${w.key} (${w.sub})${_selHour.isNotEmpty ? ' · around $_selHour' : ''}';
  }

  /// Address sent to the server, like the web: "Flat / door, location".
  String get _fullAddress {
    final flat = _flatCtrl.text.trim();
    final loc = _addressCtrl.text.trim();
    if (flat.isEmpty) return loc;
    if (loc.isEmpty) return flat;
    return '$flat, $loc';
  }

  @override
  void initState() {
    super.initState();
    final p = widget.preview;
    if (p != null) {
      _addressCtrl.text = asStr(p['address']);
      _flatCtrl.text = asStr(p['flat']);
      _landmarkCtrl.text = asStr(p['landmark']);
      _nameCtrl.text = asStr(p['name']);
      _phoneCtrl.text = asStr(p['phone']);
      _city = asStr(p['city']);
      _customerLat = asDouble(p['lat']);
      _customerLng = asDouble(p['lng']);
      _pinnedOnMap = p['pinned'] == true;
      if (asStr(p['window']).isNotEmpty) _selWindow = asStr(p['window']);
      _selDay = asInt(p['day']);
      return;
    }
    _loadProfile();
  }

  @override
  void dispose() {
    _addressCtrl.dispose();
    _flatCtrl.dispose();
    _landmarkCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final user = Session.user;
    _nameCtrl.text = user?.displayName ?? '';
    try {
      final prefs = await SharedPreferences.getInstance();
      _city = prefs.getString('user_city') ?? '';
      // Flat / landmark from the last booking
      if (_flatCtrl.text.isEmpty) _flatCtrl.text = prefs.getString('hs_last_flat') ?? '';
      if (_landmarkCtrl.text.isEmpty) _landmarkCtrl.text = prefs.getString('hs_last_landmark') ?? '';
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
    if (mounted) {
      setState(() => _contactKnown =
          _nameCtrl.text.trim().isNotEmpty && isValidIndianMobile(_phoneCtrl.text));
    }
    // Web: always fetch a fresh precise location on the address step.
    await _captureGPS();
  }

  Future<void> _captureGPS() async {
    if (mounted) setState(() => _locating = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) return;

      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high, timeLimit: const Duration(seconds: 12));

      String addr = '';
      String city = '';
      try {
        final placemarks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          addr = [p.street, p.subLocality, p.locality, p.postalCode]
              .whereType<String>()
              .where((s) => s.isNotEmpty)
              .toSet()
              .join(', ');
          city = p.locality ?? p.subAdministrativeArea ?? '';
        }
      } catch (_) {}

      if (_pinnedOnMap) return; // a map pin is more exact than GPS
      if (mounted) {
        setState(() {
          _customerLat = pos.latitude;
          _customerLng = pos.longitude;
          if (city.isNotEmpty) _city = city;
          if (addr.isNotEmpty) _addressCtrl.text = addr;
        });
      }
      try {
        await ApiService.updateCustomer({
          'lat': pos.latitude,
          'lng': pos.longitude,
          if (city.isNotEmpty) 'city': city,
        });
      } on ApiException catch (e) {
        debugPrint('Saving location failed: ${e.message}');
      }
    } catch (e) {
      debugPrint('GPS capture failed: $e');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  /// Customer pins the service location on a map (more exact than GPS).
  Future<void> _pinOnMap() async {
    HapticFeedback.selectionClick();
    final r = await MapPickerScreen.open(context, lat: _customerLat, lng: _customerLng);
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
        'lat': r.lat,
        'lng': r.lng,
        if (r.city.isNotEmpty) 'city': r.city,
      });
    } on ApiException catch (e) {
      debugPrint('Saving pinned location failed: ${e.message}');
    }
  }

  void _openMapView() {
    if (_customerLat == null || _customerLng == null) return;
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
      // Same checks and messages as the web (createBooking).
      if (_addressCtrl.text.trim().isEmpty) {
        _showError('Location not detected — pin it on the map or type your address');
        return false;
      }
      if (_flatCtrl.text.trim().isEmpty) {
        _showError('Enter your flat / door number');
        return false;
      }
      if (_nameCtrl.text.trim().isEmpty) {
        setState(() => _editContact = true);
        _showError('Enter your name');
        return false;
      }
      if (!isValidIndianMobile(_phoneCtrl.text)) {
        setState(() => _editContact = true);
        _showError('Enter valid mobile');
        return false;
      }
    }
    return true;
  }

  Future<void> _confirmBooking() async {
    HapticFeedback.mediumImpact();
    if (!_validateStep(0)) { setState(() => _step = 0); return; }
    if (!_validateStep(1)) { setState(() => _step = 1); return; }
    final phone = normalizeIndianMobile(_phoneCtrl.text);
    final address = _fullAddress;

    setState(() => _loading = true);
    try {
      // The server requires a customer profile before booking (412).
      await ApiService.ensureCustomerProfile(name: _nameCtrl.text.trim(), phone: phone);
      // Web: also save phone / address / city as the profile defaults.
      ApiService.updateCustomer({
        'phone': phone,
        'address': address,
        if (_city.isNotEmpty) 'city': _city,
      }).catchError((_) => <String, dynamic>{});

      final summary = widget.summary.isNotEmpty
          ? widget.summary
          : ['${widget.service['name']} > Service booking'];
      final note = _notesCtrl.text.trim();
      final bookingId = await ApiService.createBooking(
        svcId: asStr(widget.service['id']),
        svcName: asStr(widget.service['name']),
        svcIcon: asStr(widget.service['icon']),
        address: address,
        landmark: _landmarkCtrl.text.trim(),
        city: _city,
        lat: _customerLat ?? 0,
        lng: _customerLng ?? 0,
        slotDate: _slotDate,
        slotTime: _slotTime,
        // Web sends the selected tasks + job answers as notes.
        notes: [...summary, if (note.isNotEmpty) 'Note: $note'].join(', '),
        contactName: _nameCtrl.text.trim(),
        contactPhone: phone,
        estPrice: widget.basePrice,
        summary: summary,
      );
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('hs_last_flat', _flatCtrl.text.trim());
        await prefs.setString('hs_last_landmark', _landmarkCtrl.text.trim());
      } catch (_) {}
      if (!mounted) return;
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => BookingStatusScreen(bookingId: bookingId)));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      if (e.statusCode == 409) {
        _showActiveBookingDialog(e.message);
      } else {
        _showError(e.message.isNotEmpty ? e.message : 'Booking failed');
      }
    }
  }

  Future<void> _showActiveBookingDialog(String message) async {
    final view = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.event_busy_rounded),
        title: const Text('You already have a booking'),
        content: Text('$message\n\nFinish or cancel it before booking another service.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Close')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('View booking')),
        ],
      ),
    );
    if (view != true || !mounted) return;
    try {
      final active = await ApiService.getActiveBooking();
      final id = asStr(active?['id']);
      if (id.isEmpty || !mounted) return;
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => BookingStatusScreen(bookingId: id)));
    } on ApiException catch (e) {
      _showError(e.message);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    HapticFeedback.heavyImpact();
    showSnack(context, msg, error: true);
  }

  void _next() {
    HapticFeedback.selectionClick();
    if (_step < 2) {
      if (_validateStep(_step)) setState(() => _step++);
    } else {
      _confirmBooking();
    }
  }

  // ── UI ─────────────────────────────────────────────────────
  static const _titles = ['When do you need it?', 'Service address', 'Review booking'];

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _step == 0,
      onPopInvoked: (did) {
        if (!did) setState(() => _step--);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_titles[_step]),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(56),
            child: _StepIndicator(step: _step, labels: const ['When', 'Address', 'Confirm']),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _serviceHeader(context),
            const SizedBox(height: 16),
            if (_step == 0) ..._whenStep(context),
            if (_step == 1) ..._addressStep(context),
            if (_step == 2) ..._confirmStep(context),
          ],
        ),
        bottomNavigationBar: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: AppColors.line)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(children: [
                if (_step > 0) ...[
                  OutlinedButton(
                    onPressed: _loading ? null : () => setState(() => _step--),
                    child: const Text('Back'),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: FilledButton(
                    onPressed: _loading ? null : _next,
                    child: _loading
                        ? const SizedBox(
                            width: 22, height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                        : Text(_step < 2 ? 'Continue' : 'Find Provider'),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _serviceHeader(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          ServiceImage(asStr(widget.service['id']), size: 52),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(asStr(widget.service['name']), style: t.titleMedium),
              Text(
                  widget.basePrice > 0
                      ? 'Estimate ₹${widget.basePrice} · final price agreed with provider'
                      : 'Price quoted by provider',
                  style: t.bodySmall?.copyWith(color: AppColors.muted)),
            ]),
          ),
        ]),
      ),
    );
  }

  List<Widget> _whenStep(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final w = _window;
    final hours = _hours;
    return [
      Text('When?', style: t.titleMedium),
      const SizedBox(height: 12),
      LayoutBuilder(builder: (ctx, c) {
        final cw = (c.maxWidth - 12) / 2;
        return Wrap(spacing: 12, runSpacing: 12, children: [
          for (final tw in _windows)
            SizedBox(width: cw, child: _windowCard(ctx, tw)),
        ]);
      }),
      if (!w.isAsap) ...[
        const SizedBox(height: 24),
        Text('Day', style: t.titleMedium),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (var i = 0; i < 3; i++)
            ChoiceChip(
              label: Text(_dayName(i)),
              selected: i == _selDay,
              onSelected: (_) => _pickDay(i),
            ),
        ]),
        const SizedBox(height: 20),
        DropdownButtonFormField<String>(
          key: ValueKey('hour-$_selWindow-$_selDay'),
          value: hours.contains(_selHour) ? _selHour : '',
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Preferred hour (optional)',
            prefixIcon: Icon(Icons.schedule_rounded),
          ),
          items: [
            const DropdownMenuItem(value: '', child: Text('Any time in this window')),
            ...hours.map((h) => DropdownMenuItem(value: h, child: Text(h))),
          ],
          onChanged: (v) => setState(() => _selHour = v ?? ''),
        ),
      ],
      const SizedBox(height: 16),
      InfoBanner(
        w.isAsap
            ? 'We will send the nearest available provider right away.'
            : '${_dayName(_selDay)}, ${w.sub} — the provider confirms the exact time.',
        icon: w.isAsap ? Icons.bolt_rounded : Icons.event_rounded,
      ),
    ];
  }

  Widget _windowCard(BuildContext context, _TimeWindow tw) {
    final t = Theme.of(context).textTheme;
    final open = _windowOpen(tw, _selDay);
    final sel = tw.key == _selWindow;
    return Opacity(
      opacity: open ? 1 : 0.45,
      child: Material(
        color: sel ? AppColors.tealSoft : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: sel ? AppColors.teal : AppColors.line, width: sel ? 2 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: open ? () => _pickWindow(tw.key) : null,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Icon(tw.icon, color: sel ? AppColors.teal2 : AppColors.muted),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tw.key,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.titleSmall?.copyWith(color: sel ? AppColors.teal2 : AppColors.ink)),
                  Text(tw.sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodySmall?.copyWith(color: AppColors.muted)),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  List<Widget> _addressStep(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final hasLoc = _customerLat != null;
    return [
      Card(
        color: hasLoc ? AppColors.greenSoft : AppColors.yellowSoft,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ListTile(
          leading: _locating
              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5))
              : Icon(hasLoc ? Icons.where_to_vote_rounded : Icons.location_off_outlined,
                  color: hasLoc ? AppColors.green : AppColors.yellow),
          title: Text(
            _locating
                ? 'Detecting your location…'
                : _pinnedOnMap
                    ? 'Location updated — pinned on map'
                    : hasLoc
                        ? 'Location updated'
                        : 'Location blocked — tap to retry (allow permission)',
            style: t.titleSmall?.copyWith(color: hasLoc ? AppColors.green : AppColors.yellow),
          ),
          trailing: hasLoc
              ? TextButton(onPressed: _openMapView, child: const Text('View'))
              : null,
          onTap: hasLoc || _locating ? null : _captureGPS,
        ),
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: _pinOnMap,
        icon: const Icon(Icons.map_outlined),
        label: const Text('Pin exact location on map'),
      ),
      const SizedBox(height: 20),
      TextField(
        controller: _addressCtrl,
        minLines: 2,
        maxLines: 3,
        decoration: const InputDecoration(
          labelText: 'Your location (auto-detected)',
          hintText: 'Street / building / area',
          prefixIcon: Icon(Icons.place_outlined),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _flatCtrl,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(
          labelText: 'Flat / Door No & Building *',
          hintText: 'e.g. Flat 302, Sai Residency',
          prefixIcon: Icon(Icons.apartment_rounded),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _landmarkCtrl,
        decoration: const InputDecoration(
          labelText: 'Landmark (optional)',
          hintText: 'Near school, temple, hospital…',
          prefixIcon: Icon(Icons.flag_outlined),
        ),
      ),
      const SizedBox(height: 24),
      Text('Contact', style: t.titleMedium),
      const SizedBox(height: 12),
      if (_contactKnown && !_editContact)
        Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            leading: const Icon(Icons.person_outline_rounded),
            title: Text(_nameCtrl.text.trim()),
            subtitle: Text(_phoneCtrl.text.trim()),
            trailing: TextButton(
              onPressed: () => setState(() => _editContact = true),
              child: const Text('Change'),
            ),
          ),
        )
      else ...[
        TextField(
          controller: _nameCtrl,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
              labelText: 'Full name', prefixIcon: Icon(Icons.person_outline_rounded)),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _phoneCtrl,
          keyboardType: TextInputType.phone,
          maxLength: 10,
          decoration: const InputDecoration(
            labelText: 'Mobile number *',
            hintText: '10-digit mobile',
            counterText: '',
            prefixIcon: Icon(Icons.phone_outlined),
          ),
        ),
      ],
      const SizedBox(height: 12),
      TextField(
        controller: _notesCtrl,
        minLines: 1,
        maxLines: 3,
        decoration: const InputDecoration(
          labelText: 'Notes for provider (optional)',
          prefixIcon: Icon(Icons.edit_note_rounded),
        ),
      ),
    ];
  }

  List<Widget> _confirmStep(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final landmark = _landmarkCtrl.text.trim();
    return [
      Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(children: [
            DetailRow(Icons.event_rounded, _whenSummary, label: 'When'),
            DetailRow(Icons.place_outlined,
                '$_fullAddress${landmark.isNotEmpty ? ' (near $landmark)' : ''}',
                label: 'Address'),
            DetailRow(Icons.person_outline_rounded,
                '${_nameCtrl.text.trim()} · ${_phoneCtrl.text.trim()}',
                label: 'Contact'),
          ]),
        ),
      ),
      if (widget.summary.isNotEmpty) ...[
        const SectionHeader('Selected', padding: EdgeInsets.fromLTRB(4, 20, 4, 8)),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final s in widget.summary)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.check_circle_rounded, size: 18, color: AppColors.teal),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                          s.contains(' > ') ? s.split(' > ').sublist(1).join(' > ') : s,
                          style: t.bodyMedium),
                    ),
                  ]),
                ),
            ]),
          ),
        ),
      ],
      const SizedBox(height: 16),
      Card(
        color: AppColors.tealSoft,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Expanded(child: Text('Estimated price', style: t.titleMedium?.copyWith(color: AppColors.teal2))),
            Text(widget.basePrice > 0 ? '₹${widget.basePrice}' : 'Quoted by provider',
                style: (widget.basePrice > 0 ? t.headlineSmall : t.titleMedium)
                    ?.copyWith(color: AppColors.teal2, fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      Text(
        'Nothing is charged now. A provider will quote the final price, which you accept in the app '
        'before work starts. You pay after the service is completed.',
        style: t.bodySmall?.copyWith(color: AppColors.muted, height: 1.4),
      ),
    ];
  }
}

/// Horizontal 3-step indicator under the app bar.
class _StepIndicator extends StatelessWidget {
  final int step;
  final List<String> labels;
  const _StepIndicator({required this.step, required this.labels});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final children = <Widget>[];
    for (var i = 0; i < labels.length; i++) {
      final done = i < step;
      final cur = i == step;
      children.add(Row(mainAxisSize: MainAxisSize.min, children: [
        CircleAvatar(
          radius: 12,
          backgroundColor: done || cur ? AppColors.teal : AppColors.line,
          foregroundColor: done || cur ? Colors.white : AppColors.muted,
          child: done
              ? const Icon(Icons.check_rounded, size: 16)
              : Text('${i + 1}', style: t.labelMedium?.copyWith(color: cur ? Colors.white : AppColors.muted)),
        ),
        const SizedBox(width: 6),
        Text(labels[i],
            style: t.labelLarge?.copyWith(
                color: cur ? AppColors.ink : AppColors.muted,
                fontWeight: cur ? FontWeight.w700 : FontWeight.w500)),
      ]));
      if (i < labels.length - 1) {
        children.add(Expanded(
          child: Container(
            height: 2,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            color: i < step ? AppColors.teal : AppColors.line,
          ),
        ));
      }
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Row(children: children),
    );
  }
}
