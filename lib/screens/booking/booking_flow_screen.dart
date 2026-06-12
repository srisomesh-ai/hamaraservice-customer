import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../utils/theme.dart';
import '../../services/firebase_service.dart';
import 'radar_screen.dart';

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
  final _addressCtrl = TextEditingController();
  final _landmarkCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  bool _loading = false;
  bool _detectingLocation = false;
  double? _customerLat;
  double? _customerLng;

  final List<String> _timeSlots = [
    '07:00 AM','08:00 AM','09:00 AM','10:00 AM',
    '11:00 AM','12:00 PM','01:00 PM','02:00 PM',
    '03:00 PM','04:00 PM','05:00 PM','06:00 PM',
  ];
  String _selectedSlot = '09:00 AM';

  @override
  void initState() {
    super.initState();
    _loadNamePhone();
    _getLocation();
  }

  @override
  void dispose() {
    _addressCtrl.dispose();
    _landmarkCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _getLocation() async {
    setState(() { _detectingLocation = true; _addressCtrl.clear(); });
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        setState(() => _detectingLocation = false);
        return;
      }
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      setState(() { _customerLat = pos.latitude; _customerLng = pos.longitude; });
      try {
        final placemarks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          final parts = [p.name, p.street, p.subLocality, p.locality, p.administrativeArea]
              .where((s) => s != null && s.isNotEmpty && s != p.locality).toList();
          final addr = '${parts.join(', ')}, ${p.locality ?? ''}, ${p.administrativeArea ?? ''}';
          // Always set GPS address — never use old saved address
          if (mounted) setState(() => _addressCtrl.text = addr.trim().replaceAll(', ,', ','));
        }
      } catch (e) {}
    } catch (e) {}
    if (mounted) setState(() => _detectingLocation = false);
  }

  Future<void> _loadNamePhone() async {
    final user = FirebaseAuth.instance.currentUser;
    _nameCtrl.text = user?.displayName ?? '';
    try {
      final snap = await FirebaseDatabase.instance.ref('customers/${user?.uid}').get();
      if (snap.exists) {
        final data = Map<String, dynamic>.from(snap.value as Map);
        if (_nameCtrl.text.isEmpty) _nameCtrl.text = data['name'] ?? '';
        _phoneCtrl.text = data['phone'] ?? user?.phoneNumber ?? '';
      }
    } catch (e) {}
  }

  void _openMapView() {
    if (_customerLat == null || _customerLng == null) return;
    // Open Google Maps at detected location so user can verify
    launchUrl(Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=$_customerLat,$_customerLng'));
  }

  Future<void> _confirmBooking() async {
    HapticFeedback.mediumImpact();
    if (_addressCtrl.text.trim().isEmpty) {
      _showError('Please enter your address'); return;
    }
    if (_landmarkCtrl.text.trim().isEmpty) {
      _showError('Landmark is required — helps provider find you'); return;
    }
    if (_nameCtrl.text.trim().isEmpty || _phoneCtrl.text.trim().isEmpty) {
      _showError('Please enter your name and mobile number'); return;
    }
    if (_phoneCtrl.text.trim().length < 10) {
      _showError('Please enter a valid 10-digit mobile number'); return;
    }

    setState(() => _loading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      final bookingId = await FirebaseService.createBooking({
        'service': widget.service['name'],
        'svcId': widget.service['id'],
        'icon': widget.service['icon'],
        'price': widget.basePrice,
        'priceVal': widget.basePrice,
        'date': '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2,'0')}-${_selectedDate.day.toString().padLeft(2,'0')}',
        'time': _selectedSlot,
        'address': _addressCtrl.text.trim(),
        'landmark': _landmarkCtrl.text.trim(),
        'customer': _nameCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'customerId': user?.uid ?? '',
        'customerEmail': user?.email ?? '',
        'status': 'searching',
        'lat': _customerLat ?? 0.0,
        'lng': _customerLng ?? 0.0,
        'summary': widget.summary.isNotEmpty ? widget.summary : ['${widget.service['name']} > Service booking'],
      });
      if (mounted) {
        Navigator.pushReplacement(context, MaterialPageRoute(
          builder: (_) => RadarScreen(
            bookingId: bookingId, service: widget.service,
            date: _selectedDate, timeSlot: _selectedSlot,
            address: _addressCtrl.text.trim(), price: widget.basePrice,
            lat: _customerLat, lng: _customerLng)));
      }
    } catch (e) {
      setState(() => _loading = false);
      _showError('Booking failed. Please try again.');
    }
  }

  void _showError(String msg) {
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
                if (_step < 2) setState(() => _step++); else _confirmBooking();
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
          onDateChanged: (d) { HapticFeedback.selectionClick(); setState(() => _selectedDate = d); })),
      const SizedBox(height: 20),
      const Text('Select Time Slot', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink)),
      const SizedBox(height: 12),
      Wrap(spacing: 10, runSpacing: 10,
        children: _timeSlots.map((slot) {
          final sel = slot == _selectedSlot;
          return GestureDetector(
            onTap: () { HapticFeedback.selectionClick(); setState(() => _selectedSlot = slot); },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: sel ? AppColors.teal : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: sel ? AppColors.teal : AppColors.line)),
              child: Text(slot, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                color: sel ? Colors.white : AppColors.ink2))));
        }).toList()),
    ]);
  }

  Widget _buildAddressStep() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Service Address', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink)),
      const Text('Where should the provider come?', style: TextStyle(fontSize: 13, color: AppColors.muted)),
      const SizedBox(height: 14),

      // GPS detect button
      GestureDetector(
        onTap: _detectingLocation ? null : _getLocation,
        child: Container(padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _customerLat != null ? AppColors.greenSoft : AppColors.tealSoft,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _customerLat != null ? AppColors.green : AppColors.teal)),
          child: Row(children: [
            _detectingLocation
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.teal))
                : Icon(_customerLat != null ? Icons.location_on_rounded : Icons.my_location_rounded,
                    color: _customerLat != null ? AppColors.green : AppColors.teal, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(
              _detectingLocation ? 'Detecting your location...' :
              _customerLat != null ? 'GPS detected — tap to refresh' : 'Tap to detect current location',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                color: _customerLat != null ? AppColors.green : AppColors.teal))),
            // Map view button
            if (_customerLat != null && !_detectingLocation)
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
      ),

      const SizedBox(height: 14),
      _label('FULL ADDRESS *'),
      const SizedBox(height: 6),
      TextField(controller: _addressCtrl, maxLines: 3,
        decoration: InputDecoration(hintText: 'House no, Street, Area, City',
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
      const SizedBox(height: 12),
      _label('FULL NAME *'),
      const SizedBox(height: 6),
      TextField(controller: _nameCtrl,
        decoration: InputDecoration(hintText: 'Your name',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
      const SizedBox(height: 14),
      _label('MOBILE NUMBER *'),
      const SizedBox(height: 6),
      TextField(controller: _phoneCtrl, keyboardType: TextInputType.phone, maxLength: 10,
        decoration: InputDecoration(hintText: '10-digit mobile number',
          counterText: '',
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
            decoration: BoxDecoration(color: Color(widget.service['color'] as int), borderRadius: BorderRadius.circular(12)),
            child: Center(child: Text(widget.service['icon'] as String, style: const TextStyle(fontSize: 28)))),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.service['name'] as String, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.ink)),
            Text(widget.service['cat'] as String, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          ])),
          Text('Rs.${widget.basePrice}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.teal)),
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
          const Text('Total Amount', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.teal)),
          Text('Rs.${widget.basePrice}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.teal)),
        ])),
      const SizedBox(height: 8),
      const Text('Payment collected after service completion.', style: TextStyle(fontSize: 12, color: AppColors.muted)),
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
