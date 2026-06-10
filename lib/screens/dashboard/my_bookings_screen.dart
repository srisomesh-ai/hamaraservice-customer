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

  @override
  void initState() {
    super.initState();
    _loadBookings();
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
          .where((b) => ['confirmed','searching','accepted','active'].contains(b['status']))
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
          const Text('No active bookings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink)),
          const SizedBox(height: 8),
          const Text('Your active bookings will appear here', style: TextStyle(color: AppColors.muted)),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _bookingCard(Map<String, dynamic> b) {
    final status = b['status'] ?? 'confirmed';
    final statusColor = _statusColor(status);
    final statusLabel = _statusLabel(status);
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
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.08),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(children: [
              Text(b['icon'] ?? '🔧', style: const TextStyle(fontSize: 28)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(b['service'] ?? 'Service', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.ink)),
                Text('ID: ${(b['id'] ?? '').toString().substring(0, 8).toUpperCase()}',
                  style: const TextStyle(fontSize: 11, color: AppColors.muted)),
              ])),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: statusColor.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
                child: Text(statusLabel, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: statusColor)),
              ),
            ]),
          ),
          // Details
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              _row(Icons.calendar_today_rounded, '${b['date'] ?? ''} at ${b['time'] ?? ''}'),
              const SizedBox(height: 8),
              _row(Icons.location_on_rounded, b['address'] ?? '—'),
              const SizedBox(height: 8),
              _row(Icons.currency_rupee_rounded, '₹${b['price'] ?? b['priceVal'] ?? 0}'),
              if ((b['summary'] as List?)?.isNotEmpty == true) ...[
                if (['confirmed','searching','pending'].contains(status)) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: const Text('Cancel Booking?'),
                          content: const Text('Are you sure you want to cancel this booking?'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(context, false),
                              child: const Text('No')),
                            TextButton(onPressed: () => Navigator.pop(context, true),
                              child: const Text('Yes, Cancel',
                                style: TextStyle(color: AppColors.red))),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        await FirebaseDatabase.instance
                            .ref('bookings/${b['id']}').update({'status': 'cancelled'});
                        await FirebaseDatabase.instance
                            .ref('active_bookings/${b['id']}').update({'status': 'cancelled'});
                        setState(() => _loadBookings());
                      }
                    },
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.red),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      minimumSize: const Size(double.infinity, 38),
                    ),
                    child: const Text('Cancel Booking',
                      style: TextStyle(color: AppColors.red, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
                const SizedBox(height: 10),
                const Divider(color: AppColors.line),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6, runSpacing: 6,
                  children: (b['summary'] as List).map((s) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.tealSoft,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.teal.withOpacity(0.3)),
                    ),
                    child: Text('✓ $s', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.teal)),
                  )).toList(),
                ),
              ],
            ]),
          ),
        ],
      ),
    );
  }

  Widget _row(IconData icon, String text) {
    return Row(children: [
      Icon(icon, size: 16, color: AppColors.teal),
      const SizedBox(width: 8),
      Expanded(child: Text(text, style: const TextStyle(fontSize: 13, color: AppColors.ink2))),
    ]);
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'confirmed': return AppColors.teal;
      case 'searching': return AppColors.yellow;
      case 'accepted': return AppColors.green;
      case 'active': return AppColors.brand;
      default: return AppColors.muted;
    }
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'confirmed': return '✓ Confirmed';
      case 'searching': return '🔍 Searching';
      case 'accepted': return '✅ Provider Assigned';
      case 'active': return '🔧 In Progress';
      default: return s;
    }
  }
}
