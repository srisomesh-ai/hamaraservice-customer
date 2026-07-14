import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import '../../services/api_service.dart';
import '../../utils/theme.dart';

class CancelledBookingsScreen extends StatefulWidget {
  const CancelledBookingsScreen({super.key});
  @override
  State<CancelledBookingsScreen> createState() => _CancelledBookingsScreenState();
}

class _CancelledBookingsScreenState extends State<CancelledBookingsScreen> {
  List<Map<String, dynamic>> _bookings = [];
  bool _loading = true;
  StreamSubscription? _listener;

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
    if (uid == null) return;
    _loadBookings(uid);
  }

  Future<void> _loadBookings(String uid) async {
    try {
      final list = await ApiService.getCustomerBookings(uid);
      final filtered = list.where((b) =>
        b['status']?.toString() == 'cancelled'
      ).toList();
      if (mounted) setState(() {{ _bookings = filtered; _loading = false; }});
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: AppColors.teal));
    if (_bookings.isEmpty) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(width: 80, height: 80,
          decoration: BoxDecoration(color: AppColors.red.withOpacity(0.08), shape: BoxShape.circle),
          child: const Icon(Icons.cancel_rounded, size: 40, color: AppColors.red)),
        const SizedBox(height: 16),
        const Text('No Cancelled Bookings',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink)),
        const SizedBox(height: 8),
        const Text('Cancelled jobs will appear here',
          style: TextStyle(color: AppColors.muted, fontSize: 13)),
      ]));
    }
    return RefreshIndicator(
      onRefresh: () async => _listen(),
      color: AppColors.teal,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _bookings.length,
        itemBuilder: (_, i) => _card(_bookings[i])));
  }

  Widget _card(Map<String, dynamic> b) {
    final id = (b['id'] ?? '').toString();
    final shortId = id.replaceAll('-','').length > 8
        ? id.replaceAll('-','').substring(0,8).toUpperCase() : id.toUpperCase();
    final penalty = int.tryParse(b['penalty']?.toString() ?? '0') ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10)]),
      child: Column(children: [
        Container(padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: AppColors.red.withOpacity(0.06),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16))),
          child: Row(children: [
            Text(b['icon'] ?? '🔧', style: const TextStyle(fontSize: 26)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(b['service'] ?? 'Service',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.ink)),
              Text('ID: $shortId', style: const TextStyle(fontSize: 10, color: AppColors.muted)),
            ])),
            Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: AppColors.red.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20)),
              child: const Text('Cancelled',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.red))),
          ])),
        Padding(padding: const EdgeInsets.all(14), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
          _row(Icons.calendar_today_rounded, '${b['date'] ?? ''} at ${b['time'] ?? ''}'),
          const SizedBox(height: 5),
          _row(Icons.location_on_rounded, b['address'] ?? ''),
          const SizedBox(height: 5),
          _row(Icons.currency_rupee_rounded, 'Rs.${b['price'] ?? b['priceVal'] ?? 0}'),
          if ((b['cancelReason'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: 5),
            _row(Icons.info_outline_rounded, 'Reason: ${b['cancelReason']}'),
          ],
          if (penalty > 0) ...[
            const SizedBox(height: 8),
            Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(color: AppColors.red.withOpacity(0.07),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.red.withOpacity(0.2))),
              child: Row(children: [
                const Icon(Icons.warning_amber_rounded, color: AppColors.red, size: 14),
                const SizedBox(width: 6),
                Text('Rs.$penalty penalty was applied',
                  style: const TextStyle(fontSize: 11, color: AppColors.red, fontWeight: FontWeight.w600)),
              ])),
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