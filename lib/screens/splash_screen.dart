import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:firebase_database/firebase_database.dart';
import '../utils/theme.dart';
import 'login_screen.dart';
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
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _scale = Tween<double>(begin: 0.8, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut));
    _ctrl.forward();
    _navigate();
  }

  Future<void> _navigate() async {
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
      return;
    }
    // Check if location already set
    final snap = await FirebaseDatabase.instance.ref('customers/${user.uid}/city').get();
    final hasCity = snap.exists && (snap.value?.toString().isNotEmpty == true);
    if (!hasCity) {
      // Show location permission popup then go home
      await _showLocationPopup(user.uid);
    } else {
      // Try to refresh location silently in background
      _refreshLocationSilently(user.uid);
    }
    if (mounted) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen()));
    }
  }

  Future<void> _showLocationPopup(String uid) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _LocationPermissionDialog(uid: uid),
    );
  }

  Future<void> _refreshLocationSilently(String uid) async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium);
      String city = '';
      try {
        final placemarks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
        if (placemarks.isNotEmpty) city = placemarks.first.locality ?? '';
      } catch (e) {}
      await FirebaseDatabase.instance.ref('customers/$uid').update({
        'lat': pos.latitude, 'lng': pos.longitude,
        if (city.isNotEmpty) 'city': city,
      });
    } catch (e) {}
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
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 90, height: 90,
                  decoration: BoxDecoration(
                    color: AppColors.brand,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [BoxShadow(color: AppColors.brand.withOpacity(0.4), blurRadius: 24, offset: const Offset(0, 8))],
                  ),
                  child: const Icon(Icons.home_rounded, color: Colors.white, size: 48),
                ),
                const SizedBox(height: 20),
                RichText(text: const TextSpan(children: [
                  TextSpan(text: 'Hamara', style: TextStyle(fontFamily: 'Sora', fontSize: 32, fontWeight: FontWeight.w800, color: Colors.white)),
                  TextSpan(text: 'Service', style: TextStyle(fontFamily: 'Sora', fontSize: 32, fontWeight: FontWeight.w800, color: AppColors.brand)),
                ])),
                const SizedBox(height: 8),
                const Text('Home services at your doorstep',
                  style: TextStyle(fontFamily: 'Sora', fontSize: 14, color: Colors.white70)),
                const SizedBox(height: 48),
                const SizedBox(width: 28, height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white54))),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Location Permission Dialog ───────────────────────────────────
class _LocationPermissionDialog extends StatefulWidget {
  final String uid;
  const _LocationPermissionDialog({required this.uid});
  @override
  State<_LocationPermissionDialog> createState() => _LocationPermissionDialogState();
}

class _LocationPermissionDialogState extends State<_LocationPermissionDialog> {
  bool _detecting = false;
  String _status = '';

  Future<void> _allowLocation() async {
    setState(() { _detecting = true; _status = 'Detecting your location...'; });
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        setState(() { _status = 'Permission denied. You can change in Settings.'; _detecting = false; });
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) Navigator.pop(context);
        return;
      }
      if (permission == LocationPermission.denied) {
        setState(() { _status = 'Location permission denied.'; _detecting = false; });
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) Navigator.pop(context);
        return;
      }
      setState(() => _status = 'Getting your location...');
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      String city = '';
      try {
        final placemarks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
        if (placemarks.isNotEmpty) city = placemarks.first.locality ?? placemarks.first.subAdministrativeArea ?? '';
      } catch (e) {}
      await FirebaseDatabase.instance.ref('customers/${widget.uid}').update({
        'lat': pos.latitude, 'lng': pos.longitude,
        if (city.isNotEmpty) 'city': city,
      });
      setState(() { _status = city.isNotEmpty ? 'Location set to $city!' : 'Location detected!'; _detecting = false; });
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
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(color: AppColors.tealSoft, shape: BoxShape.circle),
            child: const Icon(Icons.location_on_rounded, color: AppColors.teal, size: 38),
          ),
          const SizedBox(height: 16),
          const Text('Allow Location Access', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.ink)),
          const SizedBox(height: 8),
          const Text('HamaraService needs your location to find nearby service providers and show accurate services in your area.',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: AppColors.muted, height: 1.5)),
          const SizedBox(height: 20),
          if (_status.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _status.contains('!') ? AppColors.greenSoft : AppColors.tealSoft,
                borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                if (_detecting) const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.teal))
                else Icon(_status.contains('!') ? Icons.check_circle_rounded : Icons.info_rounded,
                  color: _status.contains('!') ? AppColors.green : AppColors.teal, size: 16),
                const SizedBox(width: 8),
                Expanded(child: Text(_status, style: TextStyle(fontSize: 12,
                  color: _status.contains('!') ? AppColors.green : AppColors.teal, fontWeight: FontWeight.w600))),
              ]),
            ),
            const SizedBox(height: 16),
          ],
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _detecting ? null : _allowLocation,
              icon: const Icon(Icons.my_location_rounded, color: Colors.white, size: 20),
              label: const Text('Allow Location', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: _detecting ? null : () => Navigator.pop(context),
            child: const Text('Skip for now', style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600))),
        ]),
      ),
    );
  }
}
