import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import '../services/api_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../utils/theme.dart';
import 'home_screen.dart';
import 'login_screen.dart';

class LocationScreen extends StatefulWidget {
  const LocationScreen({super.key});
  @override
  State<LocationScreen> createState() => _LocationScreenState();
}

class _LocationScreenState extends State<LocationScreen> {
  final _searchCtrl = TextEditingController();
  bool _detecting = false;

  final List<String> _popularCities = [
    'Visakhapatnam', 'Hyderabad', 'Vijayawada', 'Chennai',
    'Bangalore', 'Mumbai', 'Delhi', 'Pune', 'Kolkata', 'Ahmedabad',
    'Surat', 'Jaipur', 'Lucknow', 'Nagpur', 'Bhopal',
  ];

  List<String> get _filtered {
    if (_searchCtrl.text.isEmpty) return _popularCities;
    return _popularCities.where((c) =>
      c.toLowerCase().contains(_searchCtrl.text.toLowerCase())).toList();
  }

  Future<void> _detectLocation() async {
    setState(() => _detecting = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _detecting = false);
        _showError('Location services are disabled. Please enable GPS.');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() => _detecting = false);
          _showError('Location permission denied. Please select city manually.');
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() => _detecting = false);
        _showError('Location permission permanently denied. Please select city manually.');
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
      );

      final placemarks = await placemarkFromCoordinates(
        position.latitude, position.longitude,
      );

      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        final city = place.locality ??
            place.subAdministrativeArea ??
            place.administrativeArea ??
            'Your City';
        setState(() => _detecting = false);
        await _saveAndContinue(city);
      } else {
        setState(() => _detecting = false);
        _showError('Could not detect city. Please select manually.');
      }
    } catch (e) {
      setState(() => _detecting = false);
      _showError('Could not detect location. Please select manually.');
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _saveAndContinue(String city) async {
    if (city.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_city', city.trim());
    await prefs.setBool('location_set', true);

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        await ApiService.updateCustomer({
          'city': city.trim(),
          'updatedAt': DateTime.now().toIso8601String(),
        });
      } catch (e) {}
    }

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => user != null ? const HomeScreen() : const LoginScreen(),
      ),
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF0D3D47), AppColors.teal],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.brand,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: const Icon(Icons.home_rounded, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 10),
                    RichText(text: const TextSpan(children: [
                      TextSpan(text: 'Hamara', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
                      TextSpan(text: 'Service', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.brand)),
                    ])),
                  ]),
                  const SizedBox(height: 20),
                  const Text('📍 Where are you?',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white)),
                  const SizedBox(height: 6),
                  const Text('Select your city to see available services near you',
                    style: TextStyle(fontSize: 13, color: Colors.white70)),
                  const SizedBox(height: 20),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (v) { if (v.trim().isNotEmpty) _saveAndContinue(v.trim()); },
                      decoration: InputDecoration(
                        hintText: 'Search your city or area...',
                        prefixIcon: const Icon(Icons.search, color: AppColors.muted),
                        suffixIcon: _searchCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, color: AppColors.muted),
                                onPressed: () { _searchCtrl.clear(); setState(() {}); })
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        hintStyle: const TextStyle(color: AppColors.muted, fontSize: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // GPS detect button
            Padding(
              padding: const EdgeInsets.all(16),
              child: GestureDetector(
                onTap: _detecting ? null : _detectLocation,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.teal.withOpacity(0.3)),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
                  ),
                  child: Row(children: [
                    Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.tealSoft,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: _detecting
                          ? const Center(child: SizedBox(width: 20, height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.teal)))
                          : const Icon(Icons.my_location_rounded, color: AppColors.teal, size: 22),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Use my current location',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.teal)),
                        Text('Detect automatically using GPS',
                          style: TextStyle(fontSize: 12, color: AppColors.muted)),
                      ],
                    )),
                    const Icon(Icons.chevron_right, color: AppColors.muted),
                  ]),
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                _searchCtrl.text.isEmpty ? 'POPULAR CITIES' : 'SEARCH RESULTS',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                  color: AppColors.muted, letterSpacing: 0.8),
              ),
            ),
            const SizedBox(height: 8),

            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _filtered.length + (_searchCtrl.text.isNotEmpty ? 1 : 0),
                itemBuilder: (_, i) {
                  if (_searchCtrl.text.isNotEmpty && i == _filtered.length) {
                    return GestureDetector(
                      onTap: () => _saveAndContinue(_searchCtrl.text.trim()),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.brandSoft,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.brand.withOpacity(0.3)),
                        ),
                        child: Row(children: [
                          const Icon(Icons.add_location_rounded, color: AppColors.brand, size: 20),
                          const SizedBox(width: 12),
                          Text('Use "${_searchCtrl.text.trim()}"',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.brand)),
                        ]),
                      ),
                    );
                  }
                  final city = _filtered[i];
                  return GestureDetector(
                    onTap: () => _saveAndContinue(city),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)],
                      ),
                      child: Row(children: [
                        const Icon(Icons.location_on_rounded, color: AppColors.teal, size: 20),
                        const SizedBox(width: 12),
                        Text(city, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.ink)),
                        const Spacer(),
                        const Icon(Icons.chevron_right, color: AppColors.muted, size: 18),
                      ]),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
