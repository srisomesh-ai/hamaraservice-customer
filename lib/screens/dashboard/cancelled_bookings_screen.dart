import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/api_service.dart';
import '../../utils/booking_format.dart';
import '../../utils/theme.dart';

class CancelledBookingsScreen extends StatefulWidget {
  const CancelledBookingsScreen({super.key});
  @override
  State<CancelledBookingsScreen> createState() => _CancelledBookingsScreenState();
}

class _CancelledBookingsScreenState extends State<CancelledBookingsScreen> {
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
              .where((b) => asStr(b['status']) == BookingStatus.cancelled)
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
                  decoration: BoxDecoration(color: AppColors.red.withOpacity(0.08), shape: BoxShape.circle),
                  child: const Icon(Icons.cancel_rounded, size: 40, color: AppColors.red)),
                const SizedBox(height: 16),
                const Text('No Cancelled Bookings',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink)),
                const SizedBox(height: 8),
                const Text('Cancelled jobs will appear here',
                  style: TextStyle(color: AppColors.muted, fontSize: 13)),
              ])),
            ),
          ..._bookings.map(_card),
        ],
      ),
    );
  }

  Widget _card(Map<String, dynamic> b) {
    final reason = asStr(b['cancel_reason']);
    final by = asStr(b['cancelled_by']);
    final price = bookingPrice(b);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10)]),
      child: Column(children: [
        Container(padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: AppColors.red.withOpacity(0.06),
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
              decoration: BoxDecoration(color: AppColors.red.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20)),
              child: const Text('Cancelled',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.red))),
          ])),
        Padding(padding: const EdgeInsets.all(14), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
          _row(Icons.calendar_today_rounded, slotLabel(b)),
          const SizedBox(height: 5),
          _row(Icons.location_on_rounded, asStr(b['address'])),
          if (price > 0) ...[
            const SizedBox(height: 5),
            _row(Icons.currency_rupee_rounded, '₹$price'),
          ],
          if (by.isNotEmpty) ...[
            const SizedBox(height: 5),
            _row(Icons.person_off_rounded, 'Cancelled by $by'),
          ],
          if (reason.isNotEmpty) ...[
            const SizedBox(height: 5),
            _row(Icons.info_outline_rounded, 'Reason: $reason'),
          ],
        ])),
      ]),
    );
  }

  Widget _row(IconData icon, String text) {
    return Row(children: [
      Icon(icon, size: 14, color: AppColors.muted),
      const SizedBox(width: 8),
      Expanded(child: Text(text, style: const TextStyle(fontSize: 13, color: AppColors.ink2))),
    ]);
  }
}
