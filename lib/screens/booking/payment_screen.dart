import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:http/http.dart' as http;
import 'package:razorpay_flutter/razorpay_flutter.dart';
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
  bool _loading = false;
  bool _paid = false;
  bool _creatingOrder = false;
  int _pendingPenalty = 0;
  String _selectedMethod = 'razorpay';
  late Razorpay _razorpay;

  static const String _apiBase = 'https://hamaraservice.com/api';

  final List<Map<String, dynamic>> _methods = [
    {'key': 'razorpay', 'icon': '🔒', 'label': 'Pay Online',   'sub': 'UPI · Cards · Net Banking (Secured by Razorpay)'},
    {'key': 'cash',     'icon': '💵', 'label': 'Cash',          'sub': 'Pay directly to provider'},
  ];

  @override
  void initState() {
    super.initState();
    _loadPenalty();
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onPaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _onPaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _onExternalWallet);
  }

  @override
  void dispose() {
    _razorpay.clear();
    super.dispose();
  }

  Future<void> _loadPenalty() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final snap = await FirebaseDatabase.instance.ref('customers/$uid/pendingPenalty').get();
      if (snap.exists) setState(() => _pendingPenalty = ((snap.value as num?)?.toInt() ?? 0));
    } catch (e) {}
  }

  int get _baseAmount => ((widget.booking['priceVal'] ?? widget.booking['price'] ?? 0) as num).toInt();
  int get _totalAmount => _baseAmount + _pendingPenalty;

  // ── Razorpay callbacks ────────────────────────────────────────
  void _onPaymentSuccess(PaymentSuccessResponse response) async {
    setState(() => _loading = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final providerId = widget.booking['providerId'] ?? '';

      // Update Firebase immediately
      final payUpdate = {
        'status':          'completed',
        'paymentMethod':   'razorpay',
        'paymentStatus':   'paid',
        'txnId':           response.paymentId ?? '',
        'razorpayOrderId': response.orderId ?? '',
        'amountPaid':      _totalAmount,
        'penalty':         _pendingPenalty,
        'paidAt':          DateTime.now().toIso8601String(),
      };
      await FirebaseDatabase.instance.ref('bookings/${widget.bookingId}').update(payUpdate);
      await FirebaseDatabase.instance.ref('active_bookings/${widget.bookingId}').update({
        'status': 'completed', 'paymentStatus': 'paid',
      });

      // Clear pending penalty
      if (_pendingPenalty > 0 && uid.isNotEmpty) {
        await FirebaseDatabase.instance.ref('customers/$uid/pendingPenalty').set(0);
      }

      // Verify on server (non-blocking)
      _verifyOnServer(response, uid, providerId);

      setState(() { _loading = false; _paid = true; });
      await Future.delayed(const Duration(milliseconds: 800));
      if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(
        builder: (_) => ReviewScreen(bookingId: widget.bookingId, booking: widget.booking)));
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Payment recorded but error saving: $e'), backgroundColor: AppColors.yellow));
    }
  }

  void _verifyOnServer(PaymentSuccessResponse response, String uid, String providerId) {
    http.post(
      Uri.parse('$_apiBase/verify-payment.php'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'razorpay_order_id':   response.orderId ?? '',
        'razorpay_payment_id': response.paymentId ?? '',
        'razorpay_signature':  response.signature ?? '',
        'booking_id':          widget.bookingId,
        'amount':              _totalAmount,
        'provider_id':         providerId,
        'customer_id':         uid,
      }),
    ).then((res) {
      final result = jsonDecode(res.body);
      if (result['success'] == true && result['providerEarning'] != null) {
        FirebaseDatabase.instance.ref('bookings/${widget.bookingId}').update({
          'providerEarning': result['providerEarning'],
          'commissionAmt':   result['commissionAmt'] ?? 0,
          'verified':        true,
        });
      }
    }).catchError((e) => print('Server verify failed: $e'));
  }

  void _onPaymentError(PaymentFailureResponse response) {
    setState(() => _loading = false);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Payment failed: ${response.message ?? 'Please try again'}'),
        backgroundColor: AppColors.red));
  }

  void _onExternalWallet(ExternalWalletResponse response) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('External wallet: ${response.walletName}'), backgroundColor: AppColors.teal));
  }

  // ── Start Razorpay payment ─────────────────────────────────────
  Future<void> _startRazorpayPayment() async {
    setState(() => _creatingOrder = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final user = FirebaseAuth.instance.currentUser;

      // Create order on server
      final res = await http.post(
        Uri.parse('$_apiBase/create-order.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'bookingId':  widget.bookingId,
          'amount':     _totalAmount,
          'service':    widget.booking['service'] ?? 'Home Service',
          'customerId': uid,
          'providerId': widget.booking['providerId'] ?? '',
        }),
      );

      final order = jsonDecode(res.body);
      if (order['order_id'] == null) throw Exception(order['error'] ?? 'Failed to create order');

      setState(() => _creatingOrder = false);

      // Get customer profile for prefill
      String customerName = user?.displayName ?? widget.booking['customer'] ?? '';
      String customerPhone = widget.booking['phone'] ?? '';
      String customerEmail = user?.email ?? '';

      final options = {
        'key':         order['key_id'],
        'amount':      order['amount'],
        'currency':    'INR',
        'name':        'HamaraService',
        'description': widget.booking['service'] ?? 'Home Service',
        'order_id':    order['order_id'],
        'prefill':     {'name': customerName, 'email': customerEmail, 'contact': customerPhone},
        'theme':       {'color': '#1B6B7A'},
      };

      _razorpay.open(options);
    } catch (e) {
      setState(() => _creatingOrder = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start payment: $e'), backgroundColor: AppColors.red));
    }
  }

  // ── Cash payment ───────────────────────────────────────────────
  Future<void> _confirmCashPayment() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Confirm Cash Payment', style: TextStyle(fontWeight: FontWeight.w800)),
        content: Text('Please confirm you have paid ₹$_totalAmount in cash to the provider.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes, Paid')),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _loading = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      await FirebaseDatabase.instance.ref('bookings/${widget.bookingId}').update({
        'status':        'completed',
        'paymentMethod': 'cash',
        'paymentStatus': 'paid',
        'amountPaid':    _totalAmount,
        'penalty':       _pendingPenalty,
        'paidAt':        DateTime.now().toIso8601String(),
      });
      await FirebaseDatabase.instance.ref('active_bookings/${widget.bookingId}').update({
        'status': 'completed', 'paymentStatus': 'paid',
      });
      if (_pendingPenalty > 0 && uid.isNotEmpty) {
        await FirebaseDatabase.instance.ref('customers/$uid/pendingPenalty').set(0);
      }
      setState(() { _loading = false; _paid = true; });
      await Future.delayed(const Duration(milliseconds: 800));
      if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(
        builder: (_) => ReviewScreen(bookingId: widget.bookingId, booking: widget.booking)));
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  void _pay() {
    if (_selectedMethod == 'razorpay') _startRazorpayPayment();
    else _confirmCashPayment();
  }

  @override
  Widget build(BuildContext context) {
    if (_paid) {
      return const Scaffold(
        body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.check_circle_rounded, color: AppColors.green, size: 80),
          SizedBox(height: 16),
          Text('Payment Confirmed!', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.ink)),
          SizedBox(height: 8),
          Text('Redirecting to review...', style: TextStyle(color: AppColors.muted)),
        ])));
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('Payment'), backgroundColor: AppColors.teal, automaticallyImplyLeading: false),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(children: [

          // Bill card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)]),
            child: Column(children: [
              Row(children: [
                Container(width: 52, height: 52,
                  decoration: BoxDecoration(color: AppColors.tealSoft, borderRadius: BorderRadius.circular(12)),
                  child: Center(child: Text(widget.booking['icon'] ?? '🔧', style: const TextStyle(fontSize: 28)))),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(widget.booking['service'] ?? 'Service',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.ink)),
                  Text('Provider: ${widget.booking['providerName'] ?? ''}',
                    style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                  Text('Booking: ${widget.bookingId.replaceAll('-','').substring(0,8).toUpperCase()}',
                    style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                ])),
              ]),
              const Divider(height: 24, color: AppColors.line),
              _billRow('Service Amount', '₹$_baseAmount'),
              if (_pendingPenalty > 0) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: AppColors.red.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.red.withOpacity(0.2))),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Row(children: [
                      Icon(Icons.warning_amber_rounded, color: AppColors.red, size: 14),
                      SizedBox(width: 6),
                      Text('Cancellation Penalty', style: TextStyle(fontSize: 13, color: AppColors.red, fontWeight: FontWeight.w600)),
                    ]),
                    Text('+ ₹$_pendingPenalty', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.red)),
                  ])),
              ],
              const Divider(height: 20, color: AppColors.line),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Total Amount', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink)),
                Text('₹$_totalAmount', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: AppColors.red)),
              ]),
            ])),

          const SizedBox(height: 20),

          // Payment methods
          const Align(alignment: Alignment.centerLeft,
            child: Text('SELECT PAYMENT METHOD',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.muted, letterSpacing: 0.8))),
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
                  border: Border.all(color: sel ? AppColors.teal : AppColors.line, width: sel ? 2 : 1)),
                child: Row(children: [
                  Text(m['icon'], style: const TextStyle(fontSize: 28)),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(m['label'], style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                      color: sel ? AppColors.teal : AppColors.ink)),
                    Text(m['sub'], style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                  ])),
                  Container(width: 22, height: 22,
                    decoration: BoxDecoration(shape: BoxShape.circle,
                      color: sel ? AppColors.teal : Colors.transparent,
                      border: Border.all(color: sel ? AppColors.teal : AppColors.line, width: 2)),
                    child: sel ? const Icon(Icons.check, color: Colors.white, size: 14) : null),
                ])));
          }).toList()),

          const SizedBox(height: 20),

          // Pay button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (_loading || _creatingOrder) ? null : _pay,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE8251A),
                minimumSize: const Size(double.infinity, 56),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
              child: (_loading || _creatingOrder)
                  ? const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5)),
                      SizedBox(width: 12),
                      Text('Processing...', style: TextStyle(fontSize: 15, color: Colors.white, fontWeight: FontWeight.w700)),
                    ])
                  : Text(
                      _selectedMethod == 'razorpay'
                          ? '🔒 Pay ₹$_totalAmount Securely'
                          : '💵 Confirm Cash Payment · ₹$_totalAmount',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)))),

          const SizedBox(height: 12),
          if (_selectedMethod == 'razorpay')
            const Text('Secured by Razorpay · UPI · Cards · Net Banking',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: AppColors.muted)),

          const SizedBox(height: 32),
        ]),
      ),
    );
  }

  Widget _billRow(String label, String value) {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: const TextStyle(fontSize: 13, color: AppColors.muted)),
      Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink)),
    ]);
  }
}
