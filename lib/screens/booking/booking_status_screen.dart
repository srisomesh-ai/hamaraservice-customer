import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/api_service.dart';
import '../../utils/booking_format.dart';
import '../../utils/sound_manager.dart';
import '../../utils/theme.dart';
import 'review_screen.dart';

// ══════════════════════════════════════════════════════════════
// Booking status — the ONE screen that tracks a booking from
// "searching" to "paid". Driven by polling bookings.php?action=get
// every 4 s while the app is in the foreground.
// ══════════════════════════════════════════════════════════════
class BookingStatusScreen extends StatefulWidget {
  final String bookingId;
  const BookingStatusScreen({super.key, required this.bookingId});

  /// Id of the booking currently shown (used to avoid opening it twice
  /// from notification taps).
  static String? openBookingId;

  @override
  State<BookingStatusScreen> createState() => _BookingStatusScreenState();
}

class _BookingStatusScreenState extends State<BookingStatusScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  static const _pollEvery = Duration(seconds: 4);
  static const _searchPatience = Duration(minutes: 3);

  Map<String, dynamic>? _b;
  String _loadError = '';
  bool _busy = false;
  bool _cashChosen = false;
  bool _navigatedToReview = false;
  String _lastStatus = '';
  Timer? _poll;
  bool _fetching = false;
  final DateTime _openedAt = DateTime.now();

  late final AnimationController _sweepCtrl;
  late final Razorpay _razorpay;
  String _pendingOrderId = '';

  String get _id => widget.bookingId;
  String get _status => asStr(_b?['status']);

  @override
  void initState() {
    super.initState();
    BookingStatusScreen.openBookingId = _id;
    WidgetsBinding.instance.addObserver(this);
    _sweepCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2500))
      ..repeat();
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onPaySuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _onPayError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _onExternalWallet);
    _refresh();
    _startPolling();
  }

  @override
  void dispose() {
    if (BookingStatusScreen.openBookingId == _id) {
      BookingStatusScreen.openBookingId = null;
    }
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _sweepCtrl.dispose();
    _razorpay.clear();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _poll?.cancel();
      _poll = null;
    } else if (state == AppLifecycleState.resumed) {
      _refresh();
      _startPolling();
    }
  }

  bool get _isTerminal {
    final s = _status;
    if (s == BookingStatus.cancelled) return true;
    if (s == BookingStatus.completed && isPaid(_b ?? {})) return true;
    return false;
  }

  void _startPolling() {
    _poll?.cancel();
    if (_isTerminal) return;
    _poll = Timer.periodic(_pollEvery, (_) => _refresh());
  }

  Future<void> _refresh() async {
    if (_fetching) return;
    _fetching = true;
    try {
      final b = await ApiService.getBooking(_id);
      if (!mounted) return;
      final prev = _lastStatus;
      setState(() {
        _b = b;
        _loadError = '';
      });
      _lastStatus = _status;
      if (prev.isNotEmpty && prev != _lastStatus) _onStatusChanged(prev, _lastStatus);
      if (_isTerminal) {
        _poll?.cancel();
        _poll = null;
      }
      _maybeOpenReview();
    } on ApiException catch (e) {
      if (mounted && _b == null) setState(() => _loadError = e.message);
    } finally {
      _fetching = false;
    }
  }

  void _onStatusChanged(String from, String to) {
    HapticFeedback.mediumImpact();
    if (to == BookingStatus.priceQuoted ||
        to == BookingStatus.negotiationFinal ||
        to == BookingStatus.confirmed) {
      SoundManager.play(AppSound.orderAccepted);
    } else if (to == BookingStatus.cancelled) {
      SoundManager.play(AppSound.cancelled);
    }
  }

  void _maybeOpenReview() {
    final b = _b;
    if (b == null || _navigatedToReview) return;
    if (_status == BookingStatus.completed &&
        isPaid(b) &&
        asInt(b['rating']) == 0) {
      _navigatedToReview = true;
      Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (_) => ReviewScreen(bookingId: _id, booking: b)));
    }
  }

  // ── Actions ─────────────────────────────────────────────
  Future<void> _run(Future<void> Function() action,
      {String? success}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (success != null) _toast(success);
      await _refresh();
    } on ApiException catch (e) {
      _toast(e.message, error: true);
      await _refresh();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: error ? AppColors.red : AppColors.teal));
  }

  Future<void> _acceptPrice() => _run(
      () => ApiService.confirmPrice(_id,
          shownPrice: asStr(_b?['status']) == 'negotiation_final'
              ? asInt(_b?['final_price'])
              : asInt(_b?['quoted_price'])),
      success: 'Price accepted. Booking confirmed!');

  Future<void> _decline() => _run(() => ApiService.declineQuote(_id),
      success: 'Quote declined. Looking for another provider…');

  Future<void> _searchAnother() => _run(() => ApiService.searchAnother(_id),
      success: 'Looking for another provider…');

  Future<void> _negotiate() async {
    final quote = asInt(_b?['quoted_price']);
    final ctrl = TextEditingController();
    String? err;
    final counter = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Make a counter offer',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Provider quoted ₹$quote. Enter a lower price you are happy to pay.',
                style: const TextStyle(fontSize: 13, color: AppColors.muted)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                prefixText: '₹ ',
                hintText: 'Your price',
                errorText: err,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Back')),
            ElevatedButton(
              onPressed: () {
                final v = int.tryParse(ctrl.text.trim()) ?? 0;
                if (v <= 0) {
                  setS(() => err = 'Enter an amount');
                } else if (quote > 0 && v >= quote) {
                  setS(() => err = 'Must be less than ₹$quote');
                } else {
                  Navigator.pop(ctx, v);
                }
              },
              child: const Text('Send offer'),
            ),
          ],
        ),
      ),
    );
    // (controller left to GC — disposing while the dialog animates out throws)
    if (counter == null) return;
    await _run(() => ApiService.negotiate(_id, counter),
        success: 'Counter offer of ₹$counter sent.');
  }

  Future<void> _cancel() async {
    String? reason;
    final otherCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Cancel booking?',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          content: SingleChildScrollView(
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Reason',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink)),
                  ...[
                    'Service no longer needed',
                    'Booked by mistake',
                    'Price too high',
                    'Taking too long to find a provider',
                    'Other reason',
                  ].map((r) => RadioListTile<String>(
                        value: r,
                        groupValue: reason,
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        activeColor: AppColors.teal,
                        title: Text(r, style: const TextStyle(fontSize: 13)),
                        onChanged: (v) => setS(() => reason = v),
                      )),
                  if (reason == 'Other reason')
                    TextField(
                      controller: otherCtrl,
                      maxLines: 2,
                      decoration: InputDecoration(
                          hintText: 'Tell us more…',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10))),
                    ),
                ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Keep booking')),
            ElevatedButton(
              onPressed: reason == null ? null : () => Navigator.pop(ctx, true),
              style:
                  ElevatedButton.styleFrom(backgroundColor: AppColors.red),
              child: const Text('Cancel booking',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
    final text = (reason == 'Other reason' && otherCtrl.text.trim().isNotEmpty)
        ? otherCtrl.text.trim()
        : (reason ?? '');
    if (ok != true) return;
    await _run(() => ApiService.cancelBooking(_id, text),
        success: 'Booking cancelled.');
  }

  // ── Payment ─────────────────────────────────────────────
  Future<void> _payOnline() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final order = await ApiService.createOrder(_id);
      final orderId = asStr(order['order_id']);
      final key = asStr(order['key_id']);
      final amount = asInt(order['amount']); // paise, set by server
      if (orderId.isEmpty || key.isEmpty || amount <= 0) {
        throw const ApiException('Could not start payment. Please try again.');
      }
      _pendingOrderId = orderId;
      final user = FirebaseAuth.instance.currentUser;
      _razorpay.open({
        'key': key,
        'amount': amount,
        'currency': asStr(order['currency']).isEmpty ? 'INR' : asStr(order['currency']),
        'name': 'HamaraService',
        'description': asStr(_b?['svc_name']).isEmpty ? 'Home service' : asStr(_b?['svc_name']),
        'order_id': orderId,
        'prefill': {
          'name': asStr(_b?['contact_name']),
          'contact': asStr(_b?['contact_phone']),
          'email': user?.email ?? '',
        },
        'theme': {'color': '#1B6B7A'},
      });
      // _busy is cleared by the Razorpay callbacks
    } on ApiException catch (e) {
      if (mounted) setState(() => _busy = false);
      _toast(e.message, error: true);
    } catch (e) {
      if (mounted) setState(() => _busy = false);
      _toast('Could not open payment: $e', error: true);
    }
  }

  Future<void> _onPaySuccess(PaymentSuccessResponse r) async {
    try {
      final res = await ApiService.razorpayConfirm(
        bookingId: _id,
        orderId: r.orderId ?? _pendingOrderId,
        paymentId: r.paymentId ?? '',
        signature: r.signature ?? '',
      );
      if (asStr(res['payment_status']) == 'paid') {
        SoundManager.play(AppSound.payment);
        _toast('Payment successful!');
      }
      await _refresh(); // navigates to review when paid
    } on ApiException catch (e) {
      _toast(
          'Payment received by Razorpay but could not be verified yet: ${e.message}. '
          'It will update automatically if the payment went through.',
          error: true);
      await _refresh();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _onPayError(PaymentFailureResponse r) {
    if (mounted) setState(() => _busy = false);
    final msg = (r.message ?? '').isNotEmpty ? r.message! : 'Payment cancelled or failed.';
    _toast('Payment failed: $msg', error: true);
  }

  void _onExternalWallet(ExternalWalletResponse r) {
    _toast('Opening ${r.walletName ?? 'wallet'}…');
  }

  // ── UI ──────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final b = _b;
    return Scaffold(
      backgroundColor: _status == BookingStatus.searching
          ? const Color(0xFF080C14)
          : AppColors.bg,
      appBar: AppBar(
        backgroundColor: _status == BookingStatus.searching
            ? const Color(0xFF080C14)
            : AppColors.teal,
        foregroundColor: Colors.white,
        title: Text(b == null ? 'Booking' : asStr(b['svc_name'])),
        actions: [
          IconButton(
              onPressed: _busy ? null : _refresh,
              icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: b == null ? _buildLoading() : _buildBody(b),
    );
  }

  Widget _buildLoading() {
    if (_loadError.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline_rounded,
                color: AppColors.red, size: 48),
            const SizedBox(height: 12),
            Text(_loadError,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.ink2)),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _refresh, child: const Text('Retry')),
          ]),
        ),
      );
    }
    return const Center(
        child: CircularProgressIndicator(color: AppColors.teal));
  }

  Widget _buildBody(Map<String, dynamic> b) {
    switch (_status) {
      case BookingStatus.searching:
        return _buildSearching(b);
      default:
        return RefreshIndicator(
          onRefresh: _refresh,
          color: AppColors.teal,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              _statusHeader(b),
              const SizedBox(height: 14),
              ..._stateContent(b),
              const SizedBox(height: 14),
              _detailsCard(b),
              if (BookingStatus.cancellable.contains(_status)) ...[
                const SizedBox(height: 14),
                _cancelButton(),
              ],
              const SizedBox(height: 24),
            ],
          ),
        );
    }
  }

  List<Widget> _stateContent(Map<String, dynamic> b) {
    switch (_status) {
      case BookingStatus.priceQuoted:
        return _buildQuoted(b);
      case BookingStatus.negotiating:
        return _buildNegotiating(b);
      case BookingStatus.negotiationFinal:
        return _buildFinalOffer(b);
      case BookingStatus.confirmed:
        return _buildConfirmed(b);
      case BookingStatus.active:
        return _buildActive(b);
      case BookingStatus.completed:
        return _buildCompleted(b);
      case BookingStatus.cancelled:
        return _buildCancelled(b);
      default:
        return [
          _infoBox(Icons.info_outline_rounded,
              'Status: ${statusLabel(b)}', AppColors.muted)
        ];
    }
  }

  // ── searching ───────────────────────────────────────────
  Widget _buildSearching(Map<String, dynamic> b) {
    final waitingLong =
        DateTime.now().difference(_openedAt) > _searchPatience;
    return SafeArea(
      child: Column(children: [
        const SizedBox(height: 24),
        SizedBox(
          width: 220,
          height: 220,
          child: AnimatedBuilder(
            animation: _sweepCtrl,
            builder: (_, __) => CustomPaint(
                painter: _RadarPainter(_sweepCtrl.value * 2 * pi)),
          ),
        ),
        const SizedBox(height: 20),
        const Text('Looking for a provider',
            style: TextStyle(
                fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            'Your ${asStr(b['svc_name'])} request is visible to available providers near you. '
            'You will see their price here as soon as one accepts.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 13, color: Colors.white.withOpacity(0.6), height: 1.5),
          ),
        ),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Column(children: [
              _darkRow(Icons.calendar_today_rounded, slotLabel(b)),
              const SizedBox(height: 6),
              _darkRow(Icons.location_on_rounded, asStr(b['address'])),
              if (asInt(b['est_price']) > 0) ...[
                const SizedBox(height: 6),
                _darkRow(Icons.currency_rupee_rounded,
                    'Estimate ₹${asInt(b['est_price'])} — final price agreed with provider'),
              ],
            ]),
          ),
        ),
        if (waitingLong) ...[
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.yellow.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.yellow.withOpacity(0.4)),
              ),
              child: const Text(
                'No provider has responded yet. Your request stays open and we will keep '
                'looking — you will get a notification when a provider sends a price. '
                'You can safely leave this screen.',
                style: TextStyle(fontSize: 12, color: AppColors.yellow, height: 1.5),
              ),
            ),
          ),
        ],
        const Spacer(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  side: BorderSide(color: Colors.white.withOpacity(0.3)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(100)),
                ),
                child: const Text('Back to home',
                    style: TextStyle(color: Colors.white)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton(
                onPressed: _busy ? null : _cancel,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  side: const BorderSide(color: AppColors.red),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(100)),
                ),
                child: const Text('Cancel request',
                    style: TextStyle(color: AppColors.red)),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _darkRow(IconData icon, String text) => Row(children: [
        Icon(icon, size: 15, color: Colors.white.withOpacity(0.5)),
        const SizedBox(width: 8),
        Expanded(
            child: Text(text,
                style: TextStyle(
                    fontSize: 12, color: Colors.white.withOpacity(0.75)))),
      ]);

  // ── price_quoted ────────────────────────────────────────
  List<Widget> _buildQuoted(Map<String, dynamic> b) {
    final quote = asInt(b['quoted_price']);
    return [
      _providerCard(b),
      const SizedBox(height: 14),
      _priceCard('QUOTED PRICE', quote,
          'Includes the work you selected. You pay only after the service.'),
      const SizedBox(height: 14),
      _primaryButton('Accept ₹$quote', _acceptPrice),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: _secondaryButton('Negotiate', _negotiate)),
        const SizedBox(width: 10),
        Expanded(
            child: _secondaryButton('Decline', _decline, color: AppColors.red)),
      ]),
    ];
  }

  // ── negotiating ─────────────────────────────────────────
  List<Widget> _buildNegotiating(Map<String, dynamic> b) {
    return [
      _providerCard(b),
      const SizedBox(height: 14),
      _infoBox(
          Icons.hourglass_top_rounded,
          'You offered ₹${asInt(b['counter_price'])} (quote was ₹${asInt(b['quoted_price'])}). '
          'Waiting for the provider to accept or send a final offer…',
          AppColors.brand),
    ];
  }

  // ── negotiation_final ───────────────────────────────────
  List<Widget> _buildFinalOffer(Map<String, dynamic> b) {
    final fp = asInt(b['final_price']);
    return [
      _providerCard(b),
      const SizedBox(height: 14),
      _priceCard('FINAL OFFER', fp,
          'This is the provider\'s final price — no further negotiation.'),
      const SizedBox(height: 14),
      _primaryButton('Accept ₹$fp', _acceptPrice),
      const SizedBox(height: 10),
      _secondaryButton('Find another provider', _searchAnother),
    ];
  }

  // ── confirmed ───────────────────────────────────────────
  List<Widget> _buildConfirmed(Map<String, dynamic> b) {
    final otp = asStr(b['start_otp']);
    return [
      _providerCard(b, showContact: true),
      const SizedBox(height: 14),
      if (otp.isNotEmpty)
        _otpCard(
          title: 'START OTP',
          otp: otp,
          note: 'Share this OTP with your provider when they arrive.',
          color: AppColors.teal,
        )
      else
        _infoBox(Icons.lock_clock_rounded,
            'Your start OTP will appear here shortly.', AppColors.teal),
      const SizedBox(height: 14),
      _priceCard('AGREED PRICE', bookingPrice(b), 'Pay after the service is completed.'),
    ];
  }

  // ── active ──────────────────────────────────────────────
  List<Widget> _buildActive(Map<String, dynamic> b) {
    final otp = asStr(b['completion_otp']);
    return [
      _infoBox(Icons.handyman_rounded,
          'Job in progress. Your provider has started the work.', AppColors.brand),
      const SizedBox(height: 14),
      if (otp.isNotEmpty)
        _otpCard(
          title: 'COMPLETION OTP',
          otp: otp,
          note: 'Completion OTP — share only when you are satisfied with the work.',
          color: AppColors.green,
        )
      else
        _infoBox(
            Icons.info_outline_rounded,
            'When the work is finished, the provider will request a completion OTP. '
            'It will appear here — share it only when you are satisfied.',
            AppColors.muted),
      const SizedBox(height: 14),
      _providerCard(b, showContact: true),
    ];
  }

  // ── completed ───────────────────────────────────────────
  List<Widget> _buildCompleted(Map<String, dynamic> b) {
    final amount = bookingPrice(b);
    if (isPaid(b)) {
      final rating = asInt(b['rating']);
      return [
        _infoBox(
            Icons.check_circle_rounded,
            'Paid ₹$amount${asStr(b['payment_method']).isNotEmpty ? ' (${asStr(b['payment_method'])})' : ''}. Thank you!',
            AppColors.green),
        const SizedBox(height: 14),
        if (rating == 0)
          _primaryButton('Rate your provider', () async {
            await Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => ReviewScreen(bookingId: _id, booking: b)));
            _refresh();
          })
        else
          _infoBox(Icons.star_rounded, 'You rated this service $rating★.',
              AppColors.yellow),
      ];
    }
    return [
      _infoBox(Icons.task_alt_rounded,
          'Service completed. Please pay your provider.', AppColors.green),
      const SizedBox(height: 14),
      _priceCard('AMOUNT DUE', amount, 'Pay online, or pay the provider in cash.'),
      const SizedBox(height: 14),
      _primaryButton('Pay ₹$amount online', _payOnline),
      const SizedBox(height: 6),
      const Text('UPI · Cards · Net banking — secured by Razorpay',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: AppColors.muted)),
      const SizedBox(height: 12),
      if (_cashChosen)
        _infoBox(
            Icons.payments_rounded,
            'Pay ₹$amount in cash to your provider. This screen updates automatically '
            'once they confirm they received it.',
            AppColors.teal)
      else
        _secondaryButton("I'll pay cash — provider will confirm",
            () async => setState(() => _cashChosen = true)),
    ];
  }

  // ── cancelled ───────────────────────────────────────────
  List<Widget> _buildCancelled(Map<String, dynamic> b) {
    final reason = asStr(b['cancel_reason']);
    final by = asStr(b['cancelled_by']);
    return [
      _infoBox(
          Icons.cancel_rounded,
          'This booking was cancelled${by.isNotEmpty ? ' by $by' : ''}.'
          '${reason.isNotEmpty ? '\nReason: $reason' : ''}',
          AppColors.red),
      const SizedBox(height: 14),
      _primaryButton('Back to home', () async => Navigator.pop(context)),
    ];
  }

  // ── Building blocks ─────────────────────────────────────
  Widget _statusHeader(Map<String, dynamic> b) {
    final c = statusColor(b);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)],
      ),
      child: Row(children: [
        Text(asStr(b['svc_icon']).isEmpty ? '🔧' : asStr(b['svc_icon']),
            style: const TextStyle(fontSize: 30)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(asStr(b['svc_name']),
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink)),
            Text('Booking ${shortBookingId(asStr(b['id']))}',
                style: const TextStyle(fontSize: 11, color: AppColors.muted)),
          ]),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
              color: c.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20)),
          child: Text(statusLabel(b),
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: c)),
        ),
      ]),
    );
  }

  Widget _providerCard(Map<String, dynamic> b, {bool showContact = false}) {
    final name = asStr(b['provider_name']).isEmpty ? 'Your provider' : asStr(b['provider_name']);
    final rating = asDouble(b['provider_rating']) ?? 0;
    final reviews = asInt(b['provider_reviews']);
    final phone = asStr(b['provider_phone']);
    final dist = asDouble(b['distance_km']);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.greenSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.green.withOpacity(0.3)),
      ),
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
              color: AppColors.green.withOpacity(0.2), shape: BoxShape.circle),
          child: const Icon(Icons.person_rounded, color: AppColors.green),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.ink)),
            if (rating > 0)
              Text('★ ${rating.toStringAsFixed(1)}${reviews > 0 ? ' · $reviews reviews' : ''}',
                  style: const TextStyle(fontSize: 12, color: AppColors.ink2))
            else
              const Text('New provider — no ratings yet',
                  style: TextStyle(fontSize: 12, color: AppColors.muted)),
            if (showContact && dist != null)
              Text('${dist.toStringAsFixed(1)} km away',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted)),
            if (showContact && phone.isNotEmpty)
              Text(phone, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          ]),
        ),
        if (showContact && phone.isNotEmpty)
          IconButton.filled(
            onPressed: () async {
              HapticFeedback.mediumImpact();
              final ok = await launchUrl(Uri.parse('tel:$phone'));
              if (!ok) _toast('Could not open the dialer', error: true);
            },
            style: IconButton.styleFrom(backgroundColor: AppColors.green),
            icon: const Icon(Icons.phone_rounded, color: Colors.white),
          ),
      ]),
    );
  }

  Widget _priceCard(String label, int price, String note) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.tealSoft,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.teal.withOpacity(0.3)),
        ),
        child: Column(children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: AppColors.muted,
                  letterSpacing: .5)),
          const SizedBox(height: 6),
          Text(price > 0 ? '₹$price' : '—',
              style: const TextStyle(
                  fontSize: 36, fontWeight: FontWeight.w900, color: AppColors.teal)),
          const SizedBox(height: 4),
          Text(note,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: AppColors.muted)),
        ]),
      );

  Widget _otpCard({
    required String title,
    required String otp,
    required String note,
    required Color color,
  }) =>
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color, width: 2),
          boxShadow: [BoxShadow(color: color.withOpacity(0.15), blurRadius: 16)],
        ),
        child: Column(children: [
          Text(title,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: color,
                  letterSpacing: 1)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: otp
                .split('')
                .map((d) => Container(
                      width: 48,
                      height: 58,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: AppColors.bg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: color, width: 2),
                      ),
                      child: Center(
                          child: Text(d,
                              style: const TextStyle(
                                  fontSize: 30,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.ink))),
                    ))
                .toList(),
          ),
          const SizedBox(height: 12),
          Text(note,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink2)),
        ]),
      );

  Widget _detailsCard(Map<String, dynamic> b) {
    final landmark = asStr(b['landmark']);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _row(Icons.calendar_today_rounded, slotLabel(b)),
        const SizedBox(height: 6),
        _row(Icons.location_on_rounded,
            '${asStr(b['address'])}${landmark.isNotEmpty ? ' (near $landmark)' : ''}'),
        if (asStr(b['contact_name']).isNotEmpty || asStr(b['contact_phone']).isNotEmpty) ...[
          const SizedBox(height: 6),
          _row(Icons.person_rounded,
              '${asStr(b['contact_name'])} ${asStr(b['contact_phone'])}'.trim()),
        ],
      ]),
    );
  }

  Widget _row(IconData icon, String text) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: AppColors.teal),
          const SizedBox(width: 8),
          Expanded(
              child: Text(text,
                  style: const TextStyle(fontSize: 13, color: AppColors.ink2))),
        ],
      );

  Widget _infoBox(IconData icon, String text, Color color) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
              child: Text(text,
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.ink2, height: 1.4))),
        ]),
      );

  Widget _primaryButton(String label, Future<void> Function() onTap) =>
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _busy ? null : () => onTap(),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.teal,
            minimumSize: const Size(double.infinity, 52),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: _busy
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation(Colors.white)))
              : Text(label,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Colors.white)),
        ),
      );

  Widget _secondaryButton(String label, Future<void> Function() onTap,
          {Color color = AppColors.teal}) =>
      SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: _busy ? null : () => onTap(),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 48),
            side: BorderSide(color: color),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700, color: color)),
        ),
      );

  Widget _cancelButton() => TextButton.icon(
        onPressed: _busy ? null : _cancel,
        icon: const Icon(Icons.close_rounded, color: AppColors.red, size: 18),
        label: const Text('Cancel booking',
            style: TextStyle(color: AppColors.red, fontWeight: FontWeight.w700)),
      );
}

// Cosmetic radar sweep for the "searching" state.
class _RadarPainter extends CustomPainter {
  final double sweep;
  _RadarPainter(this.sweep);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final maxR = size.width / 2;
    const green = Color(0xFF00FF88);
    for (int i = 1; i <= 4; i++) {
      canvas.drawCircle(
          c,
          maxR * i / 4,
          Paint()
            ..color = green.withOpacity(0.08)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1);
    }
    canvas.drawCircle(
        c,
        maxR,
        Paint()
          ..shader = SweepGradient(
            startAngle: sweep - 0.6,
            endAngle: sweep,
            colors: [Colors.transparent, green.withOpacity(0.18)],
          ).createShader(Rect.fromCircle(center: c, radius: maxR)));
    canvas.drawLine(
        c,
        Offset(c.dx + maxR * cos(sweep - pi / 2), c.dy + maxR * sin(sweep - pi / 2)),
        Paint()
          ..color = green.withOpacity(0.6)
          ..strokeWidth = 2);
    canvas.drawCircle(c, 6, Paint()..color = AppColors.teal);
  }

  @override
  bool shouldRepaint(_RadarPainter old) => old.sweep != sweep;
}
