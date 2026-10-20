import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/session.dart';
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
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));
    _ctrl.forward();
    _navigate();
  }

  Future<void> _navigate() async {
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    final user = Session.user;
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
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppTheme.overlay,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: FadeTransition(
            opacity: _fade,
            child: ScaleTransition(
              scale: _scale,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Image.asset('assets/images/rlogo.png', width: 280, fit: BoxFit.contain),
                ),
                const SizedBox(height: 40),
                const SizedBox(
                    width: 28, height: 28,
                    child: CircularProgressIndicator(strokeWidth: 3)),
              ]),
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
        _status = city.isNotEmpty ? 'Location set to $city' : 'Location detected';
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
    final t = Theme.of(context).textTheme;
    return AlertDialog(
      icon: const CircleAvatar(
        radius: 28,
        backgroundColor: AppColors.tealSoft,
        child: Icon(Icons.location_on_rounded, color: AppColors.teal, size: 30),
      ),
      title: const Text('Allow location access'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('HamaraService needs your location to find nearby service providers.',
            textAlign: TextAlign.center,
            style: t.bodyMedium?.copyWith(color: AppColors.ink2)),
        if (_status.isNotEmpty) ...[
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (_detecting)
              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            else
              Icon(_done ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                  color: _done ? AppColors.green : AppColors.teal, size: 18),
            const SizedBox(width: 8),
            Flexible(
                child: Text(_status,
                    style: t.bodyMedium?.copyWith(
                        color: _done ? AppColors.green : AppColors.teal2))),
          ]),
        ],
      ]),
      actions: [
        TextButton(
            onPressed: _detecting ? null : () => Navigator.pop(context),
            child: const Text('Skip for now')),
        FilledButton.icon(
          onPressed: _detecting ? null : _allow,
          icon: const Icon(Icons.my_location_rounded, size: 18),
          label: const Text('Allow location'),
        ),
      ],
    );
  }
}
