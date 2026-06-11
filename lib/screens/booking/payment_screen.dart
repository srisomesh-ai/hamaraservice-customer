import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import '../../utils/theme.dart';
import 'review_screen.dart';

class PaymentScreen extends StatefulWidget {
  final String bookingId;
  final Map<String, dynamic> booking;
  const PaymentScreen({super.key, required this.bookingId, required this.booking});
  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  String _selectedMethod = 'cash';
  bool _loading = false;
  bool _paid = false;

  final List<Map<String, dynamic>> _methods = [
    {'key': 'cash',   'icon': '💵', 'label': 'Cash',          'sub': 'Pay directly to provider'},
    {'key': 'upi',    'icon': '📱', 'label': 'UPI',           'sub': 'Google Pay, PhonePe, Paytm'},
    {'key': 'card',   'icon': '💳', 'label': 'Card',          'sub': 'Credit / Debit card'},
    {'key': 'netbanking','icon': '🏦','label': 'Net Banking',  'sub': 'All major banks'},
  ];

  Future<void> _confirmPayment() async {
    setState(() => _loading = true);
    try {
      // Update booking status to completed with payment info
      await FirebaseDatabase.instance.ref('bookings/${widget.bookingId}').update({
        'status':        'completed',
        'paymentMethod': _selectedMethod,
        'paymentStatus': 'paid',
        'paidAt':        DateTime.now().toIso8601String(),
      });
      await FirebaseDatabase.instance.ref('active_bookings/${widget.bookingId}').update({
        'status':        'completed',
        'paymentStatus': 'paid',
        'paidAt':        DateTime.now().toIso8601String(),
      });

      setState(() { _loading = false; _paid = true; });

      // Navigate to review screen
      await Future.delayed(const Duration(milliseconds: 800));
      if (mounted) {
        Navigator.pushReplacement(context, MaterialPageRoute(
          builder: (_) => ReviewScreen(
            bookingId: widget.bookingId,
            booking: widget.booking,
          )));
      }
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    final amount = widget.booking['priceVal'] ?? widget.booking['price'] ?? 0;
    final service = widget.booking['service'] ?? 'Service';
    final providerName = widget.booking['providerName'] ?? 'Provider';

    if (_paid) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        body: const Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.check_circle_rounded, color: AppColors.green, size: 80),
            SizedBox(height: 16),
            Text('Payment Confirmed!',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.ink)),
            SizedBox(height: 8),
            Text('Redirecting to review...', style: TextStyle(color: AppColors.muted)),
          ]),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Payment'),
        backgroundColor: AppColors.teal,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0D3D47), AppColors.teal],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(children: [
                const Text('💳', style: TextStyle(fontSize: 48)),
                const SizedBox(height: 8),
                const Text('Payment Due',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
                const SizedBox(height: 4),
                const Text('Your service is complete. Please complete payment.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.white70)),
              ]),
            ),

            const SizedBox(height: 20),

            // Bill summary
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)]),
              child: Column(children: [
                _billRow('Service', service),
                const Divider(color: AppColors.line),
                _billRow('Provider', providerName),
                const Divider(color: AppColors.line),
                _billRow('Booking ID',
                  widget.bookingId.substring(0, 8).toUpperCase()),
                const Divider(color: AppColors.line),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('Total Amount',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink)),
                  Text('₹$amount',
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: AppColors.red)),
                ]),
              ]),
            ),

            const SizedBox(height: 20),

            // Payment methods
            const Align(alignment: Alignment.centerLeft,
              child: Text('SELECT PAYMENT METHOD',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                  color: AppColors.muted, letterSpacing: 0.8))),
            const SizedBox(height: 10),

            ...(_methods.map((m) {
              final sel = m['key'] == _selectedMethod;
              return GestureDetector(
                onTap: () => setState(() => _selectedMethod = m['key']),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: sel ? AppColors.tealSoft : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: sel ? AppColors.teal : AppColors.line,
                      width: sel ? 2 : 1,
                    ),
                  ),
                  child: Row(children: [
                    Text(m['icon'], style: const TextStyle(fontSize: 28)),
                    const SizedBox(width: 14),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(m['label'],
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                          color: sel ? AppColors.teal : AppColors.ink)),
                      Text(m['sub'],
                        style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                    ])),
                    Container(
                      width: 22, height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: sel ? AppColors.teal : Colors.transparent,
                        border: Border.all(
                          color: sel ? AppColors.teal : AppColors.line, width: 2),
                      ),
                      child: sel ? const Icon(Icons.check, color: Colors.white, size: 14) : null,
                    ),
                  ]),
                ),
              );
            }).toList()),

            const SizedBox(height: 20),

            // Pay button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _confirmPayment,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE8251A),
                  minimumSize: const Size(double.infinity, 56),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: _loading
                    ? const SizedBox(width: 24, height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation(Colors.white)))
                    : Text(
                        _selectedMethod == 'cash'
                            ? 'Confirm Cash Payment · ₹$amount'
                            : 'Pay ₹$amount Securely',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
              ),
            ),

            const SizedBox(height: 12),
            Text(
              _selectedMethod == 'cash'
                  ? 'Confirm that you have paid ₹$amount cash to the provider'
                  : 'Secured payment · UPI · Cards · Net Banking',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: AppColors.muted)),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _billRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: const TextStyle(fontSize: 13, color: AppColors.muted)),
        Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink)),
      ]),
    );
  }
}
