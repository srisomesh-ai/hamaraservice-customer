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
  static Future<Map<String,dynamic>> _get(
      String endpoint, {Map<String,String>? params}) async {
    var uri = Uri.parse('$_base/$endpoint');
    if (params != null) uri = uri.replace(queryParameters: params);
    final token = await _token();
    final resp = await http.get(uri, headers: {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    }).timeout(const Duration(seconds: 15));
    return jsonDecode(resp.body) as Map<String,dynamic>;
  }

  static Future<Map<String,dynamic>> _post(
      String endpoint, Map<String,dynamic> body,
      {Map<String,String>? params}) async {
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
    return jsonDecode(resp.body) as Map<String,dynamic>;
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
    double radius = 20,
  }) async {
    final params = {
      'action': 'nearby',
      'lat': lat.toString(),
      'lng': lng.toString(),
      'radius': radius.toString(),
      if (svcId != null) 'svc_id': svcId,
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

  /// Create a new booking
  static Future<String?> createBooking({
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
      return (res['data'] as Map)['id'] as String?;
    }
    return null;
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

  /// Cancel booking
  static Future<bool> cancelBooking(String bookingId) async {
    final res = await _post('bookings.php',
        {'booking_id': bookingId},
        params: {'action': 'cancel'});
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

  // ── LOCAL STORAGE (SharedPreferences) ───────────────────

  static Future<void> saveCurrentUser(Map<String,dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('hs_customer', jsonEncode(data));
  }

  static Future<Map<String,dynamic>?> getCachedUser() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString('hs_customer');
    if (s == null) return null;
    return jsonDecode(s) as Map<String,dynamic>;
  }

  static Future<void> clearUser() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('hs_customer');
  }

}