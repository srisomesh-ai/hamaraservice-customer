import 'dart:async';
import 'package:flutter/material.dart';
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
  List<Map<String, dynamic>> _active = [];
  List<Map<String, dynamic>> _history = [];
  bool _loading = true;
  String _historyFilter = 'all';
  final Map<String, StreamSubscription> _otpWatchers = {};
  bool _showOtpPopup = false;
  String _otpCode = '';
  String _otpBookingId = '';
  String _otpService = '';

  @override
  void initState() {
    super.initState();
    _loadBookings();
  }

  @override
  void dispose() {
    for (final sub in _otpWatchers.values) sub.cancel();
    super.dispose();
  }

  Future<void> _loadBookings() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _loading = true);
    try {
      final snap = await FirebaseDatabase.instance.ref('bookings').get();
      if (!snap.exists) { setState(() => _loading = false); return; }
      final all = Map<String, dynamic>.from(snap.value as Map);
      final mine = all.entries
          .where((e) => (e.value as Map)['customerId'] == uid)
          .map((e) => Map<String, dynamic>.from({...e.value as Map, 'id': e.key}))
          .toList()
        ..sort((a, b) => (b['createdAt'] ?? '').compareTo(a['createdAt'] ?? ''));

      final activeStatuses = ['confirmed','searching','accepted','active','pending','otp_sent'];
      final historyStatuses = ['completed','cancelled'];

      setState(() {
        _active = mine.where((b) => activeStatuses.contains(b['status'])).toList();
        _history = mine.where((b) => historyStatuses.contains(b['status'])).toList();
        _loading = false;
      });

      // Watch OTP for active bookings
      for (final b in _active) {
        final id = b['id'] as String? ?? '';
        if (['active','otp_sent','accepted'].contains(b['status']) && id.isNotEmpty) {
          _watchOTP(id, b['service'] ?? '');
        }
      }
    } catch (e) {
      setState(() => _loading = false);
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
        setState(() {
          _showOtpPopup = true;
          _otpCode = otp;
          _otpBookingId = bookingId;
          _otpService = service;
        });
      } else if (status == 'verified') {
        setState(() => _showOtpPopup = false);
        final booking = _active.firstWhere((b) => b['id'] == bookingId, orElse: () => {});
        if (booking.isNotEmpty && mounted) {
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => PaymentScreen(bookingId: bookingId, booking: booking)));
        }
        _loadBookings();
      }
    });
  }

  Future<void> _cancelBooking(Map<String, dynamic> b) async {
    final status = b['status'] as String? ?? '';
    final id = b['id'] as String? ?? '';
    if (id.isEmpty) return;

    // If provider already accepted — show penalty warning
    if (['accepted','active'].contains(status)) {
      final confirm = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.red, size: 28),
            SizedBox(width: 8),
            Text('Cancel Booking?', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.red.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.red.withOpacity(0.3))),
              child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('⚠️ Cancellation Penalty', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.red, fontSize: 13)),
                SizedBox(height: 6),
                Text('Since the provider has already accepted your booking, a ₹20 penalty will be deducted from your next payment.',
                  style: TextStyle(fontSize: 12, color: AppColors.ink2, height: 1.4)),
              ]),
            ),
            const SizedBox(height: 12),
            const Text('The provider will be notified of this cancellation.',
              style: TextStyle(fontSize: 12, color: AppColors.muted)),
          ]),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep Booking', style: TextStyle(color: AppColors.teal, fontWeight: FontWeight.w700))),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.red,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              child: const Text('Cancel & Pay ₹20', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
          ],
        ),
      );
      if (confirm != true) return;

      // Apply ₹20 penalty
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      await FirebaseDatabase.instance.ref('bookings/$id').update({
        'status': 'cancelled',
        'cancelledAt': DateTime.now().toIso8601String(),
        'cancelledBy': 'customer',
        'penalty': 20,
        'penaltyReason': 'Cancelled after provider accepted',
      });
      await FirebaseDatabase.instance.ref('active_bookings/$id').update({
        'status': 'cancelled',
        'cancelledAt': DateTime.now().toIso8601String(),
      });

      // Save penalty to customer record
      if (uid.isNotEmpty) {
        final custSnap = await FirebaseDatabase.instance.ref('customers/$uid/pendingPenalty').get();
        final existing = (custSnap.value as num?)?.toInt() ?? 0;
        await FirebaseDatabase.instance.ref('customers/$uid').update({
          'pendingPenalty': existing + 20,
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Booking cancelled. ₹20 penalty will be deducted from your next payment.'),
            backgroundColor: AppColors.red,
            duration: Duration(seconds: 4),
          ));
      }
    } else {
      // Normal cancel — no penalty
      final confirm = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Cancel Booking?', style: TextStyle(fontWeight: FontWeight.w800)),
          content: const Text('Are you sure you want to cancel this booking?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('No')),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.red,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              child: const Text('Yes, Cancel', style: TextStyle(color: Colors.white))),
          ],
        ),
      );
      if (confirm != true) return;
      await FirebaseDatabase.instance.ref('bookings/$id').update({
        'status': 'cancelled', 'cancelledAt': DateTime.now().toIso8601String(), 'cancelledBy': 'customer',
      });
      await FirebaseDatabase.instance.ref('active_bookings/$id').update({'status': 'cancelled'});
    }

    _loadBookings();
  }

  List<Map<String, dynamic>> get _filteredHistory {
    if (_historyFilter == 'all') return _history;
    return _history.where((b) => b['status'] == _historyFilter).toList();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          title: const Text('My Bookings'),
          backgroundColor: AppColors.teal,
          automaticallyImplyLeading: false,
          bottom: const TabBar(
            indicatorColor: AppColors.brand,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [Tab(text: 'Active'), Tab(text: 'History')],
          ),
        ),
        body: Stack(children: [
          TabBarView(children: [
            _buildActiveTab(),
            _buildHistoryTab(),
          ]),
          if (_showOtpPopup) _buildOtpPopup(),
        ]),
      ),
    );
  }

  Widget _buildActiveTab() {
    if (_loading) return const Center(child: CircularProgressIndicator(color: AppColors.teal));
    if (_active.isEmpty) return _emptyState('No active bookings', 'Your active bookings will appear here', Icons.receipt_long_rounded);
    return RefreshIndicator(
      onRefresh: _loadBookings,
      color: AppColors.teal,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _active.length,
        itemBuilder: (_, i) => _bookingCard(_active[i]),
      ),
    );
  }

  Widget _buildHistoryTab() {
    if (_loading) return const Center(child: CircularProgressIndicator(color: AppColors.teal));
    return Column(children: [
      // Filter chips
      Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            _filterChip('all', 'All'),
            const SizedBox(width: 8),
            _filterChip('completed', 'Completed'),
            const SizedBox(width: 8),
            _filterChip('cancelled', 'Cancelled'),
          ]),
        ),
      ),
      Expanded(
        child: _filteredHistory.isEmpty
            ? _emptyState('No history', 'Your completed bookings will appear here', Icons.history_rounded)
            : RefreshIndicator(
                onRefresh: _loadBookings,
                color: AppColors.teal,
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _filteredHistory.length,
                  itemBuilder: (_, i) => _bookingCard(_filteredHistory[i], isHistory: true),
                ),
              ),
      ),
    ]);
  }

  Widget _filterChip(String value, String label) {
    final selected = _historyFilter == value;
    return GestureDetector(
      onTap: () => setState(() => _historyFilter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.teal : AppColors.bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? AppColors.teal : AppColors.line),
        ),
        child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
          color: selected ? Colors.white : AppColors.ink2)),
      ),
    );
  }

  Widget _bookingCard(Map<String, dynamic> b, {bool isHistory = false}) {
    final status = b['status'] ?? '';
    final statusColor = _statusColor(status);
    final hasProvider = b['providerName'] != null && b['providerName'].toString().isNotEmpty;
    final canCancel = ['confirmed','searching','pending','accepted','active'].contains(status);
    final penalty = (b['penalty'] as num?)?.toInt() ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10)],
      ),
      child: Column(children: [
        // Header
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: statusColor.withOpacity(0.07),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16))),
          child: Row(children: [
            Text(b['icon'] ?? '🔧', style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(b['service'] ?? 'Service',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.ink)),
              Text('ID: ${(b['id'] ?? '').toString().replaceAll('-','').substring(0,8).toUpperCase()}',
                style: const TextStyle(fontSize: 10, color: AppColors.muted)),
            ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: statusColor.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
              child: Text(_statusLabel(status),
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: statusColor))),
          ])),

        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _row(Icons.calendar_today_rounded, '${b['date'] ?? ''} at ${b['time'] ?? ''}'),
            const SizedBox(height: 5),
            _row(Icons.location_on_rounded, b['address'] ?? '—'),
            const SizedBox(height: 5),
            _row(Icons.currency_rupee_rounded, '₹${b['price'] ?? b['priceVal'] ?? 0}${penalty > 0 ? ' + ₹$penalty penalty' : ''}'),

            // Penalty notice
            if (penalty > 0) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppColors.red.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.red.withOpacity(0.3))),
                child: Row(children: [
                  const Icon(Icons.info_outline_rounded, color: AppColors.red, size: 14),
                  const SizedBox(width: 6),
                  Text('₹$penalty penalty applied — deducted from next payment',
                    style: const TextStyle(fontSize: 11, color: AppColors.red, fontWeight: FontWeight.w600)),
                ])),
            ],

            // Provider info when accepted
            if (hasProvider && !isHistory) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
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
                      onTap: () => launchUrl(Uri.parse('tel:${(b['acceptedBy'] as Map)['phone']}')),
                      child: Container(
                        width: 38, height: 38,
                        decoration: const BoxDecoration(color: AppColors.green, shape: BoxShape.circle),
                        child: const Icon(Icons.phone_rounded, color: Colors.white, size: 18))),
                ]),
              ),
            ],

            // OTP waiting
            if (status == 'otp_sent') ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.brand.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.brand.withOpacity(0.3))),
                child: const Row(children: [
                  Icon(Icons.lock_rounded, color: AppColors.brand, size: 16),
                  SizedBox(width: 8),
                  Expanded(child: Text('Provider requesting OTP to complete job',
                    style: TextStyle(fontSize: 12, color: AppColors.brand, fontWeight: FontWeight.w600))),
                ])),
            ],

            // Summary chips
            if ((b['summary'] as List?)?.isNotEmpty == true) ...[
              const SizedBox(height: 10),
              const Divider(color: AppColors.line),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6,
                children: (b['summary'] as List).map((s) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.tealSoft, borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.teal.withOpacity(0.3))),
                  child: Text('✓ $s', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.teal)),
                )).toList()),
            ],

            // Cancel button
            if (canCancel && !isHistory) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => _cancelBooking(b),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.red),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    minimumSize: const Size(double.infinity, 38)),
                  child: Text(
                    ['accepted','active'].contains(status) ? 'Cancel Booking (₹20 penalty)' : 'Cancel Booking',
                    style: const TextStyle(color: AppColors.red, fontWeight: FontWeight.w700, fontSize: 13)))),
            ],
          ])),
      ]),
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
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [AppColors.green, Color(0xFF34d058)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
              child: Column(children: [
                const Icon(Icons.lock_rounded, color: Colors.white, size: 36),
                const SizedBox(height: 8),
                const Text('Job Completion OTP', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
                const SizedBox(height: 4),
                Text('Share with provider to complete $_otpService',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: Colors.white70)),
              ])),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(children: [
                const Text('YOUR OTP CODE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.muted, letterSpacing: 1)),
                const SizedBox(height: 12),
                Row(mainAxisAlignment: MainAxisAlignment.center,
                  children: _otpCode.split('').map((digit) => Container(
                    width: 56, height: 64, margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.green, width: 2)),
                    child: Center(child: Text(digit,
                      style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: AppColors.ink)))
                  )).toList()),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AppColors.yellow.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
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

  Widget _emptyState(String title, String sub, IconData icon) {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(width: 80, height: 80,
        decoration: BoxDecoration(color: AppColors.tealSoft, shape: BoxShape.circle),
        child: Icon(icon, size: 40, color: AppColors.teal)),
      const SizedBox(height: 16),
      Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink)),
      const SizedBox(height: 8),
      Text(sub, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
    ]));
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
      case 'pending': return AppColors.yellow;
      case 'accepted': return AppColors.green;
      case 'active': return AppColors.brand;
      case 'otp_sent': return AppColors.brand;
      case 'completed': return AppColors.green;
      case 'cancelled': return AppColors.red;
      default: return AppColors.muted;
    }
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'confirmed': return 'Confirmed';
      case 'searching': return 'Searching...';
      case 'pending': return 'Pending';
      case 'accepted': return 'Provider Assigned';
      case 'active': return 'In Progress';
      case 'otp_sent': return 'Completing...';
      case 'completed': return 'Completed';
      case 'cancelled': return 'Cancelled';
      default: return s;
    }
  }
}
