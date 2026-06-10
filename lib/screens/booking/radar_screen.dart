import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
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
  Timer? _pollTimer;
  final List<Map<String, dynamic>> _logs = [];
  int _providersFound = 0;
  int _rangeElapsed = 0;

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
    _sweepAnim = Tween(begin: 0.0, end: 2 * pi).animate(_sweepCtrl);
    _pulseAnim = Tween(begin: 0.8, end: 1.0).animate(_pulseCtrl);
    _startRange(0);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sweepCtrl.dispose();
    _pulseCtrl.dispose();
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      if (_radarActive) {
        _radarActive = false;
        _pollTimer?.cancel();
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
    }
  }

  double _haversine(double lat1, double lng1, double lat2, double lng2) {
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
      _logs.insert(0, {'emoji': emoji, 'message': message, 'type': type});
      if (_logs.length > 10) _logs.removeLast();
    });
  }

  Future<void> _startRange(int idx) async {
    if (!_radarActive || !mounted) return;
    if (idx >= _ranges.length) {
      _bookingPending();
      return;
    }

    setState(() {
      _currentRangeIdx = idx;
      _providersFound = 0;
      _rangeElapsed = 0;
    });

    final km = _ranges[idx];

    if (idx == 0) {
      _addLog('📡', 'Searching for providers within $km km...');
    } else {
      _addLog('↔️', 'Expanding to $km km radius', type: 'warn');
    }

    final db = FirebaseDatabase.instance;
    await db.ref('active_bookings/${widget.bookingId}').update({
      'range': km,
      'status': 'searching',
    });

    _countProviders(km);

    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (t) async {
      if (!_radarActive || !mounted) {
        t.cancel();
        return;
      }
      _rangeElapsed += 3;

      try {
        final snap = await db
            .ref('active_bookings/${widget.bookingId}/acceptedBy')
            .get();
        if (snap.exists && snap.value != null) {
          t.cancel();
          _providerAccepted();
          return;
        }
      } catch (e) {}

      if (_rangeElapsed >= 30) {
        t.cancel();
        _startRange(idx + 1);
      }
    });
  }

  Future<void> _countProviders(int km) async {
    try {
      final snap =
          await FirebaseDatabase.instance.ref('providers').get();
      if (!snap.exists) return;
      final all = Map<String, dynamic>.from(snap.value as Map);
      final reqSvc = (widget.service['name'] as String).toLowerCase();
      int count = 0;
      for (final v in all.values) {
        final p = Map<String, dynamic>.from(v as Map);
        if (p['available'] != true) continue;
        if (p['status'] != 'approved') continue;
        final pLat = (p['lat'] as num?)?.toDouble();
        final pLng = (p['lng'] as num?)?.toDouble();
        if (pLat == null || pLng == null) continue;
        if (widget.lat != null && widget.lng != null) {
          if (_haversine(widget.lat!, widget.lng!, pLat, pLng) > km) continue;
        }
        final services = p['services'];
        if (services == null) continue;
        final svcList = services is List
            ? services
            : (services as Map).values.toList();
        final hasService = svcList.any((s) {
          if (s is Map)
            return (s['name'] ?? '').toString().toLowerCase() == reqSvc;
          return false;
        });
        if (hasService) count++;
      }
      if (mounted) setState(() => _providersFound = count);
      if (count > 0) {
        _addLog('👥', '$count provider${count == 1 ? '' : 's'} found within $km km',
            type: 'success');
      } else {
        _addLog('🔍', 'No providers online within $km km yet...');
      }
    } catch (e) {}
  }

  void _providerAccepted() async {
    if (!mounted) return;
    setState(() => _radarActive = false);
    _addLog('✅', 'Provider found! Confirmed!', type: 'success');
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
                  price: widget.price,
                )));
  }

  void _bookingPending() async {
    if (!mounted) return;
    setState(() => _radarActive = false);
    _pollTimer?.cancel();

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

    _addLog('📋', 'Booking saved as pending!', type: 'warn');

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
                  price: widget.price,
                )));
  }

  void _cancelSearch() async {
    setState(() => _radarActive = false);
    _pollTimer?.cancel();
    await FirebaseDatabase.instance
        .ref('active_bookings/${widget.bookingId}/status')
        .set('cancelled');
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final km = _ranges[_currentRangeIdx];
    final progress = _currentRangeIdx / (_ranges.length - 1);

    return Scaffold(
      backgroundColor: const Color(0xFF080C14),
      body: SafeArea(
        child: Column(
          children: [
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
                    child: const Icon(Icons.close, color: Colors.white, size: 18),
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
                          _radarActive ? 'Range: $km km' : 'Search complete',
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withOpacity(0.5))),
                    ])),
              ]),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                    backgroundColor: Colors.white.withOpacity(0.1),
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
                  painter:
                      _RadarPainter(_sweepAnim.value, _pulseAnim.value),
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
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: Colors.white.withOpacity(0.1)),
                    ),
                    child: Row(children: [
                      Text(log['emoji'] as String,
                          style: const TextStyle(fontSize: 16)),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Text(log['message'] as String,
                              style: TextStyle(
                                  fontSize: 13,
                                  color: color,
                                  fontWeight: FontWeight.w500))),
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
          ],
        ),
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
    canvas.drawLine(Offset(cx, 0), Offset(cx, size.height), linePaint);
    canvas.drawLine(Offset(0, cy), Offset(size.width, cy), linePaint);

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
          ).createShader(
              Rect.fromCircle(center: Offset(cx, cy), radius: maxR))
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
  bool shouldRepaint(_RadarPainter old) => old.sweep != sweep;
}
