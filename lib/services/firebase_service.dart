import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'api_service.dart';

/// Firebase is used ONLY for authentication (and FCM, see
/// notification_service.dart). All data lives in the PHP/MySQL API.
class FirebaseService {
  static final _auth = FirebaseAuth.instance;
  static final _googleSignIn = GoogleSignIn();

  static User? get currentUser => _auth.currentUser;
  static Stream<User?> get authChanges => _auth.authStateChanges();

  static Future<UserCredential?> signInWithGoogle() async {
    final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
    if (googleUser == null) return null; // user cancelled
    final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    return _auth.signInWithCredential(credential);
  }

  /// Signs out of Firebase + Google and clears all locally stored data.
  static Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } catch (_) {
      // not signed in with Google
    }
    await _auth.signOut();
    await ApiService.clearLocalData();
  }
}
