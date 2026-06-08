import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import '../../utils/theme.dart';

class BookingHistoryScreen extends StatefulWidget {
  const BookingHistoryScreen({super.key});
  @override
  State<BookingHistoryScreen> createState() => _BookingHistoryScreenState();
}

class _BookingHistoryScreenState extends State<BookingHistoryScreen> {
  List<Map<String, dynamic>> _bookings = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final snap = await FirebaseDatabase.instance.ref('bookings').get();
      if (!snap.exists) { setState(() => _loading = false); return; }
      final all = Map<String, dynamic>.from(snap.value as Map);
      final mine = all.values
          .map((v) => Map<String, dynamic>.from(v as Map))
          .where((b) => b['customerId'] == uid)
          .where((b) => ['completed','cancelled'].contains(b['status']))
          .toList()
        ..sort((a, b) => (b['createdAt'] ?? '').compareTo(a['createdAt'] ?? ''));
      setState(() { _bookings = mine; _loading = false; });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: AppColors.teal));
    if (_bookings.isEmpty) return _empty();
    return RefreshIndicator(
      onRefresh: _loadHistory,
      color: AppColors.teal,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _bookings.length,
        itemBuilder: (_, i) => _historyCard(_bookings[i]),
      ),
    );
  }

  Widget _empty() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history_rounded, size: 64, color: AppColors.muted),
          SizedBox(height: 16),
          Text('No booking history', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink)),
          SizedBox(height: 8),
          Text('Your completed bookings will appear here', style: TextStyle(color: AppColors.muted)),
        ],
      ),
    );
  }

  Widget _historyCard(Map<String, dynamic> b) {
    final completed = b['status'] == 'completed';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)],
      ),
      child: Row(children: [
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(
            color: completed ? AppColors.greenSoft : const Color(0xFFFFF5F5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(child: Text(b['icon'] ?? '🔧', style: const TextStyle(fontSize: 24))),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(b['service'] ?? 'Service',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.ink)),
          const SizedBox(height: 2),
          Text('${b['date'] ?? ''} · ₹${b['price'] ?? b['priceVal'] ?? 0}',
            style: const TextStyle(fontSize: 12, color: AppColors.muted)),
        ])),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: completed ? AppColors.greenSoft : const Color(0xFFFFF5F5),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            completed ? '✓ Done' : '✕ Cancelled',
            style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700,
              color: completed ? AppColors.green : AppColors.red,
            ),
          ),
        ),
      ]),
    );
  }
}
