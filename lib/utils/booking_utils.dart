import 'dart:math';

/// Helpers for reading MySQL booking rows (bookings.php `get`,
/// customers.php `bookings`). Rows are snake_case and numbers may arrive as
/// strings.
class BookingUtils {
  static String str(Map<String, dynamic> b, List<String> keys, [String fallback = '']) {
    for (final k in keys) {
      final v = b[k]?.toString() ?? '';
      if (v.isNotEmpty && v != 'null') return v;
    }
    return fallback;
  }

  static double? dbl(dynamic v) {
    final d = double.tryParse(v?.toString() ?? '');
    return (d == null || d == 0) ? null : d;
  }

  static int amount(Map<String, dynamic> b) {
    for (final k in ['confirmed_price', 'final_price', 'quoted_price', 'amount']) {
      final v = num.tryParse(b[k]?.toString() ?? '');
      if (v != null && v > 0) return v.toInt();
    }
    return 0;
  }

  /// Start OTP — shown while the booking is 'confirmed'. The server stores it
  /// in `start_otp` (generate_start_otp) and/or `otp` (confirm_price).
  static String startOtp(Map<String, dynamic> b) =>
      (b['status']?.toString() ?? '') == 'confirmed' ? str(b, ['start_otp', 'otp']) : '';

  /// Completion OTP — present once the provider requests it on an active job.
  static String completionOtp(Map<String, dynamic> b) =>
      (b['status']?.toString() ?? '') == 'active' ? str(b, ['completion_otp']) : '';

  /// Provider position, only while confirmed/active and when known.
  static ({double lat, double lng})? providerPos(Map<String, dynamic> b) {
    final st = b['status']?.toString() ?? '';
    if (st != 'confirmed' && st != 'active') return null;
    final lat = dbl(b['provider_lat']);
    final lng = dbl(b['provider_lng']);
    if (lat == null || lng == null) return null;
    return (lat: lat, lng: lng);
  }

  /// Distance provider → service address in km (server `distance_km`, else
  /// computed locally).
  static double? providerDistanceKm(Map<String, dynamic> b) {
    final p = providerPos(b);
    if (p == null) return null;
    final server = double.tryParse(b['distance_km']?.toString() ?? '');
    if (server != null) return server;
    final lat = dbl(b['lat']);
    final lng = dbl(b['lng']);
    if (lat == null || lng == null) return null;
    return haversineKm(p.lat, p.lng, lat, lng);
  }

  /// Google Maps directions from the provider to the service address (falls
  /// back to just pinning the provider). Opens in the Maps app or browser.
  static Uri? providerMapsUri(Map<String, dynamic> b) {
    final p = providerPos(b);
    if (p == null) return null;
    final lat = dbl(b['lat']);
    final lng = dbl(b['lng']);
    if (lat == null || lng == null) {
      return Uri.parse('https://www.google.com/maps/search/?api=1&query=${p.lat},${p.lng}');
    }
    return Uri.parse('https://www.google.com/maps/dir/?api=1'
        '&origin=${p.lat},${p.lng}&destination=$lat,$lng&travelmode=driving');
  }

  static double haversineKm(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLng = (lng2 - lng1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) * cos(lat2 * pi / 180) * sin(dLng / 2) * sin(dLng / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }
}
