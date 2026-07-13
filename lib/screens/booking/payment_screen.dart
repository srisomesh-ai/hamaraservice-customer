import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  late Razorpay _razorpay;

  // Firebase Cloud Functions — no Hostinger dependency
  static const String _createOrder  = 'https://createorder-mlchyp6tra-as.a.run.app';
  static const String _verifyPayment = 'https://verifypayment-mlchyp6tra-as.a.run.app';
  static const String _notifyBooking = 'https://notifybooking-mlchyp6tra-as.a.run.app';

  @override
  void initState() {
    super.initState();
    _loadPenalty();
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _onError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _onWallet);
  }

  @override
  void dispose() { _razorpay.clear(); super.dispose(); }

  Future<void> _loadPenalty() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final snap = await FirebaseDatabase.instance.ref('customers/$uid/pendingPenalty').get();
      if (snap.exists) setState(() => _pendingPenalty = ((snap.value as num?)?.toInt() ?? 0));
    } catch (_) {}
  }

  // confirmedPrice = negotiated & agreed price; fallback to priceVal for non-negotiated bookings
  int get _baseAmount => ((widget.booking['confirmedPrice'] ?? widget.booking['priceVal'] ?? widget.booking['price'] ?? 0) as num).toInt();
  int get _totalAmount => _baseAmount + _pendingPenalty;

  void _onSuccess(PaymentSuccessResponse r) async {
    HapticFeedback.heavyImpact();
    setState(() => _loading = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final providerId = widget.booking['providerId'] ?? '';
      await FirebaseDatabase.instance.ref('bookings/${widget.bookingId}').update({
        'status': 'completed', 'paymentMethod': 'razorpay', 'paymentStatus': 'paid',
        'txnId': r.paymentId ?? '', 'razorpayOrderId': r.orderId ?? '',
        'amountPaid': _totalAmount, 'penalty': _pendingPenalty,
        'paidAt': DateTime.now().toIso8601String(),
      });
      await FirebaseDatabase.instance.ref('active_bookings/${widget.bookingId}').update(
          {'status': 'completed', 'paymentStatus': 'paid'});
      if (_pendingPenalty > 0 && uid.isNotEmpty) {
        await FirebaseDatabase.instance.ref('customers/$uid/pendingPenalty').set(0);
      }
      // Record commission rate on booking so provider earnings_screen
      // can recalculate correctly — do NOT write totalEarned here
      // (earnings_screen is the single source of truth for provider balance)
      if (providerId.isNotEmpty) {
        final svcName = widget.booking['service'] as String? ?? '';
        final commRate = _getCommissionRate(svcName);
        final netEarned = (_baseAmount * (1 - commRate / 100)).roundToDouble();
        await FirebaseDatabase.instance.ref('bookings/${widget.bookingId}').update({
          'commissionRate': commRate,
          'platformFee': (_baseAmount * commRate / 100).round(),
          'providerEarned': netEarned.round(),
        });
      }
      // Push notification to provider — payment received
      try {
        final provId = widget.booking['providerId']?.toString() ?? '';
        if (provId.isNotEmpty) {
          final provTokenSnap = await FirebaseDatabase.instance
              .ref('providers/$provId/fcmToken').get();
          final provToken = provTokenSnap.value?.toString() ?? '';
          if (provToken.isNotEmpty) {
            final svcName = widget.booking['service']?.toString() ?? '';
            await http.post(
              Uri.parse('$_notifyBooking'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'event': 'payment_received',
                'fcmToken': provToken,
                'data': {
                  'amount': _totalAmount.toString(),
                  'service': svcName,
                  'bookingId': widget.bookingId,
                },
              }),
            );
          }
        }
      } catch (_) {}
      // Server verify (non-blocking)
      _verifyServer(r, uid);
      HapticFeedback.heavyImpact();
      setState(() { _loading = false; _paid = true; });
      await Future.delayed(const Duration(milliseconds: 1000));
      if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(
          builder: (_) => ReviewScreen(bookingId: widget.bookingId, booking: widget.booking)));
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  void _verifyServer(PaymentSuccessResponse r, String uid) {
    http.post(Uri.parse('$_verifyPayment'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'razorpay_order_id': r.orderId ?? '',
        'razorpay_payment_id': r.paymentId ?? '',
        'razorpay_signature': r.signature ?? '',
        'booking_id': widget.bookingId,
        'amount': _totalAmount,
        'provider_id': widget.booking['providerId'] ?? '',
        'customer_id': uid,
      })).catchError((_) {});
  }

  void _onError(PaymentFailureResponse r) {
    HapticFeedback.heavyImpact();
    setState(() => _loading = false);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Payment failed: ${r.message ?? 'Please try again'}'),
      backgroundColor: AppColors.red));
  }

  void _onWallet(ExternalWalletResponse r) {}

  Future<void> _startPayment() async {
    HapticFeedback.mediumImpact();
    setState(() => _creatingOrder = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final user = FirebaseAuth.instance.currentUser;
      final res = await http.post(Uri.parse('$_createOrder'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'bookingId': widget.bookingId,
          'amount': _totalAmount,
          'service': widget.booking['service'] ?? 'Home Service',
          'customerId': uid,
          'providerId': widget.booking['providerId'] ?? '',
        }));
      final order = jsonDecode(res.body);
      if (order['order_id'] == null) throw Exception(order['error'] ?? 'Failed to create order');
      setState(() => _creatingOrder = false);
      final options = {
        'key': order['key_id'],
        'amount': order['amount'],
        'currency': 'INR',
        'name': 'HamaraService',
        'description': widget.booking['service'] ?? 'Home Service',
        'order_id': order['order_id'],
        'prefill': {
          'name': widget.booking['customer'] ?? '',
          'contact': widget.booking['phone'] ?? '',
          'email': user?.email ?? '',
        },
        'theme': {'color': '#1B6B7A'},
      };
      _razorpay.open(options);
    } catch (e) {
      setState(() => _creatingOrder = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not start payment: $e'), backgroundColor: AppColors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_paid) {
      return const Scaffold(body: Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center, children: [
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
          // Bill summary
          Container(padding: const EdgeInsets.all(20),
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
                ])),
              ]),
              const Divider(height: 24, color: AppColors.line),
              _billRow('Service Amount', 'Rs.$_baseAmount'),
              if (_pendingPenalty > 0) ...[
                const SizedBox(height: 8),
                Container(padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: AppColors.red.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.red.withOpacity(0.2))),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Row(children: [
                      Icon(Icons.warning_amber_rounded, color: AppColors.red, size: 14),
                      SizedBox(width: 6),
                      Text('Cancellation Penalty', style: TextStyle(fontSize: 13, color: AppColors.red, fontWeight: FontWeight.w600)),
                    ]),
                    Text('+ Rs.$_pendingPenalty', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.red)),
                  ])),
              ],
              const Divider(height: 20, color: AppColors.line),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Total Amount', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink)),
                Text('Rs.$_totalAmount', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: AppColors.red)),
              ]),
            ])),

          const SizedBox(height: 20),

          // Online payment only — NO cash option
          Container(padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.tealSoft, borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.teal)),
            child: Row(children: [
              const Text('🔒', style: TextStyle(fontSize: 28)),
              const SizedBox(width: 14),
              const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Secure Online Payment', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.teal)),
                Text('UPI · Cards · Net Banking', style: TextStyle(fontSize: 12, color: AppColors.muted)),
              ])),
              Container(width: 22, height: 22,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.teal),
                child: const Icon(Icons.check, color: Colors.white, size: 14)),
            ])),

          const SizedBox(height: 20),

          SizedBox(width: double.infinity,
            child: ElevatedButton(
              onPressed: (_loading || _creatingOrder) ? null : _startPayment,
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
                  : Text('Pay Rs.$_totalAmount Securely',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)))),

          const SizedBox(height: 12),
          const Text('Secured by Razorpay · 256-bit encryption',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: AppColors.muted)),
          const SizedBox(height: 32),
        ]),
      ),
    );
  }


// ── Commission rates — MUST match provider earnings_screen.dart ─
double _getCommissionRate(String service) {
  final s = service.toLowerCase();
  // Exact-name check first (most reliable)
  const Map<String, double> rates = {
    'house maid': 10, 'deep cleaning': 12, 'bathroom cleaning': 10,
    'kitchen cleaning': 12, 'sofa / carpet cleaning': 12, 'laundry / ironing': 10,
    'pest control': 10, 'gardener': 10, 'ac cleaning & repair': 15,
    'home appliance repair': 18, 'water purifier service': 15,
    'plumber': 20, 'electrician': 20, 'carpenter': 12, 'painter': 12,
    'cctv installation': 15, 'solar panel cleaning': 12,
    'car / bike wash': 10, 'car & bike mechanic': 15,
    'cook / cooking person': 10, "men's haircut at home": 12,
    "women's haircut & beauty": 12, 'full body massage': 15,
    'gym / fitness trainer': 15, 'doctor visit at home': 15,
    'nurse visit at home': 15, 'lab test collection': 15,
    'babysitter / nanny': 10, 'elderly care': 10,
    'driver': 15, 'security guard & bouncers': 10,
  };
  // Check exact name
  if (rates.containsKey(s)) return rates[s]!;
  // Fallback keyword check
  if (s.contains('electrician') || s.contains('plumber')) return 20;
  if (s.contains('appliance') || s.contains('repair')) return 18;
  if (s.contains('ac') || s.contains('air condition')) return 15;
  if (s.contains('deep clean') || s.contains('kitchen')) return 12;
  if (s.contains('carpenter') || s.contains('painter')) return 12;
  if (s.contains('doctor') || s.contains('nurse') || s.contains('lab')) return 15;
  if (s.contains('fitness') || s.contains('massage') || s.contains('beauty')) return 15;
  if (s.contains('mechanic') || s.contains('driver') || s.contains('cctv')) return 15;
  return 10; // default
}

  Widget _billRow(String label, String value) {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: const TextStyle(fontSize: 13, color: AppColors.muted)),
      Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink)),
    ]);
  }
}
