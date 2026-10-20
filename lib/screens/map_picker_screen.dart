import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../utils/theme.dart';

/// Result of [MapPickerScreen]: the pinned point and its (reverse-geocoded)
/// address. [address] / [city] may be empty when geocoding failed.
class MapPickResult {
  final double lat;
  final double lng;
  final String address;
  final String city;
  const MapPickResult({
    required this.lat,
    required this.lng,
    this.address = '',
    this.city = '',
  });
}

// ══════════════════════════════════════════════════════════════
// Map location picker (OpenStreetMap). The pin stays in the centre;
// the user pans/zooms the map under it. When the map stops moving the
// centre is reverse-geocoded. Confirm pops a [MapPickResult].
// Same behaviour as the website's HS_MapPicker (js/hs-map.js).
// ══════════════════════════════════════════════════════════════
class MapPickerScreen extends StatefulWidget {
  final double? lat;
  final double? lng;
  final String title;
  final String confirmText;
  const MapPickerScreen({
    super.key,
    this.lat,
    this.lng,
    this.title = 'Pin your service location',
    this.confirmText = 'Use this location',
  });

  /// Opens the picker; returns null when the user backs out.
  static Future<MapPickResult?> open(BuildContext context,
          {double? lat, double? lng}) =>
      Navigator.push<MapPickResult>(context,
          MaterialPageRoute(builder: (_) => MapPickerScreen(lat: lat, lng: lng)));

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  static const _indiaCentre = LatLng(20.5937, 78.9629);

  final _map = MapController();
  Timer? _settle;
  int _geoSeq = 0;
  late LatLng _centre;
  String _address = '';
  String _city = '';
  bool _resolving = false;
  bool _locating = false;

  bool get _hasStart =>
      widget.lat != null && widget.lng != null && widget.lat != 0 && widget.lng != 0;

  @override
  void initState() {
    super.initState();
    _centre = _hasStart ? LatLng(widget.lat!, widget.lng!) : _indiaCentre;
    if (_hasStart) {
      _reverseGeocode(_centre);
    } else {
      // No start point — jump to the device location once the map is ready.
      WidgetsBinding.instance.addPostFrameCallback((_) => _useMyLocation());
    }
  }

  @override
  void dispose() {
    _settle?.cancel();
    _map.dispose();
    super.dispose();
  }

  void _onPositionChanged(MapPosition pos, bool hasGesture) {
    final c = pos.center;
    if (c == null) return;
    _centre = c;
    // Reverse-geocode only once the map has stopped moving.
    _settle?.cancel();
    _settle = Timer(const Duration(milliseconds: 700), () => _reverseGeocode(c));
  }

  Future<void> _reverseGeocode(LatLng c) async {
    final seq = ++_geoSeq;
    if (mounted) setState(() => _resolving = true);
    String addr = '';
    String city = '';
    try {
      final marks = await placemarkFromCoordinates(c.latitude, c.longitude);
      if (marks.isNotEmpty) {
        final p = marks.first;
        addr = [p.name, p.street, p.subLocality, p.locality, p.postalCode]
            .whereType<String>()
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toSet() // name and street are often identical
            .join(', ');
        city = (p.locality ?? '').isNotEmpty
            ? p.locality!
            : (p.subAdministrativeArea ?? '');
      }
    } catch (_) {
      // geocoding is optional — the coordinates are what matter
    }
    if (!mounted || seq != _geoSeq) return;
    setState(() {
      _address = addr;
      _city = city;
      _resolving = false;
    });
  }

  Future<void> _useMyLocation() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _toast('Turn on location (GPS) and try again.');
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        _toast('Location permission denied — move the map to your location.');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 15));
      if (!mounted) return;
      final c = LatLng(pos.latitude, pos.longitude);
      _map.move(c, 17);
      _centre = c;
      _reverseGeocode(c);
    } catch (_) {
      _toast('Could not get your location. Move the map to pin it.');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    showSnack(context, msg, error: true);
  }

  void _confirm() {
    HapticFeedback.mediumImpact();
    if (_centre == _indiaCentre) {
      _toast('Move the map so the pin is on your location.');
      return;
    }
    Navigator.pop(
      context,
      MapPickResult(
        lat: double.parse(_centre.latitude.toStringAsFixed(7)),
        lng: double.parse(_centre.longitude.toStringAsFixed(7)),
        address: _address,
        city: _city,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(children: [
        Expanded(
          child: Stack(children: [
            FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: _centre,
                initialZoom: _hasStart ? 16 : 5,
                minZoom: 3,
                maxZoom: 19,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
                onPositionChanged: _onPositionChanged,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.hamaraservice.customer',
                  maxZoom: 19,
                ),
                const SimpleAttributionWidget(
                  source: Text('© OpenStreetMap contributors'),
                ),
              ],
            ),
            // Fixed centre pin (its tip marks the chosen point)
            const IgnorePointer(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.only(bottom: 48),
                  child: Icon(Icons.location_on_rounded,
                      size: 48,
                      color: AppColors.red,
                      shadows: [Shadow(color: Colors.black38, blurRadius: 4)]),
                ),
              ),
            ),
            Positioned(
              right: 12,
              bottom: 36,
              child: FloatingActionButton.extended(
                heroTag: 'mapMyLocation',
                onPressed: _locating ? null : _useMyLocation,
                backgroundColor: Colors.white,
                foregroundColor: AppColors.teal2,
                icon: _locating
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.my_location_rounded),
                label: const Text('Use my current location'),
              ),
            ),
          ]),
        ),
        Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: AppColors.line)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Selected location', style: t.labelMedium?.copyWith(color: AppColors.muted)),
                const SizedBox(height: 4),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.place_rounded, color: AppColors.teal, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _resolving
                          ? 'Finding address…'
                          : (_address.isNotEmpty
                              ? _address
                              : '${_centre.latitude.toStringAsFixed(5)}, ${_centre.longitude.toStringAsFixed(5)}'),
                      style: t.titleSmall,
                    ),
                  ),
                ]),
                const SizedBox(height: 4),
                Text('Move the map so the pin sits exactly on your door.',
                    style: t.bodySmall?.copyWith(color: AppColors.muted)),
                const SizedBox(height: 12),
                FilledButton(onPressed: _confirm, child: Text(widget.confirmText)),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}
