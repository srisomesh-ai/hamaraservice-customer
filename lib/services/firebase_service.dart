import 'package:firebase_auth/firebase_auth.dart';
import 'api_service.dart';

/// Firebase is used ONLY for authentication (e-mail + password) and FCM
/// (see notification_service.dart). All data lives in the PHP/MySQL API.
class FirebaseService {
  static final _auth = FirebaseAuth.instance;

  static User? get currentUser => _auth.currentUser;
  static Stream<User?> get authChanges => _auth.authStateChanges();

  /// Signs out of Firebase and clears all locally stored data.
  static Future<void> signOut() async {
    await _auth.signOut();
    await ApiService.clearLocalData();
  }
}
