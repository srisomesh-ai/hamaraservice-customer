import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import '../../utils/theme.dart';

class MyBookingsScreen extends StatefulWidget {
  const MyBookingsScreen({super.key});
  @override
  State<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends State<MyBookingsScreen> {
  List<Map<String, dynamic>> _bookings = [];
  bool _loading = true;
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
    try {
      final snap = await FirebaseDatabase.instance.ref('bookings').get();
      if (!snap.exists) { setState(() => _loading = false); return; }
      final all = Map<String, dynamic>.from(snap.value as Map);
      final mine = all.values
          .map((v) => Map<String, dynamic>.from(v as Map))
          .where((b) => b['customerId'] == uid)
          .where((b) => ['confirmed','searching','accepted','active',
                         'pending','otp_sent'].contains(b['status']))
          .toList()
        ..sort((a, b) => (b['createdAt'] ?? '').compareTo(a['createdAt'] ?? ''));
      setState(() { _bookings = mine; _loading = false; });

      // Watch OTP for active/otp_sent bookings
      for (final b in mine) {
        final id = b['id'] as String? ?? '';
        final status = b['status'] as String? ?? '';
        if (['active', 'otp_sent', 'accepted'].contains(status) && id.isNotEmpty) {
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
        .ref('job_otp/$bookingId')
        .onValue
        .listen((event) {
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
  // Find the booking and go to payment
  final booking = _bookings.firstWhere(
    (b) => b['id'] == bookingId,
    orElse: () => <String, dynamic>{},
  );
  if (booking.isNotEmpty && mounted) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => PaymentScreen(
        bookingId: bookingId,
        booking: booking,
      )));
  }
  _loadBookings();
}
    });
  }

  Future<void> _cancelBooking(Map<String, dynamic> b) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Cancel Booking?', style: TextStyle(fontWeight: FontWeight.w800)),
        content: const Text('Are you sure you want to cancel this booking?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
            child: const Text('No')),
          TextButton(onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes, Cancel', style: TextStyle(color: AppColors.red))),
        ],
      ),
    );
    if (confirm != true) return;
    final id = b['id'] as String? ?? '';
    if (id.isEmpty) return;
    await FirebaseDatabase.instance.ref('bookings/$id').update({'status': 'cancelled'});
    await FirebaseDatabase.instance.ref('active_bookings/$id').update({'status': 'cancelled'});
    _loadBookings();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        _buildContent(),
        if (_showOtpPopup) _buildOtpPopup(),
      ],
    );
  }

  Widget _buildContent() {
    if (_loading) return const Center(child: CircularProgressIndicator(color: AppColors.teal));
    if (_bookings.isEmpty) return _empty();
    return RefreshIndicator(
      onRefresh: _loadBookings,
      color: AppColors.teal,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _bookings.length,
        itemBuilder: (_, i) => _bookingCard(_bookings[i]),
      ),
    );
  }

  Widget _empty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(color: AppColors.tealSoft, shape: BoxShape.circle),
            child: const Icon(Icons.receipt_long_rounded, size: 40, color: AppColors.teal),
          ),
          const SizedBox(height: 16),
          const Text('No active bookings',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink)),
          const SizedBox(height: 8),
          const Text('Your active bookings will appear here',
            style: TextStyle(color: AppColors.muted)),
        ],
      ),
    );
  }

  Widget _bookingCard(Map<String, dynamic> b) {
    final status = b['status'] ?? 'confirmed';
    final statusColor = _statusColor(status);
    final statusLabel = _statusLabel(status);
    final canCancel = ['confirmed','searching','pending'].contains(status);
    final hasProvider = b['providerName'] != null && b['providerName'].toString().isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10)],
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.08),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(children: [
              Text(b['icon'] ?? '🔧', style: const TextStyle(fontSize: 26)),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(b['service'] ?? 'Service',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.ink)),
                Text('ID: ${(b['id'] ?? '').toString().substring(0, min(8, (b['id'] ?? '').toString().length)).toUpperCase()}',
                  style: const TextStyle(fontSize: 11, color: AppColors.muted)),
              ])),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(statusLabel,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: statusColor)),
              ),
            ]),
          ),

          // Details
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(children: [
              _row(Icons.calendar_today_rounded, '${b['date'] ?? ''} at ${b['time'] ?? ''}'),
              const SizedBox(height: 6),
              _row(Icons.location_on_rounded, b['address'] ?? '—'),
              const SizedBox(height: 6),
              _row(Icons.currency_rupee_rounded, '₹${b['price'] ?? b['priceVal'] ?? 0}'),

              // Provider info when accepted
              if (hasProvider) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.greenSoft,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.green.withOpacity(0.3)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.person_rounded, color: AppColors.green, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Your Provider', style: TextStyle(fontSize: 11, color: AppColors.green, fontWeight: FontWeight.w700)),
                      Text(b['providerName'] ?? '',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink)),
                      if ((b['acceptedBy'] as Map?)?['phone'] != null)
                        Text((b['acceptedBy'] as Map)['phone'],
                          style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                    ])),
                    // Call provider
                    if ((b['acceptedBy'] as Map?)?['phone'] != null)
                      GestureDetector(
                        onTap: () {
                          final phone = (b['acceptedBy'] as Map)['phone'];
                          // launchUrl(Uri.parse('tel:$phone'));
                        },
                        child: Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(color: AppColors.green, shape: BoxShape.circle),
                          child: const Icon(Icons.phone_rounded, color: Colors.white, size: 18),
                        ),
                      ),
                  ]),
                ),
              ],

              // OTP waiting indicator
              if (status == 'otp_sent') ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.brand.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.brand.withOpacity(0.3)),
                  ),
                  child: const Row(children: [
                    Icon(Icons.lock_rounded, color: AppColors.brand, size: 18),
                    SizedBox(width: 8),
                    Expanded(child: Text('Provider is requesting OTP to complete job',
                      style: TextStyle(fontSize: 12, color: AppColors.brand, fontWeight: FontWeight.w600))),
                  ]),
                ),
              ],

              // Summary chips
              if ((b['summary'] as List?)?.isNotEmpty == true) ...[
                const SizedBox(height: 10),
                const Divider(color: AppColors.line),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6, runSpacing: 6,
                  children: (b['summary'] as List).map((s) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.tealSoft,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.teal.withOpacity(0.3)),
                    ),
                    child: Text('✓ $s',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.teal)),
                  )).toList(),
                ),
              ],

              // Cancel button
              if (canCancel) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => _cancelBooking(b),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.red),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      minimumSize: const Size(double.infinity, 38),
                    ),
                    child: const Text('Cancel Booking',
                      style: TextStyle(color: AppColors.red, fontWeight: FontWeight.w700, fontSize: 13)),
                  ),
                ),
              ],
            ]),
          ),
        ],
      ),
    );
  }

  // OTP Popup shown to customer when provider requests completion
  Widget _buildOtpPopup() {
    return Container(
      color: Colors.black.withOpacity(0.7),
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 30)],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.green, Color(0xFF34d058)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Column(children: [
                  const Icon(Icons.lock_rounded, color: Colors.white, size: 36),
                  const SizedBox(height: 8),
                  const Text('Job Completion OTP',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
                  const SizedBox(height: 4),
                  Text('Share this code with your provider to complete $_otpService',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: Colors.white70)),
                ]),
              ),

              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(children: [
                  const Text('YOUR OTP CODE',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                      color: AppColors.muted, letterSpacing: 1)),
                  const SizedBox(height: 12),

                  // OTP display
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    decoration: BoxDecoration(
                      color: AppColors.bg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.green.withOpacity(0.4), width: 2),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: _otpCode.split('').map((digit) => Container(
                        width: 50, height: 60,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.green, width: 2),
                        ),
                        child: Center(
                          child: Text(digit,
                            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: AppColors.ink)),
                        ),
                      )).toList(),
                    ),
                  ),

                  const SizedBox(height: 16),
                  const Text('This code expires once used',
                    style: TextStyle(fontSize: 12, color: AppColors.muted)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.yellow.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.yellow.withOpacity(0.3)),
                    ),
                    child: const Row(children: [
                      Icon(Icons.warning_amber_rounded, color: AppColors.yellow, size: 16),
                      SizedBox(width: 8),
                      Expanded(child: Text('Only share this code after the service is completed to your satisfaction.',
                        style: TextStyle(fontSize: 11, color: AppColors.ink2))),
                    ]),
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(IconData icon, String text) {
    return Row(children: [
      Icon(icon, size: 15, color: AppColors.teal),
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
      case 'otp_sent': return 'Completing...';
      default: return s;
    }
  }

  int min(int a, int b) => a < b ? a : b;
}
