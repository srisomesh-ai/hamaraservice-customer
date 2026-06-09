import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
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

class _RadarScreenState extends State<RadarScreen> with TickerProviderStateMixin {
  final List<int> _ranges = [1, 3, 5, 10, 15, 20];
  int _currentRangeIdx = 0;
  bool _radarActive = true;
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
    _sweepCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2500))..repeat();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat(reverse: true);
    _sweepAnim = Tween(begin: 0.0, end: 2 * pi).animate(_sweepCtrl);
    _pulseAnim = Tween(begin: 0.8, end: 1.0).animate(_pulseCtrl);
    _startRange(0);
  }

  @override
  void dispose() {
    _sweepCtrl.dispose();
    _pulseCtrl.dispose();
    _pollTimer?.cancel();
    _rangeTimer?.cancel();
    super.dispose();
  }

  double _haversine(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLng = (lng2 - lng1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) * cos(lat2 * pi / 180) * sin(dLng / 2) * sin(dLng / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  void _addLog(String emoji, String message, {String type = ''}) {
    if (!mounted) return;
    setState(() {
      _logs.insert(0, {'emoji': emoji, 'message': message, 'type': type, 'time': DateTime.now()});
      if (_logs.length > 10) _logs.removeLast();
    });
  }

  Future<void> _startRange(int idx) async {
    if (!_radarActive || !mounted) return;
    if (idx >= _ranges.length) {
      _showNoProviderFound();
      return;
    }

    setState(() => _currentRangeIdx = idx);
    final km = _ranges[idx];

    if (idx == 0) {
      _addLog('📡', 'Radar active — scanning $km km radius');
    } else {
      _addLog('↔️', 'Expanding to $km km — no response within ${_ranges[idx - 1]} km', type: 'warn');
    }

    // Update Firebase
    final db = FirebaseDatabase.instance;
    await db.ref('active_bookings/${widget.bookingId}/range').set(km);
    await db.ref('active_bookings/${widget.bookingId}/status').set('searching');
    await db.ref('notifications/search_${widget.bookingId}').set({
      'bookingId': widget.bookingId,
      'service': widget.service['name'],
      'lat': widget.lat ?? 0.0,
      'lng': widget.lng ?? 0.0,
      'range': km,
      'ts': DateTime.now().millisecondsSinceEpoch,
      'status': 'searching',
    });

    // Count providers in range
    _countProviders(km);

    // Poll for acceptance every 3 seconds, for 18 seconds
    int elapsed = 0;
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (t) async {
      if (!_radarActive || !mounted) { t.cancel(); return; }
      elapsed += 3;
      final snap = await db.ref('active_bookings/${widget.bookingId}').get();
      if (!snap.exists) { t.cancel(); return; }
      final data = Map<String, dynamic>.from(snap.value as Map);
      if (data['acceptedBy'] != null) {
        t.cancel();
        _providerAccepted(data['acceptedBy'] as String);
        return;
      }
      if (elapsed >= 18) {
        t.cancel();
        _startRange(idx + 1);
      }
    });
  }

  Future<void> _countProviders(int km) async {
    try {
      final snap = await FirebaseDatabase.instance.ref('providers').get();
      if (!snap.exists) { _addLog('📡', 'No providers in database yet'); return; }
      final all = Map<String, dynamic>.from(snap.value as Map);
      final reqSvc = (widget.service['name'] as String).toLowerCase();
      int count = 0;
      all.values.forEach((v) {
        final p = Map<String, dynamic>.from(v as Map);
        if (p['available'] == false) return;
        if (p['status'] != 'approved') return;
        final pLat = (p['lat'] as num?)?.toDouble();
        final pLng = (p['lng'] as num?)?.toDouble();
        if (pLat == null || pLng == null) return;
        if (widget.lat != null && widget.lng != null) {
          if (_haversine(widget.lat!, widget.lng!, pLat, pLng) > km) return;
        }
        final services = p['services'];
        if (services == null) return;
        final svcList = services is List ? services : (services as Map).values.toList();
        final hasService = svcList.any((s) {
          if (s is Map) return (s['name'] ?? '').toString().toLowerCase() == reqSvc;
          return false;
        });
        if (hasService) count++;
      });
      if (mounted) setState(() => _providersFound = count);
      if (count > 0) {
        _addLog('👥', '$count provider${count == 1 ? '' : 's'} found within $km km — sending alert', type: 'success');
      } else {
        _addLog('📡', 'No providers within $km km — continuing...');
      }
    } catch (e) {
      _addLog('📡', 'Scanning providers...');
    }
  }

  void _providerAccepted(String providerId) async {
    if (!mounted) return;
    setState(() => _radarActive = false);
    _addLog('✅', 'Provider found! Connecting...', type: 'success');
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(
      builder: (_) => BookingConfirmedScreen(
        bookingId: widget.bookingId,
        service: widget.service,
        date: widget.date,
        timeSlot: widget.timeSlot,
        address: widget.address,
        price: widget.price,
      ),
    ));
  }

  void _showNoProviderFound() {
    if (!mounted) return;
    setState(() => _radarActive = false);
    _addLog('😔', 'No providers available right now. Booking saved!', type: 'warn');
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('No Providers Found', style: TextStyle(fontWeight: FontWeight.w800)),
        content: const Text('No providers are available right now. Your booking has been saved and we\'ll notify you when a provider accepts.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushReplacement(context, MaterialPageRoute(
                builder: (_) => BookingConfirmedScreen(
                  bookingId: widget.bookingId,
                  service: widget.service,
                  date: widget.date,
                  timeSlot: widget.timeSlot,
                  address: widget.address,
                  price: widget.price,
                ),
              ));
            },
            child: const Text('OK', style: TextStyle(color: AppColors.teal, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _cancelSearch() async {
    setState(() => _radarActive = false);
    _pollTimer?.cancel();
    await FirebaseDatabase.instance.ref('active_bookings/${widget.bookingId}/status').set('cancelled');
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final km = _ranges[_currentRangeIdx];
    return Scaffold(
      backgroundColor: const Color(0xFF080C14),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                GestureDetector(
                  onTap: _cancelSearch,
                  child: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.arrow_back, color: Colors.white, size: 18),
                  ),
                ),
                const SizedBox(width: 12),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Searching for Professionals',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
                  Text(_radarActive ? 'Range: $km km' : 'Search complete',
                    style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.5))),
                ]),
              ]),
            ),

            // Radar animation
            Expanded(
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  SizedBox(
                    width: 240, height: 240,
                    child: AnimatedBuilder(
                      animation: _sweepCtrl,
                      builder: (_, __) => CustomPaint(
                        painter: _RadarPainter(_sweepAnim.value, _pulseAnim.value),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('$km km', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: Colors.white)),
                  Text('Scanning within $km km of your location',
                    style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.45))),
                  if (_providersFound > 0) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.green.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.green.withOpacity(0.3)),
                      ),
                      child: Text('$_providersFound provider${_providersFound == 1 ? '' : 's'} in range',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.green)),
                    ),
                  ],
                  const SizedBox(height: 20),

                  // Logs
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: _logs.length,
                      itemBuilder: (_, i) {
                        final log = _logs[i];
                        final type = log['type'] as String;
                        final color = type == 'success' ? AppColors.green :
                          type == 'warn' ? AppColors.yellow : Colors.white.withOpacity(0.6);
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white.withOpacity(0.1)),
                          ),
                          child: Row(children: [
                            Text(log['emoji'] as String, style: const TextStyle(fontSize: 16)),
                            const SizedBox(width: 10),
                            Expanded(child: Text(log['message'] as String,
                              style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w500))),
                          ]),
                        );
                      },
                    ),
                  ),

                  // Cancel button
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: GestureDetector(
                      onTap: _cancelSearch,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(100),
                          border: Border.all(color: Colors.white.withOpacity(0.18)),
                        ),
                        child: Text('✕ Cancel Search',
                          style: TextStyle(color: Colors.white.withOpacity(0.65), fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                ],
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

    // Concentric circles
    for (int i = 1; i <= 5; i++) {
      final paint = Paint()
        ..color = const Color(0xFF00FF88).withOpacity(0.06 + (i == 3 ? 0.04 : 0))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      canvas.drawCircle(Offset(cx, cy), maxR * i / 5, paint);
    }

    // Cross lines
    final linePaint = Paint()
      ..color = const Color(0xFF00FF88).withOpacity(0.07)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(cx, 0), Offset(cx, size.height), linePaint);
    canvas.drawLine(Offset(0, cy), Offset(size.width, cy), linePaint);

    // Sweep
    final sweepPaint = Paint()
      ..shader = SweepGradient(
        startAngle: sweep - 0.6,
        endAngle: sweep,
        colors: [Colors.transparent, const Color(0xFF00FF88).withOpacity(0.15)],
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: maxR))
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx, cy), maxR, sweepPaint);

    // Sweep line
    final linePaint2 = Paint()
      ..color = const Color(0xFF00FF88).withOpacity(0.6)
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(cx, cy),
      Offset(cx + maxR * cos(sweep - pi / 2), cy + maxR * sin(sweep - pi / 2)),
      linePaint2,
    );

    // Center dot
    final centerPaint = Paint()..color = AppColors.teal;
    canvas.drawCircle(Offset(cx, cy), 6, centerPaint);
    final centerRing = Paint()
      ..color = AppColors.teal.withOpacity(0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(Offset(cx, cy), 10, centerRing);
  }

  @override
  bool shouldRepaint(_RadarPainter old) => old.sweep != sweep || old.pulse != pulse;
}
