import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import '../../services/api_service.dart';
import '../../utils/theme.dart';

class CompletedBookingsScreen extends StatefulWidget {
  const CompletedBookingsScreen({super.key});
  @override
  State<CompletedBookingsScreen> createState() => _CompletedBookingsScreenState();
}

class _CompletedBookingsScreenState extends State<CompletedBookingsScreen> {
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
        b['status']?.toString() == 'completed'
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
          decoration: BoxDecoration(color: AppColors.greenSoft, shape: BoxShape.circle),
          child: const Icon(Icons.check_circle_rounded, size: 40, color: AppColors.green)),
        const SizedBox(height: 16),
        const Text('No Completed Bookings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink)),
        const SizedBox(height: 8),
        const Text('Your completed jobs will appear here', style: TextStyle(color: AppColors.muted, fontSize: 13)),
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
    final amountPaid = b['amountPaid'] ?? b['price'] ?? b['priceVal'] ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10)]),
      child: Column(children: [
        Container(padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: AppColors.green.withOpacity(0.07),
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
              decoration: BoxDecoration(color: AppColors.green.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20)),
              child: const Text('Completed',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.green))),
          ])),
        Padding(padding: const EdgeInsets.all(14), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
          _row(Icons.calendar_today_rounded, '${b['date'] ?? ''} at ${b['time'] ?? ''}'),
          const SizedBox(height: 5),
          _row(Icons.location_on_rounded, b['address'] ?? ''),
          const SizedBox(height: 5),
          _row(Icons.currency_rupee_rounded, 'Rs.$amountPaid paid'),
          if ((b['providerName'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: 5),
            _row(Icons.person_rounded, 'Provider: ${b['providerName']}'),
          ],
          if ((b['paymentMethod'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: 5),
            _row(Icons.payment_rounded, 'Paid via ${b['paymentMethod']}'),
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