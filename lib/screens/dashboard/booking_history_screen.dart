import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import '../../utils/theme.dart';

// HISTORY ONLY — no Scaffold, no AppBar
// Parent home_screen.dart provides all navigation

class BookingHistoryScreen extends StatefulWidget {
  const BookingHistoryScreen({super.key});
  @override
  State<BookingHistoryScreen> createState() => _BookingHistoryScreenState();
}

class _BookingHistoryScreenState extends State<BookingHistoryScreen> {
  List<Map<String, dynamic>> _history = [];
  bool _loading = true;
  String _filter = 'all';
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
    _listener = FirebaseDatabase.instance.ref('bookings').onValue.listen((event) {
      if (!mounted) return;
      if (!event.snapshot.exists) {
        setState(() { _history = []; _loading = false; });
        return;
      }
      final all = Map<String, dynamic>.from(event.snapshot.value as Map);
      final mine = all.entries
          .where((e) {
            final b = e.value as Map;
            return b['customerId'] == uid &&
                ['completed','cancelled'].contains(b['status']);
          })
          .map((e) => Map<String, dynamic>.from({...e.value as Map, 'id': e.key}))
          .toList()
        ..sort((a, b) => (b['createdAt'] ?? '').compareTo(a['createdAt'] ?? ''));
      if (mounted) setState(() { _history = mine; _loading = false; });
    });
  }

  List<Map<String, dynamic>> get _filtered {
    if (_filter == 'all') return _history;
    return _history.where((b) => b['status'] == _filter).toList();
  }

  @override
  Widget build(BuildContext context) {
    // NO Scaffold, NO AppBar — parent provides it
    if (_loading) return const Center(child: CircularProgressIndicator(color: AppColors.teal));
    return Column(children: [
      // Filter chips
      Container(color: Colors.white,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: SingleChildScrollView(scrollDirection: Axis.horizontal,
          child: Row(children: [
            _chip('all', 'All (${_history.length})'),
            const SizedBox(width: 8),
            _chip('completed', 'Completed'),
            const SizedBox(width: 8),
            _chip('cancelled', 'Cancelled'),
          ]))),
      Expanded(
        child: _filtered.isEmpty
            ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(width: 80, height: 80,
                  decoration: BoxDecoration(color: AppColors.tealSoft, shape: BoxShape.circle),
                  child: const Icon(Icons.history_rounded, size: 40, color: AppColors.teal)),
                const SizedBox(height: 16),
                const Text('No History',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink)),
                const SizedBox(height: 8),
                const Text('Completed bookings will appear here',
                    style: TextStyle(color: AppColors.muted, fontSize: 13)),
              ]))
            : RefreshIndicator(
                onRefresh: () async => _listen(),
                color: AppColors.teal,
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _filtered.length,
                  itemBuilder: (_, i) => _card(_filtered[i]))),
      ),
    ]);
  }

  Widget _chip(String val, String label) {
    final sel = _filter == val;
    return GestureDetector(
      onTap: () { HapticFeedback.selectionClick(); setState(() => _filter = val); },
      child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: sel ? AppColors.teal : AppColors.bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: sel ? AppColors.teal : AppColors.line)),
        child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
          color: sel ? Colors.white : AppColors.ink2))));
  }

  Widget _card(Map<String, dynamic> b) {
    final status = b['status'] ?? '';
    final sc = status == 'completed' ? AppColors.green : AppColors.red;
    final penalty = int.tryParse(b['penalty']?.toString() ?? '0') ?? 0;
    final id = (b['id'] ?? '').toString();
    final shortId = id.replaceAll('-','').length > 8
        ? id.replaceAll('-','').substring(0,8).toUpperCase()
        : id.toUpperCase();

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
              Text(b['service'] ?? 'Service',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.ink)),
              Text('ID: $shortId', style: const TextStyle(fontSize: 10, color: AppColors.muted)),
            ])),
            Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: sc.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20)),
              child: Text(status == 'completed' ? 'Completed' : 'Cancelled',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: sc))),
          ])),
        Padding(padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _row(Icons.calendar_today_rounded, '${b['date'] ?? ''} at ${b['time'] ?? ''}'),
          const SizedBox(height: 5),
          _row(Icons.location_on_rounded, b['address'] ?? ''),
          const SizedBox(height: 5),
          _row(Icons.currency_rupee_rounded,
              'Rs.${b['amountPaid'] ?? b['price'] ?? 0}${penalty > 0 ? '  +  Rs.$penalty penalty' : ''}'),
          if (status == 'completed' && (b['providerName'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: 5),
            _row(Icons.person_rounded, 'Provider: ${b['providerName']}'),
          ],
          if (status == 'cancelled' && (b['cancelReason'] ?? '').toString().isNotEmpty) ...[
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
                    style: const TextStyle(fontSize: 11, color: AppColors.red,
                        fontWeight: FontWeight.w600)),
              ])),
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
