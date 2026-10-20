import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/session.dart';
import '../services/api_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../utils/theme.dart';

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
    showSnack(context, msg, error: true);
  }

  Future<void> _saveAndContinue(String city) async {
    if (city.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_city', city.trim());
    await prefs.setBool('location_set', true);

    if (Session.signedIn) {
      try {
        await ApiService.updateCustomer({'city': city.trim()});
      } on ApiException catch (e) {
        _showError('City saved on this device only: ${e.message}');
      }
    }

    if (!mounted) return;
    // Opened from Home — return there (Home reloads the city on pop).
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final q = _searchCtrl.text.trim();
    return Scaffold(
      appBar: AppBar(title: const Text('Your location')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            controller: _searchCtrl,
            autofocus: false,
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() {}),
            onSubmitted: (v) { if (v.trim().isNotEmpty) _saveAndContinue(v.trim()); },
            decoration: InputDecoration(
              hintText: 'Search your city or area…',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: q.isNotEmpty
                  ? IconButton(
                      tooltip: 'Clear',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () { _searchCtrl.clear(); setState(() {}); })
                  : null,
            ),
          ),
        ),
        Expanded(
          child: ListView(children: [
            ListTile(
              leading: _detecting
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5))
                  : const Icon(Icons.my_location_rounded, color: AppColors.teal),
              title: Text('Use my current location',
                  style: t.titleSmall?.copyWith(color: AppColors.teal2)),
              subtitle: const Text('Detect automatically using GPS'),
              onTap: _detecting ? null : _detectLocation,
            ),
            const Divider(),
            if (q.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.add_location_alt_outlined, color: AppColors.brand),
                title: Text('Use "$q"'),
                onTap: () => _saveAndContinue(q),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(q.isEmpty ? 'Popular cities' : 'Matching cities',
                  style: t.labelLarge?.copyWith(color: AppColors.muted)),
            ),
            for (final city in _filtered)
              ListTile(
                leading: const Icon(Icons.location_city_outlined),
                title: Text(city),
                onTap: () => _saveAndContinue(city),
              ),
          ]),
        ),
      ]),
    );
  }
}
