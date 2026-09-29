import '../../services/api_service.dart';
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../utils/theme.dart';
import 'booking_confirmed_screen.dart';

class RadarScreen extends StatefulWidget {
  final String bookingId;
  final Map<String, dynamic> service;
  final DateTime date;
  final String timeSlot;
  final String address;
  final int price;
  final double? lat;
  final double? lng;

  const RadarScreen({
    super.key,
    required this.bookingId,
    required this.service,
    required this.date,
    required this.timeSlot,
    required this.address,
    required this.price,
    this.lat,
    this.lng,
  });

  @override
  State<RadarScreen> createState() => _RadarScreenState();
}

class _RadarScreenState extends State<RadarScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final List<int> _ranges = [1, 3, 5, 10, 15, 20];
  int _currentRangeIdx = 0;
  bool _radarActive = true;
  bool _navigating = false;
  Timer? _pollTimer;
  Timer? _rangeTimer;
  final List<Map<String, dynamic>> _logs = [];
  int _providersFound = 0;
  String _lastStatus = '';

  late AnimationController _sweepCtrl;
  late AnimationController _pulseCtrl;
  late Animation<double> _sweepAnim;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sweepCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2500))
      ..repeat();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat(reverse: true);
    _sweepAnim =
        Tween(begin: 0.0, end: 2 * pi).animate(_sweepCtrl);
    _pulseAnim = Tween(begin: 0.8, end: 1.0).animate(_pulseCtrl);
    _startRadarSound();
    _startRange(0);
  }

  Future<void> _startRadarSound() async {
    // Haptic pulse instead of sound
    HapticFeedback.lightImpact();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sweepCtrl.dispose();
    _pulseCtrl.dispose();
    _pollTimer?.cancel();
    _rangeTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // inactive = phone call, notification pull-down — DO NOT stop radar
    // Only stop on paused (app fully backgrounded)
    if (state == AppLifecycleState.paused) {
      if (_radarActive) {
        _radarActive = false;
        _pollTimer?.cancel();
        _rangeTimer?.cancel();
        // Booking stays active in MySQL when app backgrounds
      }
    } else if (state == AppLifecycleState.resumed) {
      // Resume radar if it was active before
      if (!_radarActive && !_navigating) {
        _radarActive = true;
        _startRange(_currentRangeIdx);
      }
    }
  }

  void _addLog(String emoji, String message, {String type = ''}) {
    if (!mounted) return;
    setState(() {
      _logs.insert(0, {
        'emoji': emoji,
        'message': message,
        'type': type
      });
      if (_logs.length > 10) _logs.removeLast();
    });
  }

  Future<void> _startRange(int idx) async {
    if (!_radarActive || !mounted) return;
    if (idx >= _ranges.length) {
      _giveUp();
      return;
    }
    _pollTimer?.cancel();
    _rangeTimer?.cancel();
    setState(() {
      _currentRangeIdx = idx;
      _providersFound = 0;
    });
    final km = _ranges[idx];
    if (idx == 0) {
      _addLog('📡', 'Searching for providers within $km km...', type: 'info');
    } else {
      _addLog('↔️', 'Expanding to $km km radius...', type: 'warn');
    }
    try {
      // Range update tracked locally — booking status stays 'active' in MySQL
    } catch (e) {}
    _countProviders(km);
    _pollTimer =
        Timer.periodic(const Duration(seconds: 3), (t) async {
      if (!_radarActive || !mounted || _navigating) {
        t.cancel();
        return;
      }
      await _pollOnce(t);
    });
    _rangeTimer = Timer(const Duration(seconds: 20), () {
      if (!_radarActive || !mounted || _navigating) return;
      _pollTimer?.cancel();
      _startRange(idx + 1);
    });
  }

  static int _num(dynamic v) => num.tryParse(v?.toString() ?? '')?.toInt() ?? 0;

  /// One status poll of the booking (MySQL snake_case fields).
  Future<void> _pollOnce(Timer? t) async {
    try {
      final bkData = await ApiService.getBooking(widget.bookingId);
      if (bkData == null || !mounted || _navigating) return;
      final bkStatus = bkData['status']?.toString() ?? '';
      _lastStatus = bkStatus;
      final hasProvider = (bkData['provider_id']?.toString() ?? '').isNotEmpty;
      final pn = (bkData['provider_name']?.toString() ?? '').isNotEmpty
          ? bkData['provider_name'].toString() : 'Provider';
      if (bkStatus == 'price_quoted' && hasProvider) {
        t?.cancel(); _pollTimer?.cancel(); _rangeTimer?.cancel();
        _showPriceQuote(_num(bkData['quoted_price']), pn, bkData);
      } else if (bkStatus == 'negotiation_final' && _num(bkData['final_price']) > 0) {
        t?.cancel(); _pollTimer?.cancel(); _rangeTimer?.cancel();
        _showFinalOffer(_num(bkData['final_price']), pn);
      } else if ((bkStatus == 'confirmed' || bkStatus == 'active') && hasProvider) {
        t?.cancel(); _pollTimer?.cancel(); _rangeTimer?.cancel();
        _providerAccepted();
      } else if (bkStatus == 'cancelled' || bkStatus == 'expired') {
        t?.cancel(); _pollTimer?.cancel(); _rangeTimer?.cancel();
        final reason = bkData['cancel_reason']?.toString() ?? '';
        final expired = bkStatus == 'expired' || reason == 'expired';
        _endSearch(expired
            ? 'Your search expired before a provider accepted. Please book again.'
            : (bkData['cancelled_by']?.toString() == 'admin'
                ? 'This booking was cancelled by HamaraService support.'
                : 'This booking was cancelled.'));
      }
    } catch (_) {}
  }

  /// All radius steps exhausted. If the booking is still unclaimed, cancel
  /// it (reason 'no_provider'); if a provider is mid-negotiation keep polling.
  Future<void> _giveUp() async {
    if (_navigating || !mounted) return;
    _pollTimer?.cancel();
    _rangeTimer?.cancel();
    await _pollOnce(null);
    if (_navigating || !mounted) return;
    if (_lastStatus.isNotEmpty && _lastStatus != 'searching') {
      // e.g. 'negotiating' — wait for the provider's response.
      _pollTimer = Timer.periodic(const Duration(seconds: 3), (t) async {
        if (!mounted || _navigating) { t.cancel(); return; }
        await _pollOnce(t);
      });
      return;
    }
    _addLog('😔', 'No provider accepted within 20 km', type: 'warn');
    await ApiService.cancelBooking(widget.bookingId, reason: 'no_provider');
    _endSearch('No providers are available near you right now. '
        'Your booking was cancelled — please try again in a little while.');
  }

  /// Stop the radar and tell the customer why, then leave the screen.
  Future<void> _endSearch(String message) async {
    if (_navigating || !mounted) return;
    _navigating = true;
    _pollTimer?.cancel();
    _rangeTimer?.cancel();
    setState(() => _radarActive = false);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Search ended', style: TextStyle(fontWeight: FontWeight.w800)),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK', style: TextStyle(color: AppColors.teal, fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (mounted) Navigator.pop(context);
  }

  Future<void> _countProviders(int km) async {
    try {
      final svcId = widget.service['id']?.toString() ?? '';
      // Derive city from the last part of the address for GPS-less fallback
      final addrParts = widget.address.split(',');
      final derivedCity = addrParts.isNotEmpty ? addrParts.last.trim() : '';
      final nearby = await ApiService.getNearbyProviders(
        lat: widget.lat ?? 0.0, lng: widget.lng ?? 0.0,
        svcId: svcId.isNotEmpty ? svcId : null,
        city: derivedCity.isNotEmpty ? derivedCity : null,
        radius: km.toDouble(),
      );
      if (mounted) setState(() => _providersFound = nearby.length);
    } catch (_) {}
  }
  // Show quoted price to customer — Accept / Negotiate / Search Another
  void _showPriceQuote(int quotedPrice, String providerName, Map<String,dynamic> bookingData) {
    if (_navigating || !mounted) return;
    _pollTimer?.cancel();
    _rangeTimer?.cancel();
    final counterCtrl = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(width:36, height:36,
                decoration: BoxDecoration(color:AppColors.tealSoft, shape:BoxShape.circle),
                child: const Icon(Icons.handyman_rounded, color:AppColors.teal, size:20)),
              const SizedBox(width:10),
              Expanded(child: Text(providerName,
                style: const TextStyle(fontSize:16, fontWeight:FontWeight.w800))),
            ]),
            const SizedBox(height:4),
            const Text('Provider accepted your booking',
              style: TextStyle(fontSize:12, color:AppColors.muted)),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.tealSoft,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.teal.withOpacity(0.3))),
              child: Column(children: [
                const Text('QUOTED PRICE', style: TextStyle(fontSize:11,
                  fontWeight:FontWeight.w800, color:AppColors.muted, letterSpacing:.5)),
                const SizedBox(height:6),
                Text('₹$quotedPrice',
                  style: const TextStyle(fontSize:36, fontWeight:FontWeight.w900,
                    color:AppColors.teal)),
                Text('for ${widget.service['name'] ?? 'service'}',
                  style: const TextStyle(fontSize:12, color:AppColors.muted)),
              ])),
            const SizedBox(height:14),
            // Counter offer input
            TextField(
              controller: counterCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Your counter offer (optional)',
                prefixText: '₹ ',
                hintText: 'Enter your price',
                helperText: 'Leave empty to accept or negotiate',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
            ),
          ]),
          actions: [
            // Search another provider
            TextButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _searchAnother(bookingData);
              },
              icon: const Icon(Icons.search_rounded, size:16, color:AppColors.muted),
              label: const Text('Search Another',
                style: TextStyle(color:AppColors.muted, fontSize:12))),
            // Negotiate — always visible, sends counter if filled
            TextButton(
              onPressed: () async {
                final counter = int.tryParse(counterCtrl.text.trim()) ?? 0;
                Navigator.pop(ctx);
                await _sendNegotiation(counter > 0 ? counter : null, bookingData);
              },
              child: const Text('Negotiate 💬',
                style: TextStyle(color:AppColors.brand, fontWeight:FontWeight.w700))),
            // Accept
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await _confirmPrice(quotedPrice, bookingData);
              },
              style: ElevatedButton.styleFrom(backgroundColor:AppColors.teal),
              child: Text('Accept ₹$quotedPrice',
                style: const TextStyle(color:Colors.white, fontWeight:FontWeight.w700))),
          ],
        )),
    );
  }

  // Customer sends counter offer to provider
  Future<void> _sendNegotiation(int? counterPrice, Map<String,dynamic> bookingData) async {
    try {
      // MySQL API handles negotiation + FCM notification to provider
      await ApiService.negotiateBooking(widget.bookingId, counterPrice ?? 0);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Negotiation sent. Waiting for provider response...'),
          backgroundColor: AppColors.teal));
        setState(() { _radarActive = true; });
        _startRange(0);
      }
    } catch (e) {
      if (mounted) toast('Error: $e');
    }
  }

  // Customer accepts quoted price — confirmed
  Future<void> _confirmPrice(int price, Map<String,dynamic> bookingData) async {
    try {
      // MySQL API confirms price + sends FCM to provider + generates OTP
      final res = await ApiService.confirmPrice(widget.bookingId, price);
      if (res == null) {
        if (mounted) toast('Could not confirm the price. Please try again.');
        await _pollOnce(null);
        return;
      }
      _providerAccepted();
    } catch (e) {
      if (mounted) toast('Error: $e');
    }
  }

  // Show provider's final offer
  void _showFinalOffer(int finalPrice, String providerName) {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Final Offer from Provider',
          style: TextStyle(fontSize:17, fontWeight:FontWeight.w800)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('$providerName has sent their final offer:',
            style: const TextStyle(fontSize:13, color:AppColors.muted)),
          const SizedBox(height:14),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.brand.withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.brand.withOpacity(0.3))),
            child: Column(children: [
              const Text('FINAL PRICE', style: TextStyle(fontSize:11,
                fontWeight:FontWeight.w800, color:AppColors.muted, letterSpacing:.5)),
              const SizedBox(height:6),
              Text('₹$finalPrice',
                style: const TextStyle(fontSize:36, fontWeight:FontWeight.w900,
                  color:AppColors.brand)),
              const Text('This is their final price — no further negotiation',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize:11, color:AppColors.muted)),
            ])),
        ]),
        actions: [
          TextButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _searchAnother(null);
            },
            icon: const Icon(Icons.search_rounded, size:16, color:AppColors.muted),
            label: const Text('Search Another',
              style: TextStyle(color:AppColors.muted, fontSize:12))),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _confirmPrice(finalPrice, {});
            },
            style: ElevatedButton.styleFrom(backgroundColor:AppColors.teal),
            child: Text('Accept ₹$finalPrice',
              style: const TextStyle(color:Colors.white, fontWeight:FontWeight.w700))),
        ],
      ),
    );
  }

  // Release current provider and search again
  Future<void> _searchAnother(Map<String,dynamic>? currentBooking) async {
    try {
      await ApiService.searchAnother(widget.bookingId);
      if (mounted) {
        setState(() { _radarActive = true; _navigating = false; });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('🔍 Searching for another provider...'),
          backgroundColor: AppColors.teal));
        _startRange(0);
      }
    } catch (e) {
      if (mounted) toast('Error: $e');
    }
  }

  void toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _providerAccepted() async {
    if (_navigating || !mounted) return;
    _navigating = true;
        setState(() => _radarActive = false);
    _addLog('✅', 'Provider found and confirmed!', type: 'success');
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    Navigator.pushReplacement(
        context,
        MaterialPageRoute(
            builder: (_) => BookingConfirmedScreen(
                bookingId: widget.bookingId,
                service: widget.service,
                date: widget.date,
                timeSlot: widget.timeSlot,
                address: widget.address,
                price: widget.price)));
  }

  void _cancelSearch() async {
        setState(() => _radarActive = false);
    _pollTimer?.cancel();
    _rangeTimer?.cancel();
    try {
      // Cancel booking in MySQL
      await ApiService.cancelBooking(widget.bookingId, reason: 'customer_cancelled_search');
      await Future.delayed(const Duration(milliseconds: 500));
    } catch (e) {}
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final km = _ranges[_currentRangeIdx];
    final progress = _currentRangeIdx / (_ranges.length - 1);
    return Scaffold(
      backgroundColor: const Color(0xFF080C14),
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              GestureDetector(
                onTap: _cancelSearch,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      shape: BoxShape.circle),
                  child: const Icon(Icons.close,
                      color: Colors.white, size: 18),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                const Text('Searching for Providers',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
                Text(
                    _radarActive
                        ? 'Range: $km km'
                        : 'Search complete',
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.white
                            .withOpacity(0.5))),
              ])),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(children: [
              Row(
                  mainAxisAlignment:
                      MainAxisAlignment.spaceBetween,
                  children: [
                Text('1 km',
                    style: TextStyle(
                        fontSize: 10,
                        color: Colors.white.withOpacity(0.4))),
                Text('20 km',
                    style: TextStyle(
                        fontSize: 10,
                        color: Colors.white.withOpacity(0.4))),
              ]),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor:
                      Colors.white.withOpacity(0.1),
                  valueColor: const AlwaysStoppedAnimation(
                      Color(0xFF00FF88)),
                  minHeight: 6,
                ),
              ),
            ]),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: 220,
            height: 220,
            child: AnimatedBuilder(
              animation: _sweepCtrl,
              builder: (_, __) => CustomPaint(
                painter: _RadarPainter(
                    _sweepAnim.value, _pulseAnim.value),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text('$km km',
              style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: Colors.white)),
          Text('Searching within $km km of your location',
              style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withOpacity(0.45))),
          if (_providersFound > 0) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.green.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: AppColors.green.withOpacity(0.3)),
              ),
              child: Text(
                  '$_providersFound provider${_providersFound == 1 ? '' : 's'} found — waiting for acceptance',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.green)),
            ),
          ],
          const SizedBox(height: 16),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: _logs.length,
              itemBuilder: (_, i) {
                final log = _logs[i];
                final type = log['type'] as String;
                final color = type == 'success'
                    ? AppColors.green
                    : type == 'warn'
                        ? AppColors.yellow
                        : Colors.white.withOpacity(0.6);
                final emoji = type == 'success' ? '✅' : type == 'warn' ? '↔️' : '📡';
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color:
                            Colors.white.withOpacity(0.1)),
                  ),
                  child: Row(children: [
                    Text(emoji,
                        style:
                            const TextStyle(fontSize: 16)),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text(
                            log['message'] as String,
                            style: TextStyle(
                                fontSize: 13,
                                color: color,
                                fontWeight:
                                    FontWeight.w500))),
                  ]),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: GestureDetector(
              onTap: _cancelSearch,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 32, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(
                      color: Colors.white.withOpacity(0.18)),
                ),
                child: Text('Cancel Search',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.65),
                        fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  final double sweep;
  final double pulse;
  _RadarPainter(this.sweep, this.pulse);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final maxR = size.width / 2;
    for (int i = 1; i <= 5; i++) {
      canvas.drawCircle(
          Offset(cx, cy),
          maxR * i / 5,
          Paint()
            ..color = const Color(0xFF00FF88).withOpacity(0.06)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1);
    }
    final linePaint = Paint()
      ..color = const Color(0xFF00FF88).withOpacity(0.07)
      ..strokeWidth = 1;
    canvas.drawLine(
        Offset(cx, 0), Offset(cx, size.height), linePaint);
    canvas.drawLine(
        Offset(0, cy), Offset(size.width, cy), linePaint);
    canvas.drawCircle(
        Offset(cx, cy),
        maxR,
        Paint()
          ..shader = SweepGradient(
            startAngle: sweep - 0.6,
            endAngle: sweep,
            colors: [
              Colors.transparent,
              const Color(0xFF00FF88).withOpacity(0.15)
            ],
          ).createShader(Rect.fromCircle(
              center: Offset(cx, cy), radius: maxR))
          ..style = PaintingStyle.fill);
    canvas.drawLine(
        Offset(cx, cy),
        Offset(cx + maxR * cos(sweep - pi / 2),
            cy + maxR * sin(sweep - pi / 2)),
        Paint()
          ..color = const Color(0xFF00FF88).withOpacity(0.6)
          ..strokeWidth = 2);
    canvas.drawCircle(
        Offset(cx, cy), 6, Paint()..color = AppColors.teal);
    canvas.drawCircle(
        Offset(cx, cy),
        10,
        Paint()
          ..color = AppColors.teal.withOpacity(0.4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);
  }

  @override
  bool shouldRepaint(_RadarPainter old) =>
      old.sweep != sweep;
}