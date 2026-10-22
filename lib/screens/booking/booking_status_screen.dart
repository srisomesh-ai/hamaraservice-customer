import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/api_service.dart';
import '../../services/session.dart';
import '../../utils/booking_format.dart';
import '../../utils/sound_manager.dart';
import '../../utils/support.dart';
import '../../utils/theme.dart';
import '../../widgets/common.dart';
import '../services/service_screen.dart';

// ══════════════════════════════════════════════════════════════
// Booking status — the ONE screen that tracks a booking from
// "searching" to "paid" (web: the "Your Booking" radar page). Driven by
// polling bookings.php?action=get every 4 s while in the foreground.
// ══════════════════════════════════════════════════════════════
class BookingStatusScreen extends StatefulWidget {
  final String bookingId;

  /// Test-only: show this booking (and these radar results) without
  /// calling the API.
  final Map<String, dynamic>? preview;
  final List<Map<String, dynamic>>? previewNearby;
  const BookingStatusScreen({
    super.key,
    required this.bookingId,
    this.preview,
    this.previewNearby,
  });

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
  String _lastStatus = '';
  String _lastPay = '';
  bool _lastReviewReq = false;
  Timer? _poll;
  bool _fetching = false;
  final DateTime _openedAt = DateTime.now();

  // Radar: real nearby providers, widening the search 2 → 5 → 10 → 20 km
  static const _nbRadii = [2, 5, 10, 20];
  static const _nbEvery = Duration(seconds: 7);
  Timer? _nbTimer;
  int _nbStep = 0;
  int _nbRadius = 2;
  bool _nbScanned = false;
  List<Map<String, dynamic>> _nearby = [];

  // Rotating "scanning" messages until the first radar result (web).
  static const _scanMsgs = [
    'Scanning 5 km around you',
    'Contacting nearby professionals',
    'Checking who is available now',
    'Almost there — hold on',
  ];
  int _scanMsg = -1;
  Timer? _scanTimer;

  // Quote window: confirm within quote_expires_in seconds
  DateTime? _quoteDeadline;
  Timer? _tick;

  // Inline review (web: rate card on the completed booking)
  int _stars = 0;
  final _reviewCtrl = TextEditingController();

  late final AnimationController _sweepCtrl;
  Razorpay? _razorpay;
  String _pendingOrderId = '';

  bool get _live => widget.preview == null;
  String get _id => widget.bookingId;
  String get _status => asStr(_b?['status']);

  @override
  void initState() {
    super.initState();
    _sweepCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))
      ..repeat();
    if (!_live) {
      _b = widget.preview;
      _lastStatus = _status;
      _setQuoteDeadline(_b!, tick: false);
      if (widget.previewNearby != null) {
        _nearby = widget.previewNearby!;
        _nbScanned = true;
        _nbRadius = 5;
      }
      return;
    }
    BookingStatusScreen.openBookingId = _id;
    WidgetsBinding.instance.addObserver(this);
    _scanTimer = Timer.periodic(const Duration(milliseconds: 2600), (_) {
      if (mounted && !_nbScanned) setState(() => _scanMsg = (_scanMsg + 1) % _scanMsgs.length);
    });
    _refresh();
    _startPolling();
  }

  @override
  void dispose() {
    if (BookingStatusScreen.openBookingId == _id) BookingStatusScreen.openBookingId = null;
    if (_live) WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _nbTimer?.cancel();
    _tick?.cancel();
    _scanTimer?.cancel();
    _sweepCtrl.dispose();
    _razorpay?.clear();
    _reviewCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _poll?.cancel();
      _poll = null;
      _stopNearby(); // restarted by _refresh() on resume
    } else if (state == AppLifecycleState.resumed) {
      _refresh();
      _startPolling();
    }
  }

  bool get _isTerminal {
    final s = _status;
    if (s == BookingStatus.cancelled) return true;
    if (s == BookingStatus.completed && isPaid(_b ?? {}) && asInt(_b?['rating']) > 0) return true;
    return false;
  }

  void _startPolling() {
    _poll?.cancel();
    if (_isTerminal) return;
    _poll = Timer.periodic(_pollEvery, (_) => _refresh());
  }

  Future<void> _refresh() async {
    if (!_live || _fetching) return;
    _fetching = true;
    try {
      final b = await ApiService.getBooking(_id);
      if (!mounted) return;
      final hadData = _b != null;
      setState(() {
        _b = b;
        _loadError = '';
      });
      if (hadData) _detectChange(b);
      _lastStatus = _status;
      _lastPay = asStr(b['payment_status']);
      _lastReviewReq = asInt(b['review_requested']) == 1;
      _setQuoteDeadline(b);
      if (_status == BookingStatus.searching) {
        _startNearby();
      } else {
        _stopNearby();
      }
      if (_isTerminal) {
        _poll?.cancel();
        _poll = null;
      }
    } on ApiException catch (e) {
      if (mounted && _b == null) setState(() => _loadError = e.message);
    } finally {
      _fetching = false;
    }
  }

  /// Web popNotify(): tell the customer what changed.
  void _detectChange(Map<String, dynamic> b) {
    final st = asStr(b['status']);
    if (st != _lastStatus) {
      HapticFeedback.mediumImpact();
      final who = asStr(b['provider_name']).isEmpty ? 'A provider' : asStr(b['provider_name']);
      switch (st) {
        case BookingStatus.priceQuoted:
          SoundManager.play(AppSound.orderAccepted);
          _toast('Provider Found! $who quoted ₹${asInt(b['quoted_price'])}', success: true);
          break;
        case BookingStatus.negotiationFinal:
          SoundManager.play(AppSound.orderAccepted);
          _toast('Final offer: ₹${asInt(b['final_price'])}');
          break;
        case BookingStatus.confirmed:
          SoundManager.play(AppSound.orderAccepted);
          _toast('Booking confirmed', success: true);
          break;
        case BookingStatus.active:
          _toast('Service Started — your provider has started the work');
          break;
        case BookingStatus.completed:
          _toast('Service Completed — please complete the payment', success: true);
          break;
        case BookingStatus.cancelled:
          SoundManager.play(AppSound.cancelled);
          _toast('Booking Cancelled — this booking was cancelled', error: true);
          break;
        case BookingStatus.searching:
          _toast('Searching for another provider…');
          break;
      }
    }
    if (_lastPay.isNotEmpty && asStr(b['payment_status']) != _lastPay && isPaid(b)) {
      SoundManager.play(AppSound.payment);
      _toast('Payment Confirmed — payment marked as done', success: true);
    }
    if (asInt(b['review_requested']) == 1 && !_lastReviewReq) {
      final who = asStr(b['provider_name']).isEmpty ? 'Your provider' : asStr(b['provider_name']);
      _toast('Review Requested — $who is asking for a review');
    }
  }

  // ── Radar: nearby providers ─────────────────────────────
  void _startNearby() {
    if (_nbTimer != null) return;
    _nbStep = 0;
    _scanNearby();
    _nbTimer = Timer.periodic(_nbEvery, (_) => _scanNearby());
  }

  void _stopNearby() {
    _nbTimer?.cancel();
    _nbTimer = null;
  }

  Future<void> _scanNearby() async {
    final b = _b;
    if (b == null) return;
    final r = _nbRadii[min(_nbStep, _nbRadii.length - 1)];
    try {
      final list = await ApiService.getNearbyProviders(
        svcId: asStr(b['svc_id']),
        radiusKm: r.toDouble(),
        lat: asDouble(b['lat']) ?? 0,
        lng: asDouble(b['lng']) ?? 0,
        city: asStr(b['city']),
      );
      if (!mounted || _nbTimer == null) return;
      setState(() {
        _nearby = list;
        _nbRadius = r;
        _nbScanned = true;
      });
      if (list.isEmpty && _nbStep < _nbRadii.length - 1) _nbStep++;
    } on ApiException catch (e) {
      debugPrint('Nearby providers failed: ${e.message}');
    }
  }

  // ── Quote countdown / live clocks ───────────────────────
  void _setQuoteDeadline(Map<String, dynamic> b, {bool tick = true}) {
    final st = asStr(b['status']);
    final live = (st == BookingStatus.priceQuoted || st == BookingStatus.negotiationFinal) &&
        b['quote_expires_in'] != null;
    _quoteDeadline =
        live ? DateTime.now().add(Duration(seconds: asInt(b['quote_expires_in']))) : null;
    final needTick = tick && (live || st == BookingStatus.active);
    if (needTick) {
      _tick ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else {
      _tick?.cancel();
      _tick = null;
    }
  }

  // ── Actions ─────────────────────────────────────────────
  Future<void> _run(Future<void> Function() action, {String? success}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (success != null) _toast(success, success: true);
      await _refresh();
    } on ApiException catch (e) {
      _toast(e.message.isNotEmpty ? e.message : 'Failed', error: true);
      await _refresh();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String msg, {bool error = false, bool success = false}) {
    if (mounted) showSnack(context, msg, error: error, success: success);
  }

  Future<void> _acceptPrice() => _run(
      () => ApiService.confirmPrice(_id,
          shownPrice: _status == BookingStatus.negotiationFinal
              ? asInt(_b?['final_price'])
              : asInt(_b?['quoted_price'])),
      success: 'Booking confirmed');

  Future<void> _notInterested() async {
    final ok = await _confirmDialog(
      title: 'Not interested?',
      body: 'Decline this provider and search for another?',
      yes: 'Decline',
      danger: true,
    );
    if (ok) await _run(() => ApiService.declineQuote(_id), success: 'Searching for another provider…');
  }

  Future<void> _generateStartOtp() => _run(() => ApiService.generateStartOtp(_id),
      success: 'Start OTP generated — share with provider');

  Future<bool> _confirmDialog(
      {required String title, required String body, required String yes, bool danger = false}) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Back')),
          FilledButton(
            style: danger ? FilledButton.styleFrom(backgroundColor: AppColors.red) : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(yes),
          ),
        ],
      ),
    );
    return r == true;
  }

  Future<void> _negotiate() async {
    final quote = asInt(_b?['quoted_price']);
    final ctrl = TextEditingController();
    String? err;
    final counter = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Counter offer'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Provider quoted ₹$quote. Enter your counter price (₹).'),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(prefixText: '₹ ', labelText: 'Your price', errorText: err),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Back')),
            FilledButton(
              onPressed: () {
                final v = int.tryParse(ctrl.text.trim()) ?? 0;
                if (v < 1) {
                  setS(() => err = 'Invalid price');
                } else if (quote > 0 && v >= quote) {
                  setS(() => err = 'Counter price must be below the quote');
                } else {
                  Navigator.pop(ctx, v);
                }
              },
              child: const Text('Send'),
            ),
          ],
        ),
      ),
    );
    if (counter == null) return;
    await _run(() => ApiService.negotiate(_id, counter),
        success: 'Counter sent — waiting for provider');
  }

  Future<void> _cancel() async {
    String? reason;
    final otherCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Cancel this booking?'),
          contentPadding: const EdgeInsets.fromLTRB(8, 16, 24, 0),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.only(left: 16, bottom: 4),
                child: Text('Reason', style: Theme.of(ctx).textTheme.titleSmall),
              ),
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
                    title: Text(r),
                    onChanged: (v) => setS(() => reason = v),
                  )),
              if (reason == 'Other reason')
                Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: TextField(
                    controller: otherCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(hintText: 'Tell us more…'),
                  ),
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep booking')),
            FilledButton(
              onPressed: reason == null ? null : () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: AppColors.red),
              child: const Text('Cancel booking'),
            ),
          ],
        ),
      ),
    );
    final text = (reason == 'Other reason' && otherCtrl.text.trim().isNotEmpty)
        ? otherCtrl.text.trim()
        : (reason ?? 'Cancelled by customer');
    if (ok != true) return;
    await _run(() => ApiService.cancelBooking(_id, text), success: 'Cancelled');
  }

  Future<void> _submitReview() async {
    if (_stars == 0) {
      _toast('Tap the stars to rate', error: true);
      return;
    }
    await _run(
        () => ApiService.submitReview(
            bookingId: _id, rating: _stars, review: _reviewCtrl.text.trim()),
        success: 'Thanks for your review!');
  }

  void _bookAgain() {
    final svc = asStr(_b?['svc_id']);
    if (svc.isEmpty) return;
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => ServiceScreen(svcId: svc, svcData: {
                  'id': svc,
                  'name': asStr(_b?['svc_name']),
                  'icon': asStr(_b?['svc_icon']),
                })));
  }

  // ── Payment ─────────────────────────────────────────────
  Razorpay get _rzp {
    final r = _razorpay;
    if (r != null) return r;
    final n = Razorpay();
    n.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onPaySuccess);
    n.on(Razorpay.EVENT_PAYMENT_ERROR, _onPayError);
    n.on(Razorpay.EVENT_EXTERNAL_WALLET, _onExternalWallet);
    return _razorpay = n;
  }

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
      final user = Session.user;
      _rzp.open({
        'key': key,
        'amount': amount,
        'currency': asStr(order['currency']).isEmpty ? 'INR' : asStr(order['currency']),
        'name': 'HamaraService',
        'description': 'Booking $_id',
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
      _toast('Could not start payment: ${e.message}', error: true);
    } catch (e) {
      if (mounted) setState(() => _busy = false);
      _toast('Could not open checkout: $e', error: true);
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
        _toast('Payment Successful — thank you!', success: true);
      }
      await _refresh();
    } on ApiException catch (e) {
      _toast(
          '${e.message.isNotEmpty ? e.message : 'Verification failed'} — if money was debited it will be confirmed automatically',
          error: true);
      await _refresh();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _onPayError(PaymentFailureResponse r) {
    if (mounted) setState(() => _busy = false);
    final msg = (r.message ?? '').isNotEmpty ? r.message! : 'Payment cancelled';
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
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Your booking'),
          Text(shortBookingId(_id),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted)),
        ]),
        actions: [
          IconButton(
            tooltip: 'Help',
            onPressed: () => openSupport(context, about: 'Booking $_id.'),
            icon: const Icon(Icons.support_agent_rounded),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _busy ? null : _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: b == null ? _buildLoading() : _buildBody(b),
    );
  }

  Widget _buildLoading() {
    if (_loadError.isNotEmpty) {
      return EmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Could not load this booking',
        message: _loadError,
        actionLabel: 'Retry',
        onAction: _refresh,
      );
    }
    return const SkeletonList(count: 3);
  }

  Widget _buildBody(Map<String, dynamic> b) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          if (_status != BookingStatus.cancelled) ...[
            _Timeline(status: _status),
            const SizedBox(height: 16),
          ],
          ..._stateContent(b),
          const SizedBox(height: 16),
          _detailsCard(b),
          if (BookingStatus.cancellable.contains(_status) && _status != BookingStatus.searching) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _busy ? null : _cancel,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.red,
                side: BorderSide(color: AppColors.red.withOpacity(0.5)),
              ),
              icon: const Icon(Icons.close_rounded),
              label: const Text('Cancel Booking'),
            ),
          ],
          const SizedBox(height: 8),
          Center(
            child: TextButton.icon(
              onPressed: () => openSupport(context, about: 'Booking $_id.'),
              icon: const Icon(Icons.chat_outlined, size: 20),
              label: const Text('Need help with this booking? WhatsApp us'),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  List<Widget> _stateContent(Map<String, dynamic> b) {
    switch (_status) {
      case BookingStatus.searching:
        return _searching(b);
      case BookingStatus.priceQuoted:
      case BookingStatus.negotiationFinal:
        return _offer(b);
      case BookingStatus.negotiating:
        return _negotiating(b);
      case BookingStatus.confirmed:
        return _confirmed(b);
      case BookingStatus.active:
        return _active(b);
      case BookingStatus.completed:
        return _completed(b);
      case BookingStatus.cancelled:
        return _cancelled(b);
      default:
        return [InfoBanner('Status: ${statusLabel(b)}', tone: Tone.neutral)];
    }
  }

  // ── searching ───────────────────────────────────────────
  List<Widget> _searching(Map<String, dynamic> b) {
    final t = Theme.of(context).textTheme;
    final waitingLong = _live && DateTime.now().difference(_openedAt) > _searchPatience;
    final n = _nearby.length;
    final sub = !_nbScanned
        ? (_scanMsg < 0 ? 'Scanning around you' : _scanMsgs[_scanMsg])
        : n > 0
            ? '$n provider${n > 1 ? 's' : ''} available within $_nbRadius km — waiting for a quote'
            : 'Searching within $_nbRadius km…${_nbRadius >= _nbRadii.last ? ' No provider free right now, we keep looking.' : ''}';
    return [
      Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
          child: Column(children: [
            SizedBox(
              width: 200,
              height: 200,
              child: AnimatedBuilder(
                animation: _sweepCtrl,
                builder: (_, __) => CustomPaint(painter: _RadarPainter(_sweepCtrl.value * 2 * pi)),
              ),
            ),
            const SizedBox(height: 20),
            Text('Searching for providers…', style: t.titleLarge),
            const SizedBox(height: 6),
            Text(sub,
                textAlign: TextAlign.center,
                style: t.bodyMedium?.copyWith(
                    color: n > 0 ? AppColors.green : AppColors.muted,
                    fontWeight: n > 0 ? FontWeight.w600 : FontWeight.w400)),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _busy ? null : _cancel,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.red,
                side: BorderSide(color: AppColors.red.withOpacity(0.5)),
                minimumSize: const Size(160, 44),
              ),
              icon: const Icon(Icons.close_rounded),
              label: const Text('Cancel'),
            ),
          ]),
        ),
      ),
      if (n > 0) ...[
        SectionHeader('Providers near you', trailing: 'within $_nbRadius km',
            padding: const EdgeInsets.fromLTRB(4, 20, 4, 8)),
        Card(
          child: Column(children: [
            for (var i = 0; i < min(5, n); i++) ...[
              if (i > 0) const Divider(indent: 72),
              _nearbyTile(_nearby[i]),
            ],
          ]),
        ),
      ],
      if (waitingLong) ...[
        const SizedBox(height: 12),
        const InfoBanner(
          'No provider has responded yet. Your request stays open and we will keep looking — you '
          'will get a notification when a provider sends a price. You can safely leave this screen.',
          icon: Icons.notifications_active_outlined,
          tone: Tone.warning,
        ),
      ],
    ];
  }

  Widget _nearbyTile(Map<String, dynamic> p) {
    final t = Theme.of(context).textTheme;
    final name = asStr(p['name']).isEmpty ? 'Provider' : asStr(p['name']);
    final rating = asDouble(p['rating']) ?? 0;
    final dist = asDouble(p['distance_km']);
    final mn = asInt(p['min_price']);
    final mx = asInt(p['max_price']);
    final price = mn > 0 ? '₹$mn${mx > mn ? '–$mx' : ''}' : '';
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: AppColors.teal,
        foregroundColor: Colors.white,
        child: Text(name.characters.first.toUpperCase()),
      ),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Row(children: [
        const Icon(Icons.star_rounded, size: 16, color: Color(0xFFF5A623)),
        const SizedBox(width: 2),
        Text(rating > 0 ? rating.toStringAsFixed(1) : 'New'),
        if (dist != null) ...[
          const SizedBox(width: 10),
          const Icon(Icons.place_outlined, size: 16, color: AppColors.muted),
          const SizedBox(width: 2),
          Text('${dist.toStringAsFixed(1)} km'),
        ],
      ]),
      trailing: price.isEmpty
          ? null
          : Text(price, style: t.titleSmall?.copyWith(color: AppColors.teal2)),
    );
  }

  // ── price_quoted / negotiation_final ────────────────────
  List<Widget> _offer(Map<String, dynamic> b) {
    final t = Theme.of(context).textTheme;
    final isFinal = _status == BookingStatus.negotiationFinal;
    final price = isFinal
        ? (asInt(b['final_price']) > 0 ? asInt(b['final_price']) : asInt(b['quoted_price']))
        : asInt(b['quoted_price']);
    return [
      Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.brand, width: 1.5),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const Icon(Icons.celebration_rounded, color: AppColors.brand),
              const SizedBox(width: 8),
              Text('Provider Found!', style: t.titleMedium?.copyWith(color: AppColors.brand2)),
            ]),
            const SizedBox(height: 16),
            _providerRow(b, pills: true),
            const SizedBox(height: 16),
            Text(isFinal ? 'Final offer from provider' : 'Quoted price',
                style: t.labelLarge?.copyWith(color: isFinal ? AppColors.brand2 : AppColors.muted)),
            Text('₹$price',
                style: t.displaySmall?.copyWith(color: AppColors.teal2, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
                isFinal
                    ? "This is the provider's final price. Confirm to book, or decline to find another."
                    : 'Confirm to book, send a counter offer, or decline to find another.',
                style: t.bodySmall?.copyWith(color: AppColors.muted)),
            _quoteCountdown(),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _acceptPrice,
              style: FilledButton.styleFrom(backgroundColor: AppColors.green),
              icon: const Icon(Icons.check_rounded),
              label: Text('Confirm Booking · ₹$price'),
            ),
            if (!isFinal) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _busy ? null : _negotiate,
                icon: const Icon(Icons.forum_outlined),
                label: const Text('Counter Offer'),
              ),
            ],
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy ? null : _notInterested,
              style: TextButton.styleFrom(foregroundColor: AppColors.red, minimumSize: const Size(64, 48)),
              child: const Text('Not Interested'),
            ),
          ]),
        ),
      ),
    ];
  }

  Widget _quoteCountdown() {
    final d = _quoteDeadline;
    if (d == null) return const SizedBox.shrink();
    final left = _live
        ? max(0, (d.difference(DateTime.now()).inMilliseconds / 1000).round())
        : asInt(_b?['quote_expires_in']);
    final expired = left <= 0;
    final text = expired
        ? 'Quote expired — finding another provider for you…'
        : 'Confirm within ${left ~/ 60}:${(left % 60).toString().padLeft(2, '0')} — otherwise we find another provider';
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: InfoBanner(text,
          icon: expired ? Icons.hourglass_disabled_rounded : Icons.timer_outlined,
          tone: (expired || left <= 60) ? Tone.danger : Tone.warning),
    );
  }

  // ── negotiating ─────────────────────────────────────────
  List<Widget> _negotiating(Map<String, dynamic> b) {
    final t = Theme.of(context).textTheme;
    return [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            const CircleAvatar(
              radius: 28,
              backgroundColor: AppColors.brandSoft,
              child: Icon(Icons.forum_rounded, color: AppColors.brand, size: 28),
            ),
            const SizedBox(height: 12),
            Text('Counter sent — ₹${asInt(b['counter_price'])}', style: t.titleLarge),
            const SizedBox(height: 4),
            Text('Waiting for provider to respond…',
                style: t.bodyMedium?.copyWith(color: AppColors.muted)),
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      Card(child: Padding(padding: const EdgeInsets.all(16), child: _providerRow(b, pills: true))),
    ];
  }

  // ── confirmed ───────────────────────────────────────────
  // Provider steps: Start trip → I've arrived (start OTP sent) → enters OTP.
  List<Widget> _confirmed(Map<String, dynamic> b) {
    final t = Theme.of(context).textTheme;
    final otp = asStr(b['start_otp']);
    final onTheWay = asStr(b['travel_started_at']).isNotEmpty;
    return [
      if (otp.isNotEmpty)
        _hero(Icons.where_to_vote_rounded, AppColors.green, 'Provider has arrived',
            'Share the Start OTP to begin the work')
      else if (onTheWay)
        _hero(Icons.two_wheeler_rounded, AppColors.teal, 'Provider is on the way',
            'You will get the Start OTP when they reach you')
      else
        _hero(Icons.verified_rounded, AppColors.green, 'Booking Confirmed',
            'We will notify you when the provider starts the trip'),
      const SizedBox(height: 12),
      _providerCard(b),
      const SizedBox(height: 12),
      if (otp.isNotEmpty)
        _OtpCard(
          title: 'Start OTP',
          otp: otp,
          note: 'Give this code to your provider to begin the work',
          color: AppColors.teal,
        )
      else ...[
        InfoBanner(
          onTheWay
              ? 'Your provider is coming. When they arrive, they will send you the Start OTP.'
              : 'Your provider will start the trip soon. You will be notified.',
          icon: onTheWay ? Icons.near_me_rounded : Icons.schedule_rounded,
          tone: Tone.neutral,
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton.icon(
            onPressed: _busy ? null : _generateStartOtp,
            icon: const Icon(Icons.key_rounded, size: 18),
            label: Text('Provider already at your door? Get Start OTP',
                style: t.bodyMedium?.copyWith(color: AppColors.teal, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    ];
  }

  // ── active ──────────────────────────────────────────────
  List<Widget> _active(Map<String, dynamic> b) {
    final otp = asStr(b['completion_otp']);
    final started = asStr(b['started_at']);
    final elapsed = fmtWorkDuration(started);
    return [
      _hero(Icons.handyman_rounded, AppColors.brand, 'Work In Progress', 'Your provider is working on the job'),
      const SizedBox(height: 12),
      _providerCard(b, callable: false),
      if (parseServerTime(started) != null) ...[
        const SizedBox(height: 12),
        InfoBanner('Work started at ${fmtServerTime(started)}${elapsed.isNotEmpty ? ' · $elapsed so far' : ''}',
            icon: Icons.schedule_rounded),
      ],
      const SizedBox(height: 12),
      if (otp.isNotEmpty)
        _OtpCard(
          title: 'Completion OTP',
          otp: otp,
          note: 'Share this ONLY when the work is done to your satisfaction',
          color: AppColors.green,
        )
      else
        const InfoBanner(
          'Work in progress. When your provider finishes, they will request a completion OTP.',
          icon: Icons.construction_rounded,
          tone: Tone.neutral,
        ),
    ];
  }

  // ── completed ───────────────────────────────────────────
  List<Widget> _completed(Map<String, dynamic> b) {
    final t = Theme.of(context).textTheme;
    final amount = bookingPrice(b);
    final paid = isPaid(b);
    final provider = asStr(b['provider_name']);
    final times = _workTimes(b);
    final rating = asInt(b['rating']);
    return [
      _hero(Icons.celebration_rounded, AppColors.green, 'Service Completed!',
          '${provider.isNotEmpty ? '$provider · ' : ''}₹$amount'),
      if (times != null) ...[const SizedBox(height: 12), times],
      const SizedBox(height: 12),
      if (!paid)
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.brand, width: 1.5),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                const Icon(Icons.account_balance_wallet_outlined, color: AppColors.brand),
                const SizedBox(width: 8),
                Text('Payment Pending', style: t.titleMedium),
              ]),
              const SizedBox(height: 4),
              Text('Pay ₹$amount to ${provider.isNotEmpty ? provider : 'your provider'}',
                  style: t.bodyMedium?.copyWith(color: AppColors.muted)),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _busy ? null : _payOnline,
                style: FilledButton.styleFrom(backgroundColor: AppColors.green),
                icon: const Icon(Icons.lock_rounded, size: 20),
                label: Text('Pay ₹$amount Online'),
              ),
              const SizedBox(height: 6),
              Text('UPI · Cards · Netbanking · Wallets',
                  textAlign: TextAlign.center, style: t.bodySmall?.copyWith(color: AppColors.muted)),
              const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider()),
              // Web: cash only when the server says cash_allowed == 1
              asInt(b['cash_allowed']) == 1
                  ? Text(
                      'Paying in cash? Hand the cash to your provider — they will confirm it in their app '
                      'and this booking will update automatically.',
                      textAlign: TextAlign.center,
                      style: t.bodySmall?.copyWith(color: AppColors.ink2))
                  : Text('Online payment only for this booking — cash is not available.',
                      textAlign: TextAlign.center,
                      style: t.bodySmall?.copyWith(color: const Color(0xFF9A4C00))),
            ]),
          ),
        )
      else
        InfoBanner(
            'Payment Done · ₹$amount${asStr(b['payment_method']).isNotEmpty ? ' (${asStr(b['payment_method'])})' : ''}',
            icon: Icons.check_circle_rounded,
            tone: Tone.success),
      if (paid) ...[
        const SizedBox(height: 12),
        rating == 0
            ? _rateCard(b)
            : InfoBanner('You rated this $rating/5 — thank you!',
                icon: Icons.star_rounded, tone: Tone.neutral),
      ],
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: _bookAgain,
        icon: const Icon(Icons.replay_rounded),
        label: const Text('Book Again'),
      ),
    ];
  }

  Widget _rateCard(Map<String, dynamic> b) {
    final t = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (asInt(b['review_requested']) == 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('Your provider requested a review',
                  textAlign: TextAlign.center,
                  style: t.labelLarge?.copyWith(color: AppColors.brand2)),
            ),
          Text('Rate your experience', textAlign: TextAlign.center, style: t.titleMedium),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 1; i <= 5; i++)
              IconButton(
                tooltip: '$i star${i > 1 ? 's' : ''}',
                iconSize: 36,
                onPressed: () {
                  HapticFeedback.selectionClick();
                  setState(() => _stars = i);
                },
                icon: Icon(i <= _stars ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: i <= _stars ? const Color(0xFFF5A623) : AppColors.line),
              ),
          ]),
          const SizedBox(height: 8),
          TextField(
            controller: _reviewCtrl,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(hintText: 'Write a short review (optional)'),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy ? null : _submitReview,
            child: const Text('Submit Review'),
          ),
        ]),
      ),
    );
  }

  // ── cancelled ───────────────────────────────────────────
  List<Widget> _cancelled(Map<String, dynamic> b) {
    final reason = asStr(b['cancel_reason']);
    final by = asStr(b['cancelled_by']);
    final byAdmin = by == 'admin';
    return [
      _hero(Icons.cancel_rounded, AppColors.red, 'Booking Cancelled',
          byAdmin
              ? 'This booking was cancelled by HamaraService.'
              : 'This booking was cancelled${by.isNotEmpty ? ' by $by' : ''}.${reason.isNotEmpty ? '\nReason: $reason' : ''}'),
      if (byAdmin && reason.isNotEmpty) ...[
        const SizedBox(height: 12),
        InfoBanner('Message from HamaraService: $reason', icon: Icons.support_agent_rounded),
      ],
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: _bookAgain,
        icon: const Icon(Icons.replay_rounded),
        label: const Text('Book Again'),
      ),
    ];
  }

  // ── Building blocks ─────────────────────────────────────
  Widget _hero(IconData icon, Color color, String title, String sub) {
    final t = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        child: Column(children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: color.withOpacity(0.12),
            child: Icon(icon, color: color, size: 32),
          ),
          const SizedBox(height: 12),
          Text(title, textAlign: TextAlign.center, style: t.titleLarge),
          const SizedBox(height: 4),
          Text(sub, textAlign: TextAlign.center, style: t.bodyMedium?.copyWith(color: AppColors.muted)),
        ]),
      ),
    );
  }

  Widget _avatar(Map<String, dynamic> b, double r) {
    final name = asStr(b['provider_name']).isEmpty ? 'P' : asStr(b['provider_name']);
    final photo = asStr(b['provider_photo']);
    final url = photo.isEmpty
        ? null
        : (photo.startsWith('http') ? photo : 'https://hamaraservice.com${Uri.encodeFull(photo)}');
    return CircleAvatar(
      radius: r,
      backgroundColor: AppColors.teal,
      foregroundColor: Colors.white,
      foregroundImage: url == null ? null : NetworkImage(url),
      child: Text(name.characters.first.toUpperCase(),
          style: TextStyle(fontSize: r * 0.8, fontWeight: FontWeight.w700)),
    );
  }

  Widget _providerRow(Map<String, dynamic> b, {bool pills = false}) {
    final t = Theme.of(context).textTheme;
    final name = asStr(b['provider_name']).isEmpty ? 'Provider' : asStr(b['provider_name']);
    final rating = asDouble(b['provider_rating']) ?? 0;
    final reviews = asInt(b['provider_reviews']);
    final dist = asDouble(b['distance_km']);
    Widget pill(IconData i, String s, [Color c = AppColors.teal2]) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: AppColors.tealSoft, borderRadius: BorderRadius.circular(100)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(i, size: 14, color: c),
            const SizedBox(width: 4),
            Text(s, style: t.labelMedium?.copyWith(color: AppColors.teal2, fontWeight: FontWeight.w700)),
          ]),
        );
    return Row(children: [
      _avatar(b, 26),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleMedium),
          const SizedBox(height: 4),
          Wrap(spacing: 6, runSpacing: 4, children: [
            if (dist != null) pill(Icons.place_outlined, '$dist km away'),
            pill(Icons.star_rounded,
                rating > 0 ? '${rating.toStringAsFixed(1)}${reviews > 0 ? ' ($reviews)' : ''}' : 'New',
                const Color(0xFFF5A623)),
          ]),
        ]),
      ),
    ]);
  }

  Widget _providerCard(Map<String, dynamic> b, {bool callable = true}) {
    final t = Theme.of(context).textTheme;
    final name = asStr(b['provider_name']).isEmpty ? 'Provider' : asStr(b['provider_name']);
    // Provider's number only after the customer accepted the price, so the
    // job can't be taken off the platform during negotiation.
    final phone = const ['confirmed', 'active', 'completed'].contains(_status)
        ? asStr(b['provider_phone'])
        : '';
    final price = bookingPrice(b);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            _avatar(b, 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleMedium),
                Text(asStr(b['svc_name']),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodySmall?.copyWith(color: AppColors.muted)),
              ]),
            ),
            if (price > 0)
              Text('₹$price', style: t.titleLarge?.copyWith(color: AppColors.teal2, fontWeight: FontWeight.w700)),
          ]),
          if (phone.isNotEmpty || !callable) const SizedBox(height: 12),
          if (!callable)
            FilledButton.icon(
              onPressed: null,
              icon: const Icon(Icons.phone_disabled_rounded),
              label: const Text('Calling off — provider is working'),
            )
          else if (phone.isNotEmpty)
            FilledButton.tonalIcon(
              onPressed: () async {
                HapticFeedback.mediumImpact();
                bool ok = false;
                try {
                  ok = await launchUrl(Uri.parse('tel:$phone'));
                } catch (_) {}
                if (!ok) _toast('Could not open the dialer', error: true);
              },
              icon: const Icon(Icons.call_rounded),
              label: Text('Call Provider · $phone'),
            ),
        ]),
      ),
    );
  }

  /// Work started / closed / duration, or null when not started.
  Widget? _workTimes(Map<String, dynamic> b) {
    final s = asStr(b['started_at']);
    final c = asStr(b['completed_at']);
    final hasS = parseServerTime(s) != null;
    final hasC = parseServerTime(c) != null;
    if (!hasS && !hasC) return null;
    final dur = (hasS && hasC) ? fmtWorkDuration(s, c) : '';
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(children: [
          if (hasS) DetailRow(Icons.play_circle_outline_rounded, fmtServerTime(s), label: 'Work started'),
          if (hasC) DetailRow(Icons.stop_circle_outlined, fmtServerTime(c), label: 'Work closed'),
          if (dur.isNotEmpty) DetailRow(Icons.timer_outlined, dur, label: 'Duration'),
        ]),
      ),
    );
  }

  Widget _detailsCard(Map<String, dynamic> b) {
    final t = Theme.of(context).textTheme;
    final landmark = asStr(b['landmark']);
    final notes = asStr(b['notes']);
    final created = asStr(b['created_at']);
    final contact = '${asStr(b['contact_name'])} ${asStr(b['contact_phone'])}'.trim();
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            ServiceImage(asStr(b['svc_id']), size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(asStr(b['svc_name']), style: t.titleMedium),
                Text(asStr(b['id']), style: t.bodySmall?.copyWith(color: AppColors.muted)),
              ]),
            ),
            StatusChip(b),
          ]),
          const SizedBox(height: 8),
          const Divider(),
          const SizedBox(height: 4),
          DetailRow(Icons.event_rounded, slotLabel(b), label: 'Time'),
          DetailRow(Icons.place_outlined,
              '${asStr(b['address'])}${landmark.isNotEmpty ? ' (near $landmark)' : ''}',
              label: 'Address'),
          if (contact.isNotEmpty) DetailRow(Icons.person_outline_rounded, contact, label: 'Contact'),
          if (notes.isNotEmpty) DetailRow(Icons.checklist_rounded, notes, label: 'Tasks'),
          if (_status != BookingStatus.completed) ...[
            if (parseServerTime(b['started_at']) != null)
              DetailRow(Icons.play_circle_outline_rounded, fmtServerTime(b['started_at']),
                  label: 'Work started'),
          ],
          if (created.isNotEmpty)
            DetailRow(Icons.history_rounded, created.length >= 16 ? created.substring(0, 16) : created,
                label: 'Booked on'),
        ]),
      ),
    );
  }
}

/// Booked → Provider → Confirmed → In Progress → Done (web renderTimeline).
class _Timeline extends StatelessWidget {
  final String status;
  const _Timeline({required this.status});

  static const _steps = [
    ('Booked', Icons.edit_note_rounded),
    ('Provider', Icons.engineering_outlined),
    ('Confirmed', Icons.verified_outlined),
    ('In Progress', Icons.handyman_outlined),
    ('Done', Icons.celebration_outlined),
  ];

  int get _idx {
    switch (status) {
      case BookingStatus.priceQuoted:
      case BookingStatus.negotiating:
      case BookingStatus.negotiationFinal:
        return 1;
      case BookingStatus.confirmed:
        return 2;
      case BookingStatus.active:
        return 3;
      case BookingStatus.completed:
        return 4;
      default:
        return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final idx = _idx;
    const grey = Color(0xFFE8EEF0);
    Widget line(bool on, bool show) => Expanded(
          child: Container(height: 3, color: show ? (on ? AppColors.green : grey) : Colors.transparent),
        );
    final steps = <Widget>[];
    for (var i = 0; i < _steps.length; i++) {
      final done = i < idx || (i == idx && i == _steps.length - 1);
      final cur = i == idx;
      steps.add(Expanded(
        child: Column(children: [
          Row(children: [
            line(i <= idx, i > 0),
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done ? AppColors.green : (cur ? AppColors.teal : grey),
              ),
              child: Icon(done ? Icons.check_rounded : _steps[i].$2,
                  size: 18, color: done || cur ? Colors.white : AppColors.muted),
            ),
            line(i < idx, i < _steps.length - 1),
          ]),
          const SizedBox(height: 6),
          Text(_steps[i].$1,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: t.labelSmall?.copyWith(
                  color: done ? AppColors.green : (cur ? AppColors.teal2 : AppColors.muted),
                  fontWeight: cur || done ? FontWeight.w700 : FontWeight.w500)),
        ]),
      ));
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: steps),
      ),
    );
  }
}

/// Big OTP display: one box per digit.
class _OtpCard extends StatelessWidget {
  final String title;
  final String otp;
  final String note;
  final Color color;
  const _OtpCard({required this.title, required this.otp, required this.note, required this.color});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: color, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.key_rounded, color: color, size: 20),
            const SizedBox(width: 8),
            Flexible(
              child: Text(title.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: t.labelLarge?.copyWith(color: color, letterSpacing: 0.6, fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 16),
          Semantics(
            label: 'OTP ${otp.split('').join(' ')}',
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final d in otp.split(''))
                  Container(
                    width: 52,
                    height: 64,
                    margin: const EdgeInsets.symmetric(horizontal: 5),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: color.withOpacity(0.5)),
                    ),
                    child: Text(d,
                        style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(note, textAlign: TextAlign.center, style: t.bodyMedium?.copyWith(color: AppColors.ink2)),
        ]),
      ),
    );
  }
}

/// Provider scanner for the "searching" state (web: .scanner).
class _RadarPainter extends CustomPainter {
  final double sweep;
  _RadarPainter(this.sweep);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = const RadialGradient(
            colors: [Color(0xFF0D3D47), Color(0xFF134F5C), Color(0xFF0A3540)],
            stops: [0, 0.7, 1],
          ).createShader(rect));
    const cyan = Color(0xFF78DCE8);
    for (final f in [0.3, 0.6, 0.9]) {
      canvas.drawCircle(
          c,
          r * f,
          Paint()
            ..color = cyan.withOpacity(0.35)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2);
    }
    canvas.drawLine(Offset(c.dx - r, c.dy), Offset(c.dx + r, c.dy),
        Paint()..color = cyan.withOpacity(0.12));
    canvas.drawLine(Offset(c.dx, c.dy - r), Offset(c.dx, c.dy + r),
        Paint()..color = cyan.withOpacity(0.12));
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(sweep);
    canvas.translate(-c.dx, -c.dy);
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = SweepGradient(
            startAngle: 0,
            endAngle: pi / 2,
            colors: [
              const Color(0xFF40E0D0).withOpacity(0.55),
              const Color(0xFF40E0D0).withOpacity(0.0),
            ],
            transform: const GradientRotation(-pi / 2),
          ).createShader(rect));
    canvas.restore();
    canvas.drawCircle(c, 7, Paint()..color = const Color(0xFF40E0D0));
    canvas.drawCircle(
        c,
        14,
        Paint()
          ..color = const Color(0xFF40E0D0).withOpacity(0.25)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
  }

  @override
  bool shouldRepaint(_RadarPainter old) => old.sweep != sweep;
}
