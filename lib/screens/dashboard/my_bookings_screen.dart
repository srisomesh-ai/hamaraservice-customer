import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/api_service.dart';
import '../../utils/booking_format.dart';
import '../../utils/theme.dart';
import '../booking/booking_status_screen.dart';

/// "Active" tab: open bookings + completed-but-unpaid. Tapping a booking
/// opens the single booking status screen (which does the live tracking).
class MyBookingsScreen extends StatefulWidget {
  const MyBookingsScreen({super.key});
  @override
  State<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends State<MyBookingsScreen>
    with WidgetsBindingObserver {
  List<Map<String, dynamic>> _bookings = [];
  bool _loading = true;
  String _error = '';
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _startTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _timer?.cancel();
      _timer = null;
    } else if (state == AppLifecycleState.resumed) {
      _load();
      _startTimer();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _load());
  }

  static bool _isOpen(Map<String, dynamic> b) {
    final s = asStr(b['status']);
    if (s == BookingStatus.cancelled) return false;
    if (s == BookingStatus.completed) return !isPaid(b);
    return true;
  }

  Future<void> _load() async {
    if (FirebaseAuth.instance.currentUser == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final list = await ApiService.getBookingHistory();
      if (mounted) {
        setState(() {
          _bookings = list.where(_isOpen).toList();
          _loading = false;
          _error = '';
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.message; });
    }
  }

  Future<void> _open(Map<String, dynamic> b) async {
    final id = asStr(b['id']);
    if (id.isEmpty) return;
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => BookingStatusScreen(bookingId: id)));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.teal));
    }
    if (FirebaseAuth.instance.currentUser == null) {
      return _empty(Icons.lock_outline_rounded, 'Sign in to see your bookings',
          'Go to the Profile tab to sign in.');
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.teal,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          if (_error.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.redSoft, borderRadius: BorderRadius.circular(10)),
              child: Text(_error, style: const TextStyle(color: AppColors.red, fontSize: 12)),
            ),
          if (_bookings.isEmpty && _error.isEmpty)
            SizedBox(
              height: 420,
              child: _empty(Icons.calendar_today_rounded, 'No Active Bookings',
                  'Book a service from Home to get started!'),
            ),
          ..._bookings.map(_card),
        ],
      ),
    );
  }

  Widget _empty(IconData icon, String title, String sub) => Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 80, height: 80,
            decoration: const BoxDecoration(color: AppColors.tealSoft, shape: BoxShape.circle),
            child: Icon(icon, size: 40, color: AppColors.teal)),
          const SizedBox(height: 16),
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink)),
          const SizedBox(height: 8),
          Text(sub, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
        ]),
      );

  Widget _card(Map<String, dynamic> b) {
    final sc = statusColor(b);
    final provider = asStr(b['other_party']);
    final price = bookingPrice(b);
    return GestureDetector(
      onTap: () => _open(b),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10)]),
        child: Column(children: [
          Container(padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: sc.withOpacity(0.07),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16))),
            child: Row(children: [
              Text(asStr(b['svc_icon']).isEmpty ? '🔧' : asStr(b['svc_icon']),
                  style: const TextStyle(fontSize: 26)),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(asStr(b['svc_name']).isEmpty ? 'Service' : asStr(b['svc_name']),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.ink)),
                Text('ID: ${shortBookingId(asStr(b['id']))}',
                    style: const TextStyle(fontSize: 10, color: AppColors.muted)),
              ])),
              Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: sc.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
                child: Text(statusLabel(b), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: sc))),
            ])),
          Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _row(Icons.calendar_today_rounded, slotLabel(b)),
            const SizedBox(height: 5),
            _row(Icons.location_on_rounded, asStr(b['address'])),
            if (price > 0) ...[
              const SizedBox(height: 5),
              _row(Icons.currency_rupee_rounded, '₹$price'),
            ],
            if (provider.isNotEmpty) ...[
              const SizedBox(height: 5),
              _row(Icons.person_rounded, 'Provider: $provider'),
            ],
            const SizedBox(height: 10),
            SizedBox(width: double.infinity,
              child: OutlinedButton(
                onPressed: () => _open(b),
                style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.teal),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                child: Text(
                  asStr(b['status']) == BookingStatus.completed ? 'Pay now' : 'View status',
                  style: const TextStyle(color: AppColors.teal, fontWeight: FontWeight.w700)))),
          ])),
        ]),
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
}
