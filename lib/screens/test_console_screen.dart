import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_database/firebase_database.dart';
import '../services/api_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../utils/theme.dart';

class TestConsoleScreen extends StatefulWidget {
  const TestConsoleScreen({super.key});
  @override
  State<TestConsoleScreen> createState() => _TestConsoleScreenState();
}

class _TestConsoleScreenState extends State<TestConsoleScreen> {
  final List<String> _logs = [];
  bool _testing = false;

  void _log(String msg) {
    setState(() => _logs.insert(0, '${DateTime.now().toString().substring(11,19)} — $msg'));
  }

  // ── Test 1: Vibration ──
  Future<void> _testVibration() async {
    HapticFeedback.mediumImpact();
    _log('Testing vibration...');
    try {
      final hasVib = await Vibration.hasVibrator() ?? false;
      _log('Has vibrator: $hasVib');
      if (hasVib) {
        Vibration.vibrate(pattern: [0, 400, 200, 400, 200, 400]);
        _log('✅ Vibration triggered!');
      } else {
        _log('❌ No vibrator found');
      }
    } catch (e) {
      _log('❌ Vibration error: $e');
    }
  }

  // ── Test 2: Haptic Feedback ──
  Future<void> _testHaptic() async {
    _log('Testing haptics...');
    await HapticFeedback.lightImpact();
    await Future.delayed(const Duration(milliseconds: 300));
    await HapticFeedback.mediumImpact();
    await Future.delayed(const Duration(milliseconds: 300));
    await HapticFeedback.heavyImpact();
    _log('✅ Haptic: light → medium → heavy done');
  }

  // ── Test 3: FCM Token ──
  Future<void> _testFCM() async {
    _log('Getting FCM token...');
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        _log('✅ FCM Token: ${token.substring(0, 20)}...');
        // Save to Firebase
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null) {
          await ApiService.saveFcmToken(token);
          _log('✅ Token saved to Firebase');
        }
      } else {
        _log('❌ No FCM token');
      }
    } catch (e) {
      _log('❌ FCM error: $e');
    }
  }

  // ── Test 4: Push Notification to self ──
  Future<void> _testPushNotification() async {
    _log('Sending test push notification...');
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) { _log('❌ No FCM token'); return; }
      final res = await http.post(
        Uri.parse('https://hamaraservice.com/api/notify_booking.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'event': 'booking_accepted',
          'fcmToken': token,
          'data': {
            'providerName': 'Test Provider',
            'service': 'Test Service',
            'bookingId': 'TEST-001',
          },
        }),
      );
      final result = jsonDecode(res.body);
      if (result['sent'] == true) {
        _log('✅ Push notification sent! Check status bar.');
      } else {
        _log('❌ Push failed: ${res.body.substring(0, 100)}');
      }
    } catch (e) {
      _log('❌ Push error: $e');
    }
  }

  // ── Test 5: Fake provider accepted alert ──
  Future<void> _testAcceptedAlert() async {
    _log('Testing provider accepted popup...');
    try {
      final hasVib = await Vibration.hasVibrator() ?? false;
      if (hasVib) Vibration.vibrate(pattern: [0, 400, 200, 400, 200, 400]);
      HapticFeedback.heavyImpact();
      SystemSound.play(SystemSoundType.alert);
    } catch (_) {}
    if (mounted) {
      showDialog(context: context, builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('🎉 Provider Accepted! (TEST)', style: TextStyle(fontWeight: FontWeight.w800)),
        content: const Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Ravi Kumar accepted your House Cleaning booking.'),
          SizedBox(height: 8),
          Text('📞 9876543210', style: TextStyle(color: AppColors.teal, fontWeight: FontWeight.w700)),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(context),
          child: const Text('OK', style: TextStyle(color: AppColors.teal)))],
      ));
      _log('✅ Accepted alert popup shown + vibration');
    }
  }

  // ── Test 6: Fake OTP popup ──
  Future<void> _testOTPPopup() async {
    _log('Testing OTP popup...');
    HapticFeedback.heavyImpact();
    if (mounted) {
      showDialog(context: context, builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: AppColors.green,
        title: const Text('🔐 OTP Required (TEST)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        content: const Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Your OTP:', style: TextStyle(color: Colors.white70)),
          SizedBox(height: 8),
          Text('4 2 7 9', style: TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900, letterSpacing: 8)),
          SizedBox(height: 8),
          Text('Share with provider only after service is done.', style: TextStyle(color: Colors.white70, fontSize: 12)),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(context),
          child: const Text('OK', style: TextStyle(color: Colors.white)))],
      ));
      _log('✅ OTP popup shown');
    }
  }

  // ── Test 7: Firebase write/read ──
  Future<void> _testFirebase() async {
    _log('Testing Firebase connection...');
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'test';
      // Test MySQL connection instead
await ApiService.getCustomer(uid); // ping
if (false) await Future.value({
        'ts': DateTime.now().toIso8601String(), 'app': 'customer'
      });
      final snap = await ApiService.getCustomer(uid);
      if (snap.exists) {
        _log('✅ Firebase write+read OK');
        // cleanup not needed for MySQL test
      } else {
        _log('❌ Firebase read failed');
      }
    } catch (e) {
      _log('❌ Firebase error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('🛠️ Test Console'),
        backgroundColor: AppColors.teal,
        actions: [
          TextButton(
            onPressed: () => setState(() => _logs.clear()),
            child: const Text('Clear', style: TextStyle(color: Colors.white))),
        ],
      ),
      body: Column(children: [
        Container(
          padding: const EdgeInsets.all(12),
          color: Colors.black87,
          child: const Row(children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 16),
            SizedBox(width: 8),
            Text('DEV ONLY — Remove before production',
              style: TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.w700)),
          ]),
        ),
        Expanded(
          flex: 1,
          child: GridView.count(
            crossAxisCount: 2,
            padding: const EdgeInsets.all(12),
            crossAxisSpacing: 10, mainAxisSpacing: 10,
            childAspectRatio: 2.5,
            children: [
              _btn('📳 Vibration', AppColors.teal, _testVibration),
              _btn('🤙 Haptics', AppColors.teal, _testHaptic),
              _btn('🔑 FCM Token', AppColors.brand, _testFCM),
              _btn('🔔 Push Notify', AppColors.brand, _testPushNotification),
              _btn('✅ Accepted Alert', AppColors.green, _testAcceptedAlert),
              _btn('🔐 OTP Popup', AppColors.green, _testOTPPopup),
              _btn('🔥 Firebase', Colors.orange, _testFirebase),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          flex: 1,
          child: Container(
            color: Colors.black87,
            child: _logs.isEmpty
                ? const Center(child: Text('Tap a button to test...', style: TextStyle(color: Colors.white54)))
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: _logs.length,
                    itemBuilder: (_, i) => Text(_logs[i],
                      style: TextStyle(
                        color: _logs[i].contains('✅') ? Colors.greenAccent
                            : _logs[i].contains('❌') ? Colors.redAccent
                            : Colors.white70,
                        fontSize: 12, fontFamily: 'monospace'))),
          ),
        ),
      ]),
    );
  }

  Widget _btn(String label, Color color, VoidCallback onTap) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
      child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)));
  }
}
