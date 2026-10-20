import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────
// ApiService — every data call goes to the HamaraService PHP API
// (MySQL is the only data store). Firebase is used only for Auth
// (ID token sent as Bearer) and FCM push.
// Contract: hamaraservice-website/docs/API_CONTRACT.md
// ─────────────────────────────────────────────────────────────

/// Error returned by the API (or a network failure). [message] is safe to
/// show to the user.
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  const ApiException(this.message, [this.statusCode]);
  @override
  String toString() => message;
}

class ApiService {
  static const String _base = 'https://hamaraservice.com/api';
  static const Duration _timeout = Duration(seconds: 20);

  // ── Firebase ID token (attached to every request) ───────
  static Future<String> _token() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return '';
    try {
      return await user.getIdToken() ?? '';
    } catch (_) {
      return '';
    }
  }

  static Future<Map<String, String>> _headers() async {
    final token = await _token();
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  /// Parses a response. Returns `data` on success, throws [ApiException]
  /// with the server's `error` message otherwise.
  static dynamic _handle(http.Response resp) {
    dynamic decoded;
    try {
      decoded = jsonDecode(resp.body);
    } catch (_) {
      throw ApiException(
          'Server error (HTTP ${resp.statusCode}). Please try again.',
          resp.statusCode);
    }
    if (decoded is! Map) {
      throw ApiException(
          'Unexpected server response (HTTP ${resp.statusCode}).',
          resp.statusCode);
    }
    if (decoded['success'] == true && resp.statusCode < 400) {
      return decoded['data'];
    }
    final msg = decoded['error']?.toString() ?? '';
    throw ApiException(
        msg.isNotEmpty ? msg : 'Request failed (HTTP ${resp.statusCode}).',
        resp.statusCode);
  }

  static Future<dynamic> _send(Future<http.Response> Function() call) async {
    try {
      final resp = await call().timeout(_timeout);
      return _handle(resp);
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw const ApiException('The server took too long to respond. Please try again.');
    } catch (_) {
      throw const ApiException('Network error. Check your internet connection.');
    }
  }

  static Future<dynamic> _get(String endpoint,
      {Map<String, String>? params}) async {
    var uri = Uri.parse('$_base/$endpoint');
    if (params != null) uri = uri.replace(queryParameters: params);
    final headers = await _headers();
    return _send(() => http.get(uri, headers: headers));
  }

  static Future<dynamic> _post(String endpoint, Map<String, dynamic> body,
      {Map<String, String>? params}) async {
    var uri = Uri.parse('$_base/$endpoint');
    if (params != null) uri = uri.replace(queryParameters: params);
    final headers = await _headers();
    return _send(() => http.post(uri, headers: headers, body: jsonEncode(body)));
  }

  static Map<String, dynamic> _map(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  static List<Map<String, dynamic>> _list(dynamic v) => v is List
      ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : <Map<String, dynamic>>[];

  // ── CUSTOMERS ───────────────────────────────────────────

  /// Upsert the customer profile (customers.php?action=register).
  /// Must be called after every login method; empty fields are not
  /// overwritten by the server.
  static Future<Map<String, dynamic>> registerCustomer({
    String? name,
    String? phone,
    String? email,
    String? gender,
    String? address,
    String? city,
    double? lat,
    double? lng,
    String? fcmToken,
    String authMethod = 'email',
  }) async {
    final data = await _post('customers.php', {
      if (name != null && name.isNotEmpty) 'name': name,
      if (phone != null && phone.isNotEmpty) 'phone': phone,
      if (email != null && email.isNotEmpty) 'email': email,
      if (gender != null && gender.isNotEmpty) 'gender': gender,
      if (address != null && address.isNotEmpty) 'address': address,
      if (city != null && city.isNotEmpty) 'city': city,
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
      if (fcmToken != null && fcmToken.isNotEmpty) 'fcm_token': fcmToken,
      'auth_method': authMethod,
    }, params: {'action': 'register'});
    final customer = _map(data);
    if (customer.isNotEmpty) await saveCurrentUser(customer);
    return customer;
  }

  /// Makes sure a customer row exists for the signed-in Firebase user and
  /// that the current FCM token is stored. Throws [ApiException] on failure.
  static Future<Map<String, dynamic>> ensureCustomerProfile({
    String? name,
    String? phone,
    String? authMethod,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw const ApiException('Please sign in first.', 401);
    String? fcm;
    try {
      fcm = await FirebaseMessaging.instance.getToken();
    } catch (_) {}
    String method = authMethod ?? '';
    if (method.isEmpty) {
      final isGoogle =
          user.providerData.any((p) => p.providerId == 'google.com');
      method = isGoogle ? 'google' : 'email';
    }
    return registerCustomer(
      name: (name != null && name.isNotEmpty) ? name : (user.displayName ?? ''),
      phone: phone,
      email: user.email ?? '',
      fcmToken: fcm,
      authMethod: method,
    );
  }

  /// Own customer profile, or null if it does not exist yet.
  static Future<Map<String, dynamic>?> getCustomer() async {
    try {
      final data = await _get('customers.php', params: {'action': 'get'});
      final m = _map(data);
      return m.isEmpty ? null : m;
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// Update profile fields (name, phone, gender, address, city, lat, lng).
  static Future<Map<String, dynamic>> updateCustomer(
      Map<String, dynamic> data) async {
    final res = await _post('customers.php', data, params: {'action': 'update'});
    return _map(res);
  }

  /// Save FCM token (customers.php?action=fcm).
  static Future<void> saveFcmToken(String fcmToken) async {
    if (fcmToken.isEmpty) return;
    await _post('customers.php', {'fcm_token': fcmToken},
        params: {'action': 'fcm'});
  }

  /// Delete the account (customers.php?action=delete): the server
  /// anonymises the profile and cancels a still-searching booking.
  /// 409 when a booking is in progress.
  static Future<void> deleteAccount() async {
    await _post('customers.php', const {}, params: {'action': 'delete'});
  }

  /// Website login (customers.php?action=web_login) — used only to get the
  /// same error message as the web (NOT_REGISTERED / incorrect password) and
  /// to move an older web-only account onto Firebase so the app can sign in.
  /// Returns normally on success; throws [ApiException] with the server text.
  static Future<void> webLogin(String email, String password) async {
    final uri = Uri.parse('$_base/customers.php?action=web_login');
    await _send(() => http.post(uri,
        headers: const {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode({'email': email, 'password': password})));
  }

  // ── SERVICES ────────────────────────────────────────────

  /// Provider price ranges per service:
  /// {svcId: {min, max, provider_count, admin_prices?}}
  static Future<Map<String, dynamic>> getServicePriceRanges(
      {String? city}) async {
    final params = <String, String>{'action': 'price_ranges'};
    if (city != null && city.isNotEmpty) params['city'] = city;
    return _map(await _get('services.php', params: params));
  }

  /// Reference prices for one service: {groupKey: {optionKey: price}}
  static Future<Map<String, dynamic>> getServicePrices(String svcId) async {
    return _map(await _get('services.php',
        params: {'action': 'prices', 'id': svcId}));
  }

  // ── PROVIDERS (public) ──────────────────────────────────

  /// Online, approved providers offering [svcId] within [radiusKm] of the
  /// booking (providers.php?action=nearby). Each row: id, name, rating
  /// (string), distance_km (number or null), min_price, max_price.
  static Future<List<Map<String, dynamic>>> getNearbyProviders({
    required String svcId,
    required double radiusKm,
    double lat = 0,
    double lng = 0,
    String city = '',
  }) async {
    return _list(await _get('providers.php', params: {
      'action': 'nearby',
      'svc_id': svcId,
      'radius': radiusKm.toStringAsFixed(0),
      'lat': lat.toString(),
      'lng': lng.toString(),
      'city': city,
    }));
  }

  // ── SITE SETTINGS (public) ──────────────────────────────

  static Map<String, dynamic>? _siteConfig;

  /// Public site settings (site.php?action=config): support_whatsapp,
  /// support_email, customer_app_url, provider_app_url, web_login_mode.
  /// Cached for the app session; returns {} when unreachable.
  static Future<Map<String, dynamic>> getSiteConfig() async {
    final cached = _siteConfig;
    if (cached != null) return cached;
    try {
      final cfg = _map(await _get('site.php', params: {'action': 'config'}));
      _siteConfig = cfg;
      return cfg;
    } on ApiException {
      return <String, dynamic>{};
    }
  }

  /// Service ids the admin switched off in the live catalog
  /// (hamaraservice.com/catalog.json, same file the web app reads).
  /// Empty when unreachable.
  static Future<Set<String>> getInactiveServices() async {
    try {
      final resp = await http
          .get(Uri.parse('https://hamaraservice.com/catalog.json'))
          .timeout(_timeout);
      final d = jsonDecode(resp.body);
      if (d is! List) return <String>{};
      return d
          .whereType<Map>()
          .where((x) => x['status']?.toString() == 'inactive')
          .map((x) => x['id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
    } catch (_) {
      return <String>{};
    }
  }

  // ── BOOKINGS ────────────────────────────────────────────

  /// Create a booking. Returns the new booking id.
  /// 409 → customer already has an open booking; 412 → no profile.
  static Future<String> createBooking({
    required String svcId,
    required String svcName,
    String svcIcon = '',
    required String address,
    String landmark = '',
    String city = '',
    double lat = 0,
    double lng = 0,
    required String slotDate,
    required String slotTime,
    String notes = '',
    required String contactName,
    required String contactPhone,
    int estPrice = 0,
    List<String> summary = const [],
  }) async {
    final data = await _post('bookings.php', {
      'svc_id': svcId,
      'svc_name': svcName,
      'svc_icon': svcIcon,
      'address': address,
      'landmark': landmark,
      'city': city,
      'lat': lat,
      'lng': lng,
      'slot_date': slotDate,
      'slot_time': slotTime,
      'notes': notes,
      'contact_name': contactName,
      'contact_phone': contactPhone,
      'est_price': estPrice,
      'summary': summary,
    }, params: {'action': 'create'});
    final id = _map(data)['id']?.toString() ?? '';
    if (id.isEmpty) throw const ApiException('Booking could not be created.');
    return id;
  }

  /// `id`/`role` for "my …" requests: the current API takes them from the
  /// token, the previous API version requires them explicitly.
  static Map<String, String> _mine(String action) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return {
      'action': action,
      if (uid.isNotEmpty) 'id': uid,
      'role': 'customer',
    };
  }

  /// Booking details (snake_case fields, see contract).
  static Future<Map<String, dynamic>> getBooking(String id) async {
    return _map(await _get('bookings.php', params: {'action': 'get', 'id': id}));
  }

  /// Current open booking for the signed-in customer (includes
  /// completed-but-unpaid), or null.
  static Future<Map<String, dynamic>?> getActiveBooking() async {
    final data = await _get('bookings.php', params: _mine('active'));
    if (data == null) return null;
    final m = _map(data);
    return m.isEmpty ? null : m;
  }

  /// Booking history, newest first. `other_party` = provider name.
  static Future<List<Map<String, dynamic>>> getBookingHistory() async {
    return _list(await _get('bookings.php', params: _mine('history')));
  }

  static Future<Map<String, dynamic>> _bookingAction(
      String action, String bookingId,
      [Map<String, dynamic> extra = const {}]) async {
    return _map(await _post('bookings.php', {'booking_id': bookingId, ...extra},
        params: {'action': action}));
  }

  /// Counter offer (status must be price_quoted; counter < quote).
  static Future<Map<String, dynamic>> negotiate(
          String bookingId, int counterPrice) =>
      _bookingAction('negotiate', bookingId, {'counter_price': counterPrice});

  /// Accept the quote / final offer. The server decides the price.
  /// [shownPrice] is ignored by the current API (it uses its own stored
  /// price); the previous API version requires it.
  static Future<Map<String, dynamic>> confirmPrice(String bookingId,
          {int shownPrice = 0}) =>
      _bookingAction('confirm_price', bookingId,
          {if (shownPrice > 0) 'confirmed_price': shownPrice});

  /// Decline the provider's quote → back to searching.
  static Future<Map<String, dynamic>> declineQuote(String bookingId) =>
      _bookingAction('decline', bookingId);

  /// Release current provider and search for another → searching.
  static Future<Map<String, dynamic>> searchAnother(String bookingId) =>
      _bookingAction('search_another', bookingId);

  /// Cancel (allowed before the job is active).
  static Future<Map<String, dynamic>> cancelBooking(
          String bookingId, String reason) =>
      _bookingAction('cancel', bookingId, {'reason': reason});

  /// Start OTP for a confirmed booking (normally already in `get`).
  static Future<Map<String, dynamic>> generateStartOtp(String bookingId) =>
      _bookingAction('generate_start_otp', bookingId);

  /// Razorpay order for a completed, unpaid booking:
  /// {order_id, amount (paise), currency, key_id, booking_id}
  static Future<Map<String, dynamic>> createOrder(String bookingId) =>
      _bookingAction('create_order', bookingId);

  /// Verify Razorpay payment on the server and mark the booking paid.
  static Future<Map<String, dynamic>> razorpayConfirm({
    required String bookingId,
    required String orderId,
    required String paymentId,
    required String signature,
  }) =>
      _bookingAction('razorpay_confirm', bookingId, {
        'razorpay_order_id': orderId,
        'razorpay_payment_id': paymentId,
        'razorpay_signature': signature,
      });

  /// Rate a completed booking (once).
  static Future<Map<String, dynamic>> submitReview({
    required String bookingId,
    required int rating,
    String review = '',
  }) =>
      _bookingAction('review', bookingId, {'rating': rating, 'review': review});

  // ── LOCAL STORAGE (SharedPreferences) ───────────────────

  static Future<void> saveCurrentUser(Map<String, dynamic> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('hs_customer', jsonEncode(data));
    } catch (_) {
      // cache only — safe to ignore
    }
  }

  static Future<Map<String, dynamic>?> getCachedUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final s = prefs.getString('hs_customer');
      if (s == null) return null;
      return Map<String, dynamic>.from(jsonDecode(s) as Map);
    } catch (_) {
      return null;
    }
  }

  /// Remove everything this app stored locally (called on sign-out).
  static Future<void> clearLocalData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } catch (_) {}
  }
}
