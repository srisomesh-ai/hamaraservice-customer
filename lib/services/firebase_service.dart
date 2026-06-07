import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

class FirebaseService {
  static final _auth = FirebaseAuth.instance;
  static final _db   = FirebaseDatabase.instance;

  // ── Auth ─────────────────────────────────────────────────────────────────
  static User? get currentUser => _auth.currentUser;
  static Stream<User?> get authChanges => _auth.authStateChanges();

  static Future<UserCredential> signInWithPhone(String verificationId, String otp) =>
      _auth.signInWithCredential(
        PhoneAuthProvider.credential(verificationId: verificationId, smsCode: otp),
      );

  static Future<void> verifyPhone({
    required String phone,
    required void Function(String verificationId) onCodeSent,
    required void Function(String error) onError,
  }) async {
    await _auth.verifyPhoneNumber(
      phoneNumber: phone,
      verificationCompleted: (cred) async => _auth.signInWithCredential(cred),
      verificationFailed: (e) => onError(e.message ?? 'Verification failed'),
      codeSent: (verificationId, _) => onCodeSent(verificationId),
      codeAutoRetrievalTimeout: (_) {},
      timeout: const Duration(seconds: 60),
    );
  }

  static Future<void> signOut() => _auth.signOut();

  // ── Database helpers ──────────────────────────────────────────────────────
  static DatabaseReference ref(String path) => _db.ref(path);

  static Future<DataSnapshot> get(String path) => _db.ref(path).get();

  static Future<void> set(String path, dynamic data) =>
      _db.ref(path).set(data);

  static Future<void> update(String path, Map<String, dynamic> data) =>
      _db.ref(path).update(data);

  static Future<void> push(String path, dynamic data) =>
      _db.ref(path).push().set(data);

  static Stream<DatabaseEvent> stream(String path) =>
      _db.ref(path).onValue;

  // ── User profile ──────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>?> getUserProfile(String uid) async {
    final snap = await get('customers/$uid');
    if (!snap.exists) return null;
    return Map<String, dynamic>.from(snap.value as Map);
  }

  static Future<void> saveUserProfile(String uid, Map<String, dynamic> data) =>
      set('customers/$uid', {...data, 'updatedAt': DateTime.now().toIso8601String()});

  // ── Bookings ──────────────────────────────────────────────────────────────
  static Future<String> createBooking(Map<String, dynamic> data) async {
    final ref = _db.ref('bookings').push();
    await ref.set({...data, 'id': ref.key, 'createdAt': DateTime.now().toIso8601String()});
    return ref.key!;
  }

  static Stream<DatabaseEvent> watchBooking(String bookingId) =>
      stream('bookings/$bookingId');

  static Future<List<Map<String, dynamic>>> getUserBookings(String uid) async {
    final snap = await get('bookings');
    if (!snap.exists) return [];
    final all = Map<String, dynamic>.from(snap.value as Map);
    return all.values
        .map((v) => Map<String, dynamic>.from(v as Map))
        .where((b) => b['customerId'] == uid)
        .toList()
      ..sort((a, b) => (b['createdAt'] ?? '').compareTo(a['createdAt'] ?? ''));
  }

  // ── Services catalog ──────────────────────────────────────────────────────
  static Future<Map<String, dynamic>?> getServicePrices(String svcId) async {
    final snap = await get('hs_service_prices/$svcId');
    if (!snap.exists) return null;
    return Map<String, dynamic>.from(snap.value as Map);
  }
}
