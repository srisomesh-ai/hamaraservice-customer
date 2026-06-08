import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:google_sign_in/google_sign_in.dart';

class FirebaseService {
  static final _auth = FirebaseAuth.instance;
  static final _db = FirebaseDatabase.instance;
  static final _googleSignIn = GoogleSignIn();

  // ── Auth ──────────────────────────────────────────────────────────────────
  static User? get currentUser => _auth.currentUser;
  static Stream<User?> get authChanges => _auth.authStateChanges();

  static Future<UserCredential?> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null;
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      return await _auth.signInWithCredential(credential);
    } catch (e) {
      rethrow;
    }
  }

  static Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }

  // ── Database helpers ──────────────────────────────────────────────────────
  static DatabaseReference ref(String path) => _db.ref(path);
  static Future<DataSnapshot> get(String path) => _db.ref(path).get();
  static Future<void> set(String path, dynamic data) => _db.ref(path).set(data);
  static Future<void> update(String path, Map<String, dynamic> data) => _db.ref(path).update(data);
  static Future<void> push(String path, dynamic data) => _db.ref(path).push().set(data);
  static Stream<DatabaseEvent> stream(String path) => _db.ref(path).onValue;

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
}
