import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/api_service.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../utils/theme.dart';
import '../../utils/booking_utils.dart';
import '../booking/payment_screen.dart';

/// "Active" bookings tab. Lists the customer's bookings (customers.php
/// `bookings`) and polls bookings.php `get` for each live one to show the
/// start / completion OTP, provider location and the payment action.
class MyBookingsScreen extends StatefulWidget {
  const MyBookingsScreen({super.key});
  @override
  State<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends State<MyBookingsScreen> {
  List<Map<String, dynamic>> _bookings = [];
  // Full rows from bookings.php `get` (OTPs, provider location, …) by id.
  final Map<String, Map<String, dynamic>> _details = {};
  bool _loading = true;
  StreamSubscription? _listener;
  bool _polling = false;

  bool _showOtpPopup = false;
  String _otpCode = '';
  String _otpService = '';
  // "<bookingId>:<otp>" already popped up, so a dismissed popup stays closed.
  final Set<String> _otpShown = {};

  // Last seen status per booking, to detect "provider accepted".
  final Map<String, String> _lastStatus = {};
  final Set<String> _busy = {};

  // In-app accepted alert
  bool _showAcceptedAlert = false;
  String _acceptedProviderName = '';
  String _acceptedProviderPhone = '';
  String _acceptedService = '';

  static const _liveStatuses = {
    'searching', 'price_quoted', 'negotiating', 'negotiation_final',
    'confirmed', 'active',
  };

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void dispose() {
    _listener?.cancel();
    super.dispose();
  }

  void _listen() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _loading = false;
      return;
    }
    _loadBookings(uid);
    // Never stack pollers: cancel any previous periodic stream first.
    _listener?.cancel();
    _listener = Stream.periodic(const Duration(seconds: 5))
        .listen((_) => _loadBookings(uid));
  }

  Future<void> _refresh() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await _loadBookings(uid);
  }

  /// Bookings that belong on the Active tab: in progress, or completed but
  /// not yet paid (so the customer can still pay).
  static bool _isActiveTab(Map<String, dynamic> b) {
    final st = b['status']?.toString() ?? '';
    if (_liveStatuses.contains(st)) return true;
    return st == 'completed' && (b['payment_status']?.toString() ?? '') != 'paid';
  }

  Future<void> _loadBookings(String uid) async {
    if (_polling) return;
    _polling = true;
    try {
      final list = (await ApiService.getCustomerBookings(uid))
          .where(_isActiveTab).toList();
      // Refresh details for each active booking (a handful at most).
      final ids = list.map((b) => b['id']?.toString() ?? '').where((id) => id.isNotEmpty).take(8).toList();
      final fetched = await Future.wait(ids.map((id) async => MapEntry(id, await ApiService.getBooking(id))));
      if (!mounted) return;
      setState(() {
        _bookings = list;
        _details.removeWhere((k, _) => !ids.contains(k));
        for (final e in fetched) {
          if (e.value != null) _details[e.key] = e.value!;
        }
        _loading = false;
      });
      for (final b in list) {
        _checkTransitions(_merged(b));
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    } finally {
      _polling = false;
    }
  }

  Map<String, dynamic> _merged(Map<String, dynamic> b) {
    final id = b['id']?.toString() ?? '';
    return {...b, ...?_details[id]};
  }

  void _checkTransitions(Map<String, dynamic> d) {
    final id = d['id']?.toString() ?? '';
    final status = d['status']?.toString() ?? '';
    final prev = _lastStatus[id];
    _lastStatus[id] = status;
    final service = BookingUtils.str(d, ['svc_name'], 'your service');

    if (prev == 'searching' && status == 'price_quoted') {
      _showProviderAcceptedAlert(
          BookingUtils.str(d, ['provider_name'], 'Your provider'),
          BookingUtils.str(d, ['provider_phone']), service);
    }

    final cotp = BookingUtils.completionOtp(d);
    if (cotp.isNotEmpty && _otpShown.add('$id:$cotp')) {
      HapticFeedback.heavyImpact();
      setState(() { _showOtpPopup = true; _otpCode = cotp; _otpService = service; });
    }
  }

  void _showProviderAcceptedAlert(String name, String phone, String service) async {
    // Vibrate + sound
    try {
      final hasVib = await Vibration.hasVibrator() ?? false;
      if (hasVib) Vibration.vibrate(pattern: [0, 400, 200, 400, 200, 400]);
    } catch (_) {}
    HapticFeedback.heavyImpact();
    SystemSound.play(SystemSoundType.alert);
    if (mounted) {
      setState(() {
        _showAcceptedAlert = true;
        _acceptedProviderName = name;
        _acceptedProviderPhone = phone;
        _acceptedService = service;
      });
    }
  }

  void _openPayment(Map<String, dynamic> d) {
    final id = d['id']?.toString() ?? '';
    if (id.isEmpty || !PaymentScreen.reserve(id)) return;
    HapticFeedback.mediumImpact();
    Navigator.push(context, MaterialPageRoute(
        builder: (_) => PaymentScreen(bookingId: id, booking: d)))
      .then((_) => _refresh());
  }

  Future<void> _acceptQuote(Map<String, dynamic> d, int price) async {
    final id = d['id']?.toString() ?? '';
    if (id.isEmpty || !_busy.add(id)) return;
    setState(() {});
    final res = await ApiService.confirmPrice(id, price);
    _busy.remove(id);
    if (!mounted) return;
    if (res == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Could not confirm the price. Please try again.'),
        backgroundColor: AppColors.red));
    }
    await _refresh();
  }

  Future<void> _generateStartOtp(Map<String, dynamic> d) async {
    final id = d['id']?.toString() ?? '';
    if (id.isEmpty || !_busy.add(id)) return;
    setState(() {});
    final otp = await ApiService.generateStartOtp(id);
    _busy.remove(id);
    if (!mounted) return;
    if (otp == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Could not get the start OTP. Please try again.'),
        backgroundColor: AppColors.red));
    }
    await _refresh();
  }

  Future<void> _cancelBooking(Map<String, dynamic> b) async {
    HapticFeedback.mediumImpact();
    final status = b['status']?.toString() ?? '';
    final id = b['id']?.toString() ?? '';
    if (id.isEmpty) return;
    String? selectedReason;
    final reasonCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context, barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(children: [
            Icon(['accepted','active'].contains(status) ? Icons.warning_amber_rounded : Icons.cancel_outlined,
                color: AppColors.red, size: 24),
            const SizedBox(width: 8),
            const Expanded(child: Text('Cancel Booking', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
          ]),
          content: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (['accepted','active'].contains(status)) ...[
                Container(padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AppColors.red.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.red.withOpacity(0.3))),
                  child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Rs.20 Penalty', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.red, fontSize: 13)),
                    SizedBox(height: 4),
                    Text('Provider already accepted. Rs.20 deducted from next payment.',
                        style: TextStyle(fontSize: 12, color: AppColors.ink2, height: 1.4)),
                  ])),
                const SizedBox(height: 12),
              ],
              const Text('Reason:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink)),
              const SizedBox(height: 8),
              ...['Found another provider','Service no longer needed','Wrong service selected',
                  'Provider taking too long','Other reason'].map((r) => RadioListTile<String>(
                value: r, groupValue: selectedReason, dense: true, contentPadding: EdgeInsets.zero,
                title: Text(r, style: const TextStyle(fontSize: 13)),
                activeColor: AppColors.teal,
                onChanged: (v) => setS(() => selectedReason = v))),
              if (selectedReason == 'Other reason') ...[
                const SizedBox(height: 8),
                TextField(controller: reasonCtrl, maxLines: 2,
                  decoration: InputDecoration(hintText: 'Tell us more...',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.all(10))),
              ],
            ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep Booking', style: TextStyle(color: AppColors.teal, fontWeight: FontWeight.w700))),
            ElevatedButton(
              onPressed: selectedReason == null ? null : () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.red,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              child: Text(['accepted','active'].contains(status) ? 'Cancel (+Rs.20)' : 'Confirm Cancel',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
          ],
        ),
      ),
    );
    // Read the free-text reason BEFORE disposing its controller.
    final otherText = reasonCtrl.text.trim();
    reasonCtrl.dispose();
    if (confirmed != true || selectedReason == null) return;

    // Play cancel sound
    HapticFeedback.heavyImpact();

    final cancelReason = selectedReason == 'Other reason' && otherText.isNotEmpty
        ? otherText : selectedReason!;
    final ok = await ApiService.cancelBooking(id, reason: cancelReason);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Could not cancel booking. Please try again.'),
        backgroundColor: AppColors.red, duration: Duration(seconds: 3)));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('Booking cancelled.'),
      backgroundColor: AppColors.red, duration: const Duration(seconds: 3)));
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      _buildList(),
      if (_showOtpPopup) _buildOtpPopup(),
      if (_showAcceptedAlert) _buildAcceptedAlert(),
    ]);
  }

  Widget _buildList() {
    if (_loading) return const Center(child: CircularProgressIndicator(color: AppColors.teal));
    if (_bookings.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        color: AppColors.teal,
        child: ListView(children: [
          const SizedBox(height: 120),
          Center(child: Container(width: 80, height: 80,
            decoration: const BoxDecoration(color: AppColors.tealSoft, shape: BoxShape.circle),
            child: const Icon(Icons.calendar_today_rounded, size: 40, color: AppColors.teal))),
          const SizedBox(height: 16),
          const Center(child: Text('No Active Bookings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink))),
          const SizedBox(height: 8),
          const Center(child: Text('Book a service from Home to get started!', style: TextStyle(color: AppColors.muted, fontSize: 13))),
        ]));
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      color: AppColors.teal,
      child: ListView.builder(padding: const EdgeInsets.all(16),
        itemCount: _bookings.length, itemBuilder: (_, i) => _card(_merged(_bookings[i]))));
  }

  Widget _card(Map<String, dynamic> b) {
    final status = b['status']?.toString() ?? '';
    final payStatus = b['payment_status']?.toString() ?? '';
    final sc = _statusColor(status);
    final providerName = BookingUtils.str(b, ['provider_name']);
    final providerPhone = BookingUtils.str(b, ['provider_phone']);
    final canCancel = ['searching','price_quoted','negotiating','negotiation_final','confirmed','active'].contains(status);
    final id = (b['id'] ?? '').toString();
    final busy = _busy.contains(id);
    final shortId = id.replaceAll('-','').length > 8 ? id.replaceAll('-','').substring(0,8).toUpperCase() : id.toUpperCase();
    final amount = BookingUtils.amount(b);
    final slot = [BookingUtils.str(b, ['slot_date']), BookingUtils.str(b, ['slot_time'])]
        .where((x) => x.isNotEmpty).join(' at ');
    final startOtp = BookingUtils.startOtp(b);
    final completionOtp = BookingUtils.completionOtp(b);
    final distKm = BookingUtils.providerDistanceKm(b);
    final mapsUri = BookingUtils.providerMapsUri(b);
    final liveLoc = BookingUtils.str(b, ['provider_loc_at']).isNotEmpty;
    final payable = PaymentScreen.isPayable(b);
    final quote = status == 'negotiation_final'
        ? (num.tryParse(b['final_price']?.toString() ?? '')?.toInt() ?? 0)
        : status == 'price_quoted'
            ? (num.tryParse(b['quoted_price']?.toString() ?? '')?.toInt() ?? 0)
            : 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10)]),
      child: Column(children: [
        Container(padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: sc.withOpacity(0.07),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16))),
          child: Row(children: [
            Text(BookingUtils.str(b, ['svc_icon'], '🔧'), style: const TextStyle(fontSize: 26)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(BookingUtils.str(b, ['svc_name'], 'Service'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.ink)),
              Text('ID: $shortId', style: const TextStyle(fontSize: 10, color: AppColors.muted)),
            ])),
            Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: sc.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
              child: Text(_statusLabel(status), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: sc))),
          ])),
        Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (slot.isNotEmpty) ...[
            _row(Icons.calendar_today_rounded, slot),
            const SizedBox(height: 5),
          ],
          _row(Icons.location_on_rounded, BookingUtils.str(b, ['address'])),
          if (amount > 0) ...[
            const SizedBox(height: 5),
            _row(Icons.currency_rupee_rounded, '₹$amount'),
          ],
          if (providerName.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.greenSoft, borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.green.withOpacity(0.3))),
              child: Row(children: [
                Container(width: 36, height: 36,
                  decoration: BoxDecoration(color: AppColors.green.withOpacity(0.2), shape: BoxShape.circle),
                  child: const Icon(Icons.person_rounded, color: AppColors.green, size: 20)),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Your Provider', style: TextStyle(fontSize: 11, color: AppColors.green, fontWeight: FontWeight.w700)),
                  Text(providerName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink)),
                  if (providerPhone.isNotEmpty)
                    Text(providerPhone, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                ])),
                if (providerPhone.isNotEmpty)
                  GestureDetector(
                    onTap: () { HapticFeedback.mediumImpact(); launchUrl(Uri.parse('tel:$providerPhone')); },
                    child: Container(width: 38, height: 38,
                      decoration: const BoxDecoration(color: AppColors.green, shape: BoxShape.circle),
                      child: const Icon(Icons.phone_rounded, color: Colors.white, size: 18))),
              ])),
          ],

          // Provider quote waiting for the customer
          if (quote > 0) ...[
            const SizedBox(height: 10),
            _notice(Icons.local_offer_rounded, AppColors.teal,
                status == 'negotiation_final'
                    ? 'Final offer from provider: ₹$quote'
                    : 'Provider quoted ₹$quote'),
            const SizedBox(height: 8),
            _primaryButton(busy ? 'Please wait…' : 'Accept ₹$quote', Icons.check_rounded, AppColors.teal,
                busy ? null : () => _acceptQuote(b, quote)),
          ],
          if (status == 'negotiating') ...[
            const SizedBox(height: 10),
            _notice(Icons.forum_rounded, AppColors.brand, 'Waiting for the provider to reply to your offer…'),
          ],

          // Start OTP — share when the provider arrives
          if (status == 'confirmed') ...[
            const SizedBox(height: 10),
            if (startOtp.isNotEmpty)
              _otpBox('START OTP', startOtp, 'Share this with your provider when they arrive to start the job.', AppColors.teal)
            else
              _primaryButton(busy ? 'Please wait…' : 'Get Start OTP', Icons.key_rounded, AppColors.teal,
                  busy ? null : () => _generateStartOtp(b)),
          ],

          // Completion OTP — share only when satisfied
          if (completionOtp.isNotEmpty) ...[
            const SizedBox(height: 10),
            _otpBox('COMPLETION OTP', completionOtp, 'Share only after the work is done to your satisfaction.', AppColors.green),
          ],

          // Live tracking
          if (mapsUri != null) ...[
            const SizedBox(height: 10),
            Container(padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.tealSoft, borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                const Icon(Icons.near_me_rounded, color: AppColors.teal, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(
                  distKm != null
                      ? 'Provider is ${distKm < 1 ? '${(distKm * 1000).round()} m' : '${distKm.toStringAsFixed(1)} km'} away'
                          '${liveLoc ? '' : ' (approx.)'}'
                      : 'See where your provider is',
                  style: const TextStyle(fontSize: 12, color: AppColors.ink2, fontWeight: FontWeight.w600))),
                TextButton.icon(
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    launchUrl(mapsUri, mode: LaunchMode.externalApplication);
                  },
                  icon: const Icon(Icons.map_rounded, size: 16, color: AppColors.teal),
                  label: const Text('Map', style: TextStyle(color: AppColors.teal, fontWeight: FontWeight.w700))),
              ])),
          ],

          // Payment
          if (payStatus == 'cash_pending') ...[
            const SizedBox(height: 10),
            _notice(Icons.hourglass_top_rounded, AppColors.yellow,
                'Cash payment recorded — awaiting provider confirmation.'),
          ] else if (payStatus == 'paid') ...[
            const SizedBox(height: 10),
            _notice(Icons.verified_rounded, AppColors.green, 'Paid'),
          ] else if (payable) ...[
            const SizedBox(height: 10),
            if (status == 'completed')
              _notice(Icons.hourglass_top_rounded, AppColors.yellow, 'Service completed! Please complete your payment.'),
            const SizedBox(height: 8),
            _primaryButton('Pay ₹$amount', Icons.payment_rounded, const Color(0xFFE8251A), () => _openPayment(b)),
          ],

          if (canCancel) ...[
            const SizedBox(height: 10),
            SizedBox(width: double.infinity,
              child: OutlinedButton(
                onPressed: () => _cancelBooking(b),
                style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.red),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  minimumSize: const Size(double.infinity, 38)),
                child: Text('Cancel Booking',
                  style: const TextStyle(color: AppColors.red, fontWeight: FontWeight.w700, fontSize: 13)))),
          ],
        ])),
      ]),
    );
  }

  Widget _notice(IconData icon, Color color, String text) {
    return Container(padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.35))),
      child: Row(children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 12, color: AppColors.ink2, fontWeight: FontWeight.w600))),
      ]));
  }

  Widget _primaryButton(String label, IconData icon, Color color, VoidCallback? onPressed) {
    return SizedBox(width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, color: Colors.white, size: 18),
        label: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white)),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          minimumSize: const Size(double.infinity, 46),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))));
  }

  Widget _otpBox(String title, String code, String hint, Color color) {
    return Container(width: double.infinity, padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withOpacity(0.06), borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.4))),
      child: Column(children: [
        Text(title, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color, letterSpacing: 1)),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.center,
          children: code.split('').map((d) => Container(
            width: 40, height: 48, margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color, width: 1.5)),
            child: Center(child: Text(d, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppColors.ink))))).toList()),
        const SizedBox(height: 8),
        Text(hint, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: AppColors.ink2)),
      ]));
  }

  // Provider accepted in-app alert
  Widget _buildAcceptedAlert() {
    return Container(
      color: Colors.black.withOpacity(0.7),
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 30)]),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [Color(0xFF1B5E20), AppColors.green],
                  begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
              child: Column(children: [
                const Text('🎉', style: TextStyle(fontSize: 48)),
                const SizedBox(height: 8),
                const Text('Provider Accepted!', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
                Text('$_acceptedService is confirmed', style: const TextStyle(fontSize: 13, color: Colors.white70)),
              ])),
            Padding(padding: const EdgeInsets.all(20), child: Column(children: [
              Container(padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: AppColors.greenSoft, borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.green.withOpacity(0.3))),
                child: Row(children: [
                  Container(width: 44, height: 44,
                    decoration: BoxDecoration(color: AppColors.green.withOpacity(0.2), shape: BoxShape.circle),
                    child: const Icon(Icons.person_rounded, color: AppColors.green, size: 24)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Your Provider', style: TextStyle(fontSize: 11, color: AppColors.green, fontWeight: FontWeight.w700)),
                    Text(_acceptedProviderName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink)),
                    if (_acceptedProviderPhone.isNotEmpty)
                      Text(_acceptedProviderPhone, style: const TextStyle(fontSize: 13, color: AppColors.muted)),
                  ])),
                  if (_acceptedProviderPhone.isNotEmpty)
                    GestureDetector(
                      onTap: () { HapticFeedback.mediumImpact(); launchUrl(Uri.parse('tel:$_acceptedProviderPhone')); },
                      child: Container(width: 44, height: 44,
                        decoration: const BoxDecoration(color: AppColors.green, shape: BoxShape.circle),
                        child: const Icon(Icons.phone_rounded, color: Colors.white, size: 22))),
                ])),
              const SizedBox(height: 16),
              const Text('Your provider is on the way! You can call them if needed.',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: AppColors.muted)),
              const SizedBox(height: 16),
              SizedBox(width: double.infinity,
                child: ElevatedButton(
                  onPressed: () { HapticFeedback.mediumImpact(); setState(() => _showAcceptedAlert = false); },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.green,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                  child: const Text('Great, Got It!', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)))),
            ])),
          ]),
        ),
      ),
    );
  }

  Widget _buildOtpPopup() {
    return Container(
      color: Colors.black.withOpacity(0.7),
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 30)]),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [AppColors.green, Color(0xFF34d058)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
              child: Column(children: [
                const Icon(Icons.lock_rounded, color: Colors.white, size: 36),
                const SizedBox(height: 8),
                const Text('Job Completion OTP', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
                Text('Share with provider to complete $_otpService',
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Colors.white70)),
              ])),
            Padding(padding: const EdgeInsets.all(24), child: Column(children: [
              const Text('YOUR OTP CODE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.muted, letterSpacing: 1)),
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.center,
                children: _otpCode.split('').map((d) => Container(
                  width: 56, height: 64, margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.green, width: 2)),
                  child: Center(child: Text(d, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: AppColors.ink))))).toList()),
              const SizedBox(height: 16),
              Container(padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.yellow.withOpacity(0.1), borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.yellow.withOpacity(0.3))),
                child: const Row(children: [
                  Icon(Icons.warning_amber_rounded, color: AppColors.yellow, size: 16),
                  SizedBox(width: 8),
                  Expanded(child: Text('Only share after service is completed to your satisfaction.',
                    style: TextStyle(fontSize: 11, color: AppColors.ink2))),
                ])),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => setState(() => _showOtpPopup = false),
                child: const Text('Close', style: TextStyle(color: AppColors.muted, fontSize: 13))),
            ])),
          ]),
        ),
      ),
    );
  }

  Widget _row(IconData icon, String text) {
    return Row(children: [
      Icon(icon, size: 14, color: AppColors.teal),
      const SizedBox(width: 8),
      Expanded(child: Text(text, style: const TextStyle(fontSize: 13, color: AppColors.ink2))),
    ]);
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'confirmed': return AppColors.teal;
      case 'searching': return AppColors.yellow;
      case 'price_quoted': case 'negotiating': case 'negotiation_final': return AppColors.green;
      case 'active': return AppColors.brand;
      case 'completed': return AppColors.yellow;
      default: return AppColors.muted;
    }
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'searching': return 'Searching';
      case 'price_quoted': return 'Quote Received';
      case 'negotiating': return 'Negotiating';
      case 'negotiation_final': return 'Final Offer';
      case 'confirmed': return 'Confirmed';
      case 'active': return 'In Progress';
      case 'completed': return 'Payment Pending';
      default: return s;
    }
  }
}
