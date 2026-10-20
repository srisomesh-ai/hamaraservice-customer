import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../utils/theme.dart';
import 'home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
    _fade  = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _scale = Tween<double>(begin: 0.8, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut));
    _ctrl.forward();
    _navigate();
  }

  Future<void> _navigate() async {
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    final user = FirebaseAuth.instance.currentUser;
    bool askLocation = false;
    if (user != null) {
      try {
        askLocation =
            await Geolocator.checkPermission() == LocationPermission.denied;
      } catch (_) {
        askLocation = false;
      }
    }
    if (!mounted) return;
    // Guests can browse; login is asked only when they try to book.
    Navigator.pushReplacement(
      context, MaterialPageRoute(builder: (_) => const HomeScreen()));
    if (user != null && askLocation) {
      await Future.delayed(const Duration(milliseconds: 500));
      // This splash route is gone now — use the app navigator's context.
      final ctx = navigatorKey.currentContext;
      if (ctx != null && ctx.mounted) {
        showDialog(
          context: ctx,
          barrierDismissible: false,
          builder: (_) => const _LocationDialog(),
        );
      }
    }
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0D3D47), AppColors.teal],
          ),
        ),
        child: Center(
          child: FadeTransition(
            opacity: _fade,
            child: ScaleTransition(
              scale: _scale,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    margin: const EdgeInsets.symmetric(horizontal: 32),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.18),
                          blurRadius: 24, offset: const Offset(0, 8)),
                      ],
                    ),
                    child: Image.asset('assets/images/rlogo.png',
                        width: 260, fit: BoxFit.contain),
                  ),
                  const SizedBox(height: 48),
                  const SizedBox(width: 28, height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white54))),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Location Permission Dialog ───────────────────────────────────
class _LocationDialog extends StatefulWidget {
  const _LocationDialog();
  @override
  State<_LocationDialog> createState() => _LocationDialogState();
}

class _LocationDialogState extends State<_LocationDialog> {
  bool _detecting = false;
  String _status = '';
  bool _done = false;

  Future<void> _allow() async {
    setState(() { _detecting = true; _status = 'Detecting your location...'; });
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        setState(() { _status = 'Permission denied. Enable in Settings.'; _detecting = false; });
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) Navigator.pop(context);
        return;
      }
      if (permission == LocationPermission.denied) {
        setState(() { _status = 'Permission denied.'; _detecting = false; });
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) Navigator.pop(context);
        return;
      }
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      String city = '';
      try {
        final placemarks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
        if (placemarks.isNotEmpty) {
          city = placemarks.first.locality ?? placemarks.first.subAdministrativeArea ?? '';
        }
      } catch (_) {}
      try {
        await ApiService.updateCustomer({
          'lat': pos.latitude, 'lng': pos.longitude,
          if (city.isNotEmpty) 'city': city,
        });
      } on ApiException catch (e) {
        debugPrint('Saving location failed: ${e.message}');
      }
      if (!mounted) return;
      setState(() {
        _status = city.isNotEmpty ? '📍 Location set to $city!' : '📍 Location detected!';
        _detecting = false;
        _done = true;
      });
      await Future.delayed(const Duration(milliseconds: 800));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() { _status = 'Could not detect location.'; _detecting = false; });
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 72, height: 72,
            decoration: BoxDecoration(color: AppColors.tealSoft, shape: BoxShape.circle),
            child: const Icon(Icons.location_on_rounded, color: AppColors.teal, size: 38)),
          const SizedBox(height: 16),
          const Text('Allow Location Access',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.ink)),
          const SizedBox(height: 10),
          const Text(
            'HamaraService needs your location to find nearby service providers.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.muted, height: 1.5)),
          if (_status.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _done ? AppColors.greenSoft : AppColors.tealSoft,
                borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                if (_detecting)
                  const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.teal))
                else
                  Icon(_done ? Icons.check_circle_rounded : Icons.info_rounded,
                    color: _done ? AppColors.green : AppColors.teal, size: 16),
                const SizedBox(width: 8),
                Expanded(child: Text(_status,
                  style: TextStyle(fontSize: 12,
                    color: _done ? AppColors.green : AppColors.teal,
                    fontWeight: FontWeight.w600))),
              ])),
          ],
          const SizedBox(height: 20),
          SizedBox(width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _detecting ? null : _allow,
              icon: const Icon(Icons.my_location_rounded, color: Colors.white, size: 18),
              label: const Text('Allow Location',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))))),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _detecting ? null : () => Navigator.pop(context),
            child: const Text('Skip for now',
              style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600))),
        ]),
      ),
    );
  }
}
