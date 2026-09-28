import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────
// ApiService — all data calls go to Hostinger MySQL
// Firebase Auth is KEPT for customer login (Google Sign-In)
// Firebase is NOT used for data storage anymore
// ─────────────────────────────────────────────────────────────

class ApiService {
  static const String _base = 'https://hamaraservice.com/api';

  // ── Get Firebase token (sent with every request) ────────
  static Future<String> _token() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return '';
    try {
      return await user.getIdToken() ?? '';
    } catch (_) { return ''; }
  }

  // ── HTTP helpers ────────────────────────────────────────
  // Never throw on bad responses: non-2xx / non-JSON / network errors all
  // come back as {success:false, error:...} so callers can show a message.
  static Map<String,dynamic> _decode(http.Response resp) {
    dynamic decoded;
    try {
      decoded = jsonDecode(resp.body);
    } catch (_) {
      decoded = null;
    }
    final ok = resp.statusCode >= 200 && resp.statusCode < 300;
    if (decoded is Map) {
      final map = Map<String,dynamic>.from(decoded);
      if (!ok) {
        map['success'] = false;
        map['error'] ??= 'Server error (${resp.statusCode})';
      }
      return map;
    }
    return {
      'success': false,
      'error': ok
          ? 'Invalid server response'
          : 'Server error (${resp.statusCode})',
    };
  }

  static Future<Map<String,dynamic>> _get(
      String endpoint, {Map<String,String>? params}) async {
    try {
      var uri = Uri.parse('$_base/$endpoint');
      if (params != null) uri = uri.replace(queryParameters: params);
      final token = await _token();
      final resp = await http.get(uri, headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      }).timeout(const Duration(seconds: 15));
      return _decode(resp);
    } catch (e) {
      return {'success': false, 'error': 'Network error. Please check your connection.'};
    }
  }

  static Future<Map<String,dynamic>> _post(
      String endpoint, Map<String,dynamic> body,
      {Map<String,String>? params}) async {
    try {
      var uri = Uri.parse('$_base/$endpoint');
      if (params != null) uri = uri.replace(queryParameters: params);
      final token = await _token();
      final resp = await http.post(uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 15));
      return _decode(resp);
    } catch (e) {
      return {'success': false, 'error': 'Network error. Please check your connection.'};
    }
  }

  // ── CUSTOMERS ───────────────────────────────────────────

  /// Called after Firebase login — saves customer to MySQL
  static Future<Map<String,dynamic>?> registerCustomer({
    String? name,
    String? phone,
    String? gender,
    String? address,
    String? city,
    double? lat,
    double? lng,
    String? fcmToken,
    String authMethod = 'email',
  }) async {
    final res = await _post('customers.php', {
      if (name    != null) 'name':    name,
      if (phone   != null) 'phone':   phone,
      if (gender  != null) 'gender':  gender,
      if (address != null) 'address': address,
      if (city    != null) 'city':    city,
      if (lat     != null) 'lat':     lat,
      if (lng     != null) 'lng':     lng,
      if (fcmToken!= null) 'fcm_token': fcmToken,
      'auth_method': authMethod,
    }, params: {'action': 'register'});
    if (res['success'] == true) return res['data'] as Map<String,dynamic>?;
    return null;
  }

  /// Get customer profile from MySQL
  static Future<Map<String,dynamic>?> getCustomer(String uid) async {
    final res = await _get('customers.php',
        params: {'action': 'get', 'id': uid});
    if (res['success'] == true) return res['data'] as Map<String,dynamic>?;
    return null;
  }

  /// Update customer profile
  static Future<bool> updateCustomer(Map<String,dynamic> data) async {
    final res = await _post('customers.php', data,
        params: {'action': 'update'});
    return res['success'] == true;
  }

  /// Save FCM token
  static Future<void> saveFcmToken(String fcmToken) async {
    await _post('customers.php', {'fcm_token': fcmToken},
        params: {'action': 'fcm'});
  }

  /// Get customer booking history
  static Future<List<Map<String,dynamic>>> getCustomerBookings(String uid) async {
    final res = await _get('customers.php',
        params: {'action': 'bookings', 'id': uid});
    if (res['success'] == true) {
      return (res['data'] as List).cast<Map<String,dynamic>>();
    }
    return [];
  }

  // ── SERVICES ────────────────────────────────────────────

  /// Get all 34 services
  static Future<List<Map<String,dynamic>>> getServices() async {
    final res = await _get('services.php', params: {'action': 'all'});
    if (res['success'] == true) {
      return (res['data'] as List).cast<Map<String,dynamic>>();
    }
    return [];
  }

  /// Get provider price ranges per service (for homepage)
  static Future<Map<String,dynamic>> getServicePriceRanges({String? city}) async {
    final params = <String,String>{'action': 'price_ranges'};
    if (city != null) params['city'] = city;
    final res = await _get('services.php', params: params);
    if (res['success'] == true) return res['data'] as Map<String,dynamic>;
    return {};
  }

  /// Get reference prices for a service
  static Future<Map<String,dynamic>> getServicePrices(String svcId) async {
    final res = await _get('services.php',
        params: {'action': 'prices', 'id': svcId});
    if (res['success'] == true) return res['data'] as Map<String,dynamic>;
    return {};
  }

  // ── PROVIDERS ───────────────────────────────────────────

  /// Get nearby providers for radar
  static Future<List<Map<String,dynamic>>> getNearbyProviders({
    required double lat,
    required double lng,
    String? svcId,
    String? city,
    double radius = 20,
  }) async {
    final params = {
      'action': 'nearby',
      'lat': lat.toString(),
      'lng': lng.toString(),
      'radius': radius.toString(),
      if (svcId != null) 'svc_id': svcId,
      if (city != null && city.isNotEmpty) 'city': city,
    };
    final res = await _get('providers.php', params: params);
    if (res['success'] == true) {
      return (res['data'] as List).cast<Map<String,dynamic>>();
    }
    return [];
  }

  /// Get provider profile
  static Future<Map<String,dynamic>?> getProvider(String id) async {
    final res = await _get('providers.php',
        params: {'action': 'get', 'id': id});
    if (res['success'] == true) return res['data'] as Map<String,dynamic>?;
    return null;
  }

  // ── BOOKINGS ────────────────────────────────────────────

  /// Create a new booking.
  /// Returns {'success': true, 'id': '<booking id>'} or
  /// {'success': false, 'error': '<message>'}.
  static Future<Map<String,dynamic>> createBooking({
    required String svcId,
    required String svcName,
    String svcIcon = '',
    required String address,
    required String city,
    double lat = 0,
    double lng = 0,
    String? slotDate,
    String? slotTime,
    String? notes,
  }) async {
    final res = await _post('bookings.php', {
      'svc_id':    svcId,
      'svc_name':  svcName,
      'svc_icon':  svcIcon,
      'address':   address,
      'city':      city,
      'lat':       lat,
      'lng':       lng,
      if (slotDate != null) 'slot_date': slotDate,
      if (slotTime != null) 'slot_time': slotTime,
      if (notes    != null) 'notes':     notes,
    }, params: {'action': 'create'});
    if (res['success'] == true) {
      final data = res['data'];
      final id = data is Map ? data['id']?.toString() : null;
      if (id != null && id.isNotEmpty) return {'success': true, 'id': id};
      return {'success': false, 'error': 'Invalid server response'};
    }
    return {
      'success': false,
      'error': res['error']?.toString() ?? res['message']?.toString() ?? 'Booking failed',
    };
  }

  /// Get booking details
  static Future<Map<String,dynamic>?> getBooking(String id) async {
    final res = await _get('bookings.php',
        params: {'action': 'get', 'id': id});
    if (res['success'] == true) return res['data'] as Map<String,dynamic>?;
    return null;
  }

  /// Get active booking for customer (for radar polling)
  static Future<Map<String,dynamic>?> getActiveBooking(String customerId) async {
    final res = await _get('bookings.php', params: {
      'action': 'active',
      'id':     customerId,
      'role':   'customer',
    });
    if (res['success'] == true && res['data'] != null) {
      return res['data'] as Map<String,dynamic>;
    }
    return null;
  }

  /// Customer sends counter price (negotiate)
  static Future<bool> negotiateBooking(String bookingId, int counterPrice) async {
    final res = await _post('bookings.php', {
      'booking_id':    bookingId,
      'counter_price': counterPrice,
    }, params: {'action': 'negotiate'});
    return res['success'] == true;
  }

  /// Customer confirms price
  static Future<Map<String,dynamic>?> confirmPrice(
      String bookingId, int price) async {
    final res = await _post('bookings.php', {
      'booking_id':      bookingId,
      'confirmed_price': price,
    }, params: {'action': 'confirm_price'});
    if (res['success'] == true) return res['data'] as Map<String,dynamic>?;
    return null;
  }

  /// Customer searches another provider
  static Future<bool> searchAnother(String bookingId) async {
    final res = await _post('bookings.php',
        {'booking_id': bookingId},
        params: {'action': 'search_another'});
    return res['success'] == true;
  }

  /// Cancel booking. [reason] is sent for the server to store if it
  /// supports it (currently ignored by bookings.php `cancel`).
  static Future<bool> cancelBooking(String bookingId, {String reason = ''}) async {
    final res = await _post('bookings.php', {
      'booking_id': bookingId,
      if (reason.isNotEmpty) 'reason': reason,
    }, params: {'action': 'cancel'});
    return res['success'] == true;
  }

  /// Submit a review for a completed booking
  static Future<bool> submitReview({
    required String bookingId,
    required String providerId,
    required int rating,
    String comment = '',
  }) async {
    final res = await _post('reviews.php', {
      'booking_id':  bookingId,
      'provider_id': providerId,
      'rating':      rating,
      'comment':     comment,
    }, params: {'action': 'submit'});
    return res['success'] == true;
  }

  /// Complete booking after successful payment
  static Future<bool> completeBooking({
    required String bookingId,
    String razorpayPaymentId = '',
    String razorpayOrderId = '',
  }) async {
    final res = await _post('bookings.php', {
      'booking_id':          bookingId,
      'razorpay_payment_id': razorpayPaymentId,
      'razorpay_order_id':   razorpayOrderId,
    }, params: {'action': 'complete'});
    return res['success'] == true;
  }

  /// Server-side Razorpay signature verification (bookings.php
  /// `razorpay_confirm`). Marks the booking paid on success.
  /// Returns the raw response map ({success, data|error}).
  static Future<Map<String,dynamic>> confirmRazorpayPayment({
    required String bookingId,
    required String razorpayOrderId,
    required String razorpayPaymentId,
    required String razorpaySignature,
  }) {
    return _post('bookings.php', {
      'booking_id':          bookingId,
      'razorpay_order_id':   razorpayOrderId,
      'razorpay_payment_id': razorpayPaymentId,
      'razorpay_signature':  razorpaySignature,
    }, params: {'action': 'razorpay_confirm'});
  }

  // ── LOCAL STORAGE (SharedPreferences) ───────────────────

  static Future<void> saveCurrentUser(Map<String,dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('hs_customer', jsonEncode(data));
  }

  static Future<Map<String,dynamic>?> getCachedUser() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString('hs_customer');
    if (s == null) return null;
    try {
      final d = jsonDecode(s);
      return d is Map ? Map<String,dynamic>.from(d) : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearUser() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('hs_customer');
  }

}