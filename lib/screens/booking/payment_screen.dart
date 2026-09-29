import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/api_service.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../../utils/theme.dart';
import 'review_screen.dart';

/// Pays for a booking whose status is active/completed and whose
/// payment_status is not 'paid' (see [PaymentScreen.isPayable]).
///
/// Online: create-order.php → Razorpay checkout → bookings.php
/// razorpay_confirm (server verifies the signature and marks it paid).
/// Cash: bookings.php mark_paid → 'cash_pending' until the provider confirms.
/// The customer never completes the booking — the provider does that with
/// the customer's completion OTP.
class PaymentScreen extends StatefulWidget {
  final String bookingId;
  final Map<String, dynamic> booking;
  const PaymentScreen({super.key, required this.bookingId, required this.booking});
  @override
  State<PaymentScreen> createState() => _PaymentScreenState();

  // Booking ids whose PaymentScreen is currently open (or being opened), ids
  // already paid in this session, and ids we already auto-prompted for.
  // Shared by every poller (HomeScreen, MyBookingsScreen) so a payable status
  // doesn't push a new screen on every poll tick.
  static final Set<String> _openIds = <String>{};
  static final Set<String> _paidIds = <String>{};
  static final Set<String> _promptedIds = <String>{};

  /// Contract: pay when status in (active, completed) and not yet paid.
  /// 'cash_pending' is excluded — the provider still has to confirm cash.
  static bool isPayable(Map<String, dynamic> b) {
    final id = b['id']?.toString() ?? '';
    if (_paidIds.contains(id)) return false;
    final status = b['status']?.toString() ?? '';
    final pay = b['payment_status']?.toString() ?? '';
    return (status == 'active' || status == 'completed') &&
        pay != 'paid' && pay != 'cash_pending';
  }

  /// Returns true if the caller may open a PaymentScreen for [bookingId].
  /// The id stays reserved until the screen is disposed or [release] is called.
  static bool reserve(String bookingId) {
    if (_paidIds.contains(bookingId)) return false;
    return _openIds.add(bookingId);
  }

  /// Like [reserve], but only succeeds once per booking per app session, so an
  /// automatic prompt doesn't reappear after the customer closes the screen.
  static bool reserveAutoPrompt(String bookingId) {
    if (_promptedIds.contains(bookingId)) return false;
    if (!reserve(bookingId)) return false;
    _promptedIds.add(bookingId);
    return true;
  }

  static void release(String bookingId) => _openIds.remove(bookingId);
}

class _PaymentScreenState extends State<PaymentScreen> {
  bool _loading = false;
  bool _paid = false;
  bool _creatingOrder = false;
  bool _cashLoading = false;
  int _serverAmount = 0; // rupees, from create-order.php
  late Razorpay _razorpay;

  @override
  void initState() {
    super.initState();
    PaymentScreen._openIds.add(widget.bookingId);
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _onError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _onWallet);
  }

  @override
  void dispose() {
    PaymentScreen.release(widget.bookingId);
    _razorpay.clear();
    super.dispose();
  }

  String _s(List<String> keys, [String fallback = '']) {
    for (final k in keys) {
      final v = widget.booking[k]?.toString() ?? '';
      if (v.isNotEmpty) return v;
    }
    return fallback;
  }

  String get _serviceName => _s(['svc_name', 'service'], 'Home Service');
  String get _serviceIcon => _s(['svc_icon', 'icon'], '🔧');
  String get _providerName => _s(['provider_name', 'providerName']);

  // Server-side payable = confirmed_price, else amount (bookingPayable()).
  // MySQL rows may return numbers as strings.
  int get _baseAmount {
    final b = widget.booking;
    for (final k in ['confirmed_price', 'amount', 'confirmedPrice', 'price']) {
      final v = num.tryParse(b[k]?.toString() ?? '');
      if (v != null && v > 0) return v.toInt();
    }
    return 0;
  }
  int get _totalAmount => _serverAmount > 0 ? _serverAmount : _baseAmount;

  void _onSuccess(PaymentSuccessResponse r) async {
    HapticFeedback.heavyImpact();
    if (!mounted) return;
    setState(() => _loading = true);

    // Verify the Razorpay signature server-side; this also marks the
    // booking paid. Nothing else is trusted client-side.
    bool verified = false;
    String verifyError = '';
    try {
      final res = await ApiService.confirmRazorpayPayment(
        bookingId: widget.bookingId,
        razorpayOrderId: r.orderId ?? '',
        razorpayPaymentId: r.paymentId ?? '',
        razorpaySignature: r.signature ?? '',
      );
      verified = res['success'] == true;
      if (!verified) verifyError = res['error']?.toString() ?? '';
    } catch (_) {}

    if (!verified) {
      if (!mounted) return;
      setState(() => _loading = false);
      final pid = r.paymentId ?? '';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Payment could not be verified'
            '${verifyError.isNotEmpty ? ' ($verifyError)' : ''}. '
            'If money was debited, contact support'
            '${pid.isNotEmpty ? ' with payment ID $pid' : ''}.'),
        backgroundColor: AppColors.red,
        duration: const Duration(seconds: 8)));
      return;
    }

    PaymentScreen._paidIds.add(widget.bookingId);
    HapticFeedback.heavyImpact();
    if (!mounted) return;
    setState(() { _loading = false; _paid = true; });

    // Review is only possible once the provider has completed the job.
    final fresh = await ApiService.getBooking(widget.bookingId);
    final status = (fresh?['status'] ?? widget.booking['status'])?.toString() ?? '';
    await Future.delayed(const Duration(milliseconds: 1000));
    if (!mounted) return;
    if (status == 'completed') {
      Navigator.pushReplacement(context, MaterialPageRoute(
          builder: (_) => ReviewScreen(bookingId: widget.bookingId, booking: fresh ?? widget.booking)));
    } else {
      Navigator.pop(context, true);
    }
  }

  void _onError(PaymentFailureResponse r) {
    HapticFeedback.heavyImpact();
    if (!mounted) return;
    setState(() => _loading = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Payment failed: ${r.message ?? 'Please try again'}'),
      backgroundColor: AppColors.red));
  }

  void _onWallet(ExternalWalletResponse r) {}

  Future<void> _startPayment() async {
    HapticFeedback.mediumImpact();
    setState(() => _creatingOrder = true);
    final order = await ApiService.createPaymentOrder(widget.bookingId);
    if (!mounted) return;
    setState(() => _creatingOrder = false);
    if (order['success'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not start payment: ${order['error'] ?? 'Please try again'}'),
        backgroundColor: AppColors.red));
      return;
    }
    final paise = order['amount'] as int? ?? 0;
    if (paise > 0) setState(() => _serverAmount = paise ~/ 100);
    final user = FirebaseAuth.instance.currentUser;
    final options = {
      'key': order['key_id'],
      'amount': paise,
      'currency': order['currency'] ?? 'INR',
      'name': 'HamaraService',
      'description': _serviceName,
      'order_id': order['order_id'],
      'prefill': {
        'name': _s(['customer_name', 'customer'], user?.displayName ?? ''),
        'contact': _s(['customer_phone', 'phone']),
        'email': user?.email ?? '',
      },
      'theme': {'color': '#1B6B7A'},
    };
    try {
      _razorpay.open(options);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not open payment: $e'), backgroundColor: AppColors.red));
    }
  }

  Future<void> _payCash() async {
    HapticFeedback.mediumImpact();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Pay in cash?', style: TextStyle(fontWeight: FontWeight.w800)),
        content: Text('Hand Rs.$_totalAmount in cash to '
            '${_providerName.isNotEmpty ? _providerName : 'your provider'}. '
            'The payment is marked complete once they confirm receiving it.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Back', style: TextStyle(color: AppColors.muted))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.teal),
            child: const Text('I paid in cash', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _cashLoading = true);
    final res = await ApiService.markPaidCash(widget.bookingId);
    if (!mounted) return;
    setState(() => _cashLoading = false);
    if (res['success'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res['error']?.toString() ?? 'Could not record cash payment'),
        backgroundColor: AppColors.red));
      return;
    }
    final ps = (res['data'] is Map ? (res['data'] as Map)['payment_status'] : null)?.toString() ?? 'cash_pending';
    if (ps == 'paid') PaymentScreen._paidIds.add(widget.bookingId);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ps == 'paid'
          ? 'Payment confirmed. Thank you!'
          : 'Cash payment recorded — awaiting provider confirmation.'),
      backgroundColor: AppColors.green));
    Navigator.pop(context, true);
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
          Text('Thank you!', style: TextStyle(color: AppColors.muted)),
        ])));
    }
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('Payment'), backgroundColor: AppColors.teal, foregroundColor: Colors.white),
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
                  child: Center(child: Text(_serviceIcon, style: const TextStyle(fontSize: 28)))),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_serviceName,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.ink)),
                  Text('Provider: $_providerName',
                    style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                ])),
              ]),
              const Divider(height: 24, color: AppColors.line),
              _billRow('Service Amount', 'Rs.$_baseAmount'),
              const Divider(height: 20, color: AppColors.line),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Total Amount', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink)),
                Text('Rs.$_totalAmount', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: AppColors.red)),
              ]),
            ])),

          const SizedBox(height: 20),

          // Online payment (UPI / cards) — or cash below
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
              onPressed: (_loading || _creatingOrder || _cashLoading) ? null : _startPayment,
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
          SizedBox(width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: (_loading || _creatingOrder || _cashLoading) ? null : _payCash,
              icon: _cashLoading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.teal))
                  : const Icon(Icons.payments_outlined, color: AppColors.teal),
              label: Text('Pay Rs.$_totalAmount in Cash',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.teal)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.teal),
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))))),
          const SizedBox(height: 12),
          const Text('Secured by Razorpay · 256-bit encryption',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: AppColors.muted)),
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