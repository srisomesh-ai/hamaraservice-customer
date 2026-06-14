import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../utils/theme.dart';
import '../booking/payment_screen.dart';

class MyBookingsScreen extends StatefulWidget {
  const MyBookingsScreen({super.key});
  @override
  State<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends State<MyBookingsScreen> {
  List<Map<String, dynamic>> _bookings = [];
  bool _loading = true;
  StreamSubscription? _listener;
  bool _showOtpPopup = false;
  String _otpCode = '';
  String _otpService = '';
  String _otpBookingId = '';
  final Map<String, StreamSubscription> _otpWatchers = {};
  final Map<String, StreamSubscription> _acceptWatchers = {};
  
  // In-app accepted alert
  bool _showAcceptedAlert = false;
  String _acceptedProviderName = '';
  String _acceptedProviderPhone = '';
  String _acceptedService = '';

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void dispose() {
    _listener?.cancel();
    for (final s in _otpWatchers.values) s.cancel();
    for (final s in _acceptWatchers.values) s.cancel();
    super.dispose();
  }

  void _listen() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _listener = FirebaseDatabase.instance.ref('bookings').onValue.listen((event) {
      if (!mounted) return;
      if (!event.snapshot.exists) {
        setState(() { _bookings = []; _loading = false; });
        return;
      }
      final all = Map<String, dynamic>.from(event.snapshot.value as Map);
      final activeStatuses = ['confirmed','searching','accepted','active','pending','otp_sent','payment_pending'];
      final mine = all.entries
          .where((e) {
            final b = e.value as Map;
            return b['customerId'] == uid && activeStatuses.contains(b['status']);
          })
          .map((e) => Map<String, dynamic>.from({...e.value as Map, 'id': e.key}))
          .toList()
        ..sort((a, b) => (b['createdAt'] ?? '').compareTo(a['createdAt'] ?? ''));

      setState(() { _bookings = mine; _loading = false; });

      for (final b in mine) {
        final id = b['id'] as String? ?? '';
        if (id.isEmpty) continue;
        if (['active','otp_sent','accepted'].contains(b['status'])) {
          _watchOTP(id, b['service'] ?? '');
        }
        // Watch acceptance for searching/pending
        // payment_pending is already handled by Pay Now button
        // Watch for acceptance
        if (b['status'] == 'searching' || b['status'] == 'pending') {
          _watchAcceptance(id, b);
        }
      }
    });
  }

  void _watchAcceptance(String bookingId, Map<String, dynamic> booking) {
    if (_acceptWatchers.containsKey(bookingId)) return;
    _acceptWatchers[bookingId] = FirebaseDatabase.instance
        .ref('active_bookings/$bookingId/status').onValue.listen((event) {
      if (!mounted) return;
      final status = event.snapshot.value?.toString() ?? '';
      if (status == 'accepted') {
        _acceptWatchers[bookingId]?.cancel();
        _acceptWatchers.remove(bookingId);
        // Get provider info and show alert
        FirebaseDatabase.instance.ref('active_bookings/$bookingId').get().then((snap) {
          if (!snap.exists || !mounted) return;
          final data = Map<String, dynamic>.from(snap.value as Map);
          final acceptedBy = data['acceptedBy'] as Map?;
          final providerName = data['providerName']?.toString() ?? acceptedBy?['name']?.toString() ?? 'Your provider';
          final providerPhone = acceptedBy?['phone']?.toString() ?? '';
          _showProviderAcceptedAlert(providerName, providerPhone, booking['service'] ?? '');
        });
      }
    });
  }

  void _showProviderAcceptedAlert(String name, String phone, String service) async {
    // Play sound + vibrate
    SystemSound.play(SystemSoundType.alert);
    HapticFeedback.heavyImpact();
    if (mounted) {
      setState(() {
        _showAcceptedAlert = true;
        _acceptedProviderName = name;
        _acceptedProviderPhone = phone;
        _acceptedService = service;
      });
    }
  }

  void _watchOTP(String bookingId, String service) {
    if (_otpWatchers.containsKey(bookingId)) return;
    _otpWatchers[bookingId] = FirebaseDatabase.instance
        .ref('job_otp/$bookingId').onValue.listen((event) {
      if (!event.snapshot.exists || !mounted) return;
      final data = Map<String, dynamic>.from(event.snapshot.value as Map);
      final status = data['status']?.toString() ?? '';
      final otp = data['otp']?.toString() ?? '';
      if (status == 'waiting' && otp.isNotEmpty) {
        setState(() { _showOtpPopup = true; _otpCode = otp; _otpBookingId = bookingId; _otpService = service; });
      } else if (status == 'verified') {
        setState(() => _showOtpPopup = false);
        final booking = _bookings.firstWhere((b) => b['id'] == bookingId, orElse: () => {});
        if (booking.isNotEmpty && mounted) {
          Navigator.push(context, MaterialPageRoute(
              builder: (_) => PaymentScreen(bookingId: bookingId, booking: booking)));
        }
      }
    });
  }

  Future<void> _cancelBooking(Map<String, dynamic> b) async {
    HapticFeedback.mediumImpact();
    final status = b['status'] as String? ?? '';
    final id = b['id'] as String? ?? '';
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
    reasonCtrl.dispose();
    if (confirmed != true || selectedReason == null) return;

    // Play cancel sound
    HapticFeedback.heavyImpact();

    final cancelReason = selectedReason == 'Other reason' && reasonCtrl.text.trim().isNotEmpty
        ? reasonCtrl.text.trim() : selectedReason!;
    final update = {
      'status': 'cancelled', 'cancelledAt': DateTime.now().toIso8601String(),
      'cancelledBy': 'customer', 'cancelReason': cancelReason,
    };
    if (['accepted','active'].contains(status)) {
      update['penalty'] = '20';
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      if (uid.isNotEmpty) {
        final snap = await FirebaseDatabase.instance.ref('customers/$uid/pendingPenalty').get();
        final existing = (snap.value as num?)?.toInt() ?? 0;
        await FirebaseDatabase.instance.ref('customers/$uid').update({'pendingPenalty': existing + 20});
      }
    }
    await FirebaseDatabase.instance.ref('bookings/$id').update(update);
    await FirebaseDatabase.instance.ref('active_bookings/$id').update({'status': 'cancelled', 'cancelledBy': 'customer'});
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(['accepted','active'].contains(status) ? 'Cancelled. Rs.20 penalty applied.' : 'Booking cancelled.'),
      backgroundColor: AppColors.red, duration: const Duration(seconds: 3)));
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
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(width: 80, height: 80,
          decoration: BoxDecoration(color: AppColors.tealSoft, shape: BoxShape.circle),
          child: const Icon(Icons.calendar_today_rounded, size: 40, color: AppColors.teal)),
        const SizedBox(height: 16),
        const Text('No Active Bookings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink)),
        const SizedBox(height: 8),
        const Text('Book a service from Home to get started!', style: TextStyle(color: AppColors.muted, fontSize: 13)),
      ]));
    }
    return RefreshIndicator(
      onRefresh: () async { _listen(); },
      color: AppColors.teal,
      child: ListView.builder(padding: const EdgeInsets.all(16),
        itemCount: _bookings.length, itemBuilder: (_, i) => _card(_bookings[i])));
  }

  Widget _card(Map<String, dynamic> b) {
    final status = b['status'] ?? '';
    final sc = _statusColor(status);
    final hasProvider = (b['providerName'] ?? '').toString().isNotEmpty;
    final canCancel = ['confirmed','searching','pending','accepted','active'].contains(status);
    final penalty = int.tryParse(b['penalty']?.toString() ?? '0') ?? 0;
    final id = (b['id'] ?? '').toString();
    final shortId = id.replaceAll('-','').length > 8 ? id.replaceAll('-','').substring(0,8).toUpperCase() : id.toUpperCase();

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10)]),
      child: Column(children: [
        Container(padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: sc.withOpacity(0.07),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16))),
          child: Row(children: [
            Text(b['icon'] ?? '🔧', style: const TextStyle(fontSize: 26)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(b['service'] ?? 'Service', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.ink)),
              Text('ID: $shortId', style: const TextStyle(fontSize: 10, color: AppColors.muted)),
            ])),
            Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: sc.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
              child: Text(_statusLabel(status), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: sc))),
          ])),
        Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _row(Icons.calendar_today_rounded, '${b['date'] ?? ''} at ${b['time'] ?? ''}'),
          const SizedBox(height: 5),
          _row(Icons.location_on_rounded, '${b['address'] ?? ''}${(b['landmark'] ?? '').toString().isNotEmpty ? '  (${b['landmark']})' : ''}'),
          const SizedBox(height: 5),
          _row(Icons.currency_rupee_rounded, 'Rs.${b['price'] ?? b['priceVal'] ?? 0}${penalty > 0 ? '  +  Rs.$penalty penalty' : ''}'),
          if (penalty > 0) ...[
            const SizedBox(height: 8),
            Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(color: AppColors.red.withOpacity(0.07), borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.red.withOpacity(0.2))),
              child: Row(children: [
                const Icon(Icons.warning_amber_rounded, color: AppColors.red, size: 14),
                const SizedBox(width: 6),
                Text('Rs.$penalty penalty — deducted from next payment',
                  style: const TextStyle(fontSize: 11, color: AppColors.red, fontWeight: FontWeight.w600)),
              ])),
          ],
          if (hasProvider) ...[
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
                  Text(b['providerName'] ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink)),
                  if ((b['acceptedBy'] as Map?)?['phone']?.toString().isNotEmpty == true)
                    Text((b['acceptedBy'] as Map)['phone'], style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                ])),
                if ((b['acceptedBy'] as Map?)?['phone']?.toString().isNotEmpty == true)
                  GestureDetector(
                    onTap: () { HapticFeedback.mediumImpact(); launchUrl(Uri.parse('tel:${(b['acceptedBy'] as Map)['phone']}')); },
                    child: Container(width: 38, height: 38,
                      decoration: const BoxDecoration(color: AppColors.green, shape: BoxShape.circle),
                      child: const Icon(Icons.phone_rounded, color: Colors.white, size: 18))),
              ])),
          ],
          if (status == 'otp_sent') ...[
            const SizedBox(height: 10),
            Container(padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.brand.withOpacity(0.08), borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.brand.withOpacity(0.3))),
              child: const Row(children: [
                Icon(Icons.lock_rounded, color: AppColors.brand, size: 16),
                SizedBox(width: 8),
                Expanded(child: Text('Provider requesting OTP — check popup above',
                  style: TextStyle(fontSize: 12, color: AppColors.brand, fontWeight: FontWeight.w600))),
              ])),
          ],
          // Payment pending — show Pay Now button
          if (status == 'payment_pending') ...[
            const SizedBox(height: 10),
            Container(padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.yellow.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.yellow.withOpacity(0.4))),
              child: const Row(children: [
                Icon(Icons.hourglass_top_rounded, color: AppColors.yellow, size: 16),
                SizedBox(width: 8),
                Expanded(child: Text('Service completed! Please complete your payment.',
                  style: TextStyle(fontSize: 12, color: AppColors.ink2, fontWeight: FontWeight.w600))),
              ])),
            const SizedBox(height: 8),
            SizedBox(width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  Navigator.push(context, MaterialPageRoute(
                    builder: (_) => PaymentScreen(bookingId: b['id'], booking: b)));
                },
                icon: const Icon(Icons.payment_rounded, color: Colors.white, size: 18),
                label: Text('Pay Rs.\${b['price'] ?? b['priceVal'] ?? 0} Now',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE8251A),
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))))),
          ],

          if (canCancel) ...[
            const SizedBox(height: 10),
            SizedBox(width: double.infinity,
              child: OutlinedButton(
                onPressed: () => _cancelBooking(b),
                style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.red),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  minimumSize: const Size(double.infinity, 38)),
                child: Text(['accepted','active'].contains(status) ? 'Cancel Booking (Rs.20 penalty)' : 'Cancel Booking',
                  style: const TextStyle(color: AppColors.red, fontWeight: FontWeight.w700, fontSize: 13)))),
          ],
        ])),
      ]),
    );
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
      case 'searching': case 'pending': return AppColors.yellow;
      case 'accepted': return AppColors.green;
      case 'active': case 'otp_sent': return AppColors.brand;
      case 'payment_pending': return AppColors.yellow;
      default: return AppColors.muted;
    }
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'confirmed': return 'Confirmed';
      case 'searching': return 'Searching';
      case 'pending': return 'Pending';
      case 'accepted': return 'Provider Assigned';
      case 'active': return 'In Progress';
      case 'otp_sent': return 'Completing';
      case 'payment_pending': return '⏳ Payment Pending';
      default: return s;
    }
  }
}
