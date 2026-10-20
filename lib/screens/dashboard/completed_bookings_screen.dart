import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/api_service.dart';
import '../../utils/booking_format.dart';
import '../../utils/theme.dart';
import '../booking/booking_status_screen.dart';
import '../booking/review_screen.dart';

class CompletedBookingsScreen extends StatefulWidget {
  const CompletedBookingsScreen({super.key});
  @override
  State<CompletedBookingsScreen> createState() => _CompletedBookingsScreenState();
}

class _CompletedBookingsScreenState extends State<CompletedBookingsScreen> {
  List<Map<String, dynamic>> _bookings = [];
  bool _loading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
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
          _bookings = list
              .where((b) => asStr(b['status']) == BookingStatus.completed)
              .toList();
          _loading = false;
          _error = '';
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.message; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: AppColors.teal));
    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.teal,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          if (_error.isNotEmpty)
            Text(_error, style: const TextStyle(color: AppColors.red, fontSize: 12)),
          if (_bookings.isEmpty && _error.isEmpty)
            SizedBox(
              height: 420,
              child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(width: 80, height: 80,
                  decoration: const BoxDecoration(color: AppColors.greenSoft, shape: BoxShape.circle),
                  child: const Icon(Icons.check_circle_rounded, size: 40, color: AppColors.green)),
                const SizedBox(height: 16),
                const Text('No Completed Bookings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink)),
                const SizedBox(height: 8),
                const Text('Your completed jobs will appear here', style: TextStyle(color: AppColors.muted, fontSize: 13)),
              ])),
            ),
          ..._bookings.map(_card),
        ],
      ),
    );
  }

  Widget _card(Map<String, dynamic> b) {
    final amount = bookingPrice(b);
    final paid = isPaid(b);
    final method = asStr(b['payment_method']);
    final provider = asStr(b['other_party']);
    final rating = asInt(b['rating']);
    final id = asStr(b['id']);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10)]),
      child: Column(children: [
        Container(padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: AppColors.green.withOpacity(0.07),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16))),
          child: Row(children: [
            Text(asStr(b['svc_icon']).isEmpty ? '🔧' : asStr(b['svc_icon']),
                style: const TextStyle(fontSize: 26)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(asStr(b['svc_name']).isEmpty ? 'Service' : asStr(b['svc_name']),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.ink)),
              Text('ID: ${shortBookingId(id)}', style: const TextStyle(fontSize: 10, color: AppColors.muted)),
            ])),
            Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: statusColor(b).withOpacity(0.15),
                borderRadius: BorderRadius.circular(20)),
              child: Text(statusLabel(b),
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: statusColor(b)))),
          ])),
        Padding(padding: const EdgeInsets.all(14), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
          _row(Icons.calendar_today_rounded, slotLabel(b)),
          const SizedBox(height: 5),
          _row(Icons.location_on_rounded, asStr(b['address'])),
          const SizedBox(height: 5),
          _row(Icons.currency_rupee_rounded,
              paid ? '₹$amount paid${method.isNotEmpty ? ' ($method)' : ''}' : '₹$amount due'),
          if (provider.isNotEmpty) ...[
            const SizedBox(height: 5),
            _row(Icons.person_rounded, 'Provider: $provider'),
          ],
          if (parseServerTime(b['started_at']) != null) ...[
            const SizedBox(height: 5),
            _row(Icons.play_circle_outline_rounded,
                'Work started: ${fmtServerTime(b['started_at'])}'),
          ],
          if (parseServerTime(b['completed_at']) != null) ...[
            const SizedBox(height: 5),
            _row(Icons.stop_circle_outlined,
                'Work closed: ${fmtServerTime(b['completed_at'])}'
                '${parseServerTime(b['started_at']) != null ? ' (${fmtWorkDuration(b['started_at'], b['completed_at'])})' : ''}'),
          ],
          if (rating > 0) ...[
            const SizedBox(height: 5),
            _row(Icons.star_rounded, 'You rated $rating★'),
          ],
          if (!paid || rating == 0) ...[
            const SizedBox(height: 10),
            SizedBox(width: double.infinity,
              child: OutlinedButton(
                onPressed: () async {
                  await Navigator.push(context, MaterialPageRoute(
                    builder: (_) => paid
                        ? ReviewScreen(bookingId: id, booking: b)
                        : BookingStatusScreen(bookingId: id)));
                  _load();
                },
                style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.teal),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                child: Text(paid ? 'Rate this service' : 'Pay now',
                  style: const TextStyle(color: AppColors.teal, fontWeight: FontWeight.w700)))),
          ],
        ])),
      ]),
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
