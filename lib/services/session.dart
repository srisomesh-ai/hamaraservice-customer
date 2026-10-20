import 'package:firebase_auth/firebase_auth.dart';

/// Safe access to the signed-in Firebase user. Returns null when Firebase
/// is not initialised (e.g. startup failed offline, or widget tests).
class Session {
  static User? get user {
    try {
      return FirebaseAuth.instance.currentUser;
    } catch (_) {
      return null;
    }
  }

  static bool get signedIn => user != null;
}
