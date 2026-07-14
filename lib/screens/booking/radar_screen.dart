import 'dart:convert';
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';
import 'package:firebase_database/firebase_database.dart';
import '../../utils/theme.dart';
import 'booking_confirmed_screen.dart';
import 'booking_pending_screen.dart';

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
        // Make booking pending when app goes to background
        FirebaseDatabase.instance
            .ref('active_bookings/${widget.bookingId}')
            .update({
          'status': 'pending',
          'pendingAt': DateTime.now().toIso8601String(),
        });
        FirebaseDatabase.instance
            .ref('bookings/${widget.bookingId}')
            .update({
          'status': 'pending',
          'pendingAt': DateTime.now().toIso8601String(),
        });
      }
    } else if (state == AppLifecycleState.resumed) {
      // Resume radar if it was active before
      if (!_radarActive && !_navigating) {
        _radarActive = true;
        _startRange(_currentRangeIdx);
      }
    }
  }

  double _haversine(
      double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLng = (lng2 - lng1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) *
            cos(lat2 * pi / 180) *
            sin(dLng / 2) *
            sin(dLng / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
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
      _bookingPending();
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
      try {
        final bkData = await ApiService.getBooking(widget.bookingId);
        if (bkData == null) return;
        final bkStatus = bkData['status']?.toString() ?? '';
        if ((bkStatus == "price_quoted") && bkData["acceptedBy"] != null && !_navigating) {
          t.cancel(); _rangeTimer?.cancel();
          final q = (bkData["quotedPrice"] as num?)?.toInt() ?? 0;
          final pn = (bkData["acceptedBy"] is Map) ? (bkData["acceptedBy"] as Map)["name"]?.toString() ?? "Provider" : "Provider";
          if (mounted) _showPriceQuote(q, pn, bkData);
        } else if (bkStatus == "negotiation_final" && bkData["finalPrice"] != null && !_navigating) {
          t.cancel(); _rangeTimer?.cancel();
          final fp = (bkData["finalPrice"] as num?)?.toInt() ?? 0;
          final pn = (bkData["acceptedBy"] is Map) ? (bkData["acceptedBy"] as Map)["name"]?.toString() ?? "Provider" : "Provider";
          if (mounted) _showFinalOffer(fp, pn);
        } else if ((bkStatus == "confirmed" || bkStatus == "accepted") && bkData["acceptedBy"] != null && !_navigating) {
          t.cancel(); _rangeTimer?.cancel(); _providerAccepted();
        }
      } catch (e) {}
    });
    _rangeTimer = Timer(const Duration(seconds: 20), () {
      if (!_radarActive || !mounted || _navigating) return;
      _pollTimer?.cancel();
      _startRange(idx + 1);
    });
  }

  Future<void> _countProviders(int km) async {
    try {
      final snap =
          await FirebaseDatabase.instance.ref('providers').get();
      if (!snap.exists) return;
      final all =
          Map<String, dynamic>.from(snap.value as Map);
      final reqSvc =
          (widget.service['name'] as String).toLowerCase();
      int count = 0;
      for (final v in all.values) {
        final p = Map<String, dynamic>.from(v as Map);
        if (p['available'] != true) continue;
        if (p['status'] != 'approved') continue;
        final pLat = (p['lat'] as num?)?.toDouble();
        final pLng = (p['lng'] as num?)?.toDouble();
        if (pLat == null || pLng == null) continue;
        if (widget.lat != null && widget.lng != null) {
          if (_haversine(
                  widget.lat!, widget.lng!, pLat, pLng) >
              km) continue;
        }
        final services = p['services'];
        if (services == null) continue;
        final svcList = services is List
            ? services
            : (services as Map).values.toList();
        final hasService = svcList.any((s) {
          if (s is Map) {
            return (s['name'] ?? '')
                    .toString()
                    .toLowerCase() ==
                reqSvc;
          }
          return false;
        });
        if (hasService) count++;
      }
      if (mounted) setState(() => _providersFound = count);
      if (count > 0) {
        _addLog('✅', '$count provider${count == 1 ? '' : 's'} found within $km km', type: 'success');
      } else {
        _addLog('📡', 'No providers online within $km km', type: 'info');
      }
    } catch (e) {}
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
      final updates = {
        'negotiationStatus': 'customer_countered',
        'status': 'negotiating',
        if (counterPrice != null && counterPrice > 0) 'counterPrice': counterPrice,
        'negotiatedAt': DateTime.now().toIso8601String(),
      };
      await FirebaseDatabase.instance.ref('active_bookings/${widget.bookingId}').update(updates);
      await FirebaseDatabase.instance.ref('bookings/${widget.bookingId}').update(updates);

      // Notify provider
      final provId = bookingData['providerId']?.toString() ?? '';
      if (provId.isNotEmpty) {
        final tokenSnap = await FirebaseDatabase.instance.ref('providers/$provId/fcmToken').get();
        final token = tokenSnap.value?.toString() ?? '';
        if (token.isNotEmpty) {
          await http.post(
            Uri.parse('https://notifybooking-mlchyp6tra-as.a.run.app'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'event': 'price_negotiation',
              'fcmToken': token,
              'title': '💬 Customer is Negotiating',
              'body': counterPrice != null && counterPrice > 0
                  ? 'Customer countered with ₹$counterPrice. Send your final offer.'
                  : 'Customer wants a better price. Send your final offer.',
              'data': {
                'bookingId': widget.bookingId,
                'counterPrice': counterPrice?.toString() ?? '0',
              },
            }),
          );
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Negotiation sent. Waiting for provider response...'),
          backgroundColor: AppColors.teal));
        // Restart listening for provider's final offer
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
      final updates = {
        'status': 'accepted',
        'negotiationStatus': 'confirmed',
        'confirmedPrice': price,
        'finalPrice': price,
        'confirmedAt': DateTime.now().toIso8601String(),
      };
      await FirebaseDatabase.instance.ref('active_bookings/${widget.bookingId}').update(updates);
      await FirebaseDatabase.instance.ref('bookings/${widget.bookingId}').update(updates);
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

  void _bookingPending() async {
    if (_navigating || !mounted) return;
    _navigating = true;
        setState(() => _radarActive = false);
    _pollTimer?.cancel();
    _rangeTimer?.cancel();
    try {
      await FirebaseDatabase.instance
          .ref('active_bookings/${widget.bookingId}')
          .update({
        'status': 'pending',
        'pendingAt': DateTime.now().toIso8601String(),
      });
      await FirebaseDatabase.instance
          .ref('bookings/${widget.bookingId}')
          .update({
        'status': 'pending',
        'pendingAt': DateTime.now().toIso8601String(),
      });
    } catch (e) {}
    _addLog('⏳', 'Booking saved as pending — providers will see it', type: 'warn');
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;
    Navigator.pushReplacement(
        context,
        MaterialPageRoute(
            builder: (_) => BookingPendingScreen(
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
      await ApiService.cancelBooking(widget.bookingId);
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