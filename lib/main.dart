import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'utils/theme.dart';
import 'screens/splash_screen.dart';
import 'services/api_service.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _installErrorScreen();

  // Only Firebase core is awaited before the first frame (with a time limit),
  // so a slow device/network can never leave the app stuck on its launch
  // screen. Notifications + permission prompts start after the UI is visible.
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)
        .timeout(const Duration(seconds: 10));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(NotificationService.init().catchError((Object e) {
        debugPrint('Notification init failed: $e');
      }));
    });

    // Signed in from a previous session: make sure the customer profile
    // exists on the server and the FCM token is current.
    FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (user == null) return;
      try {
        await ApiService.ensureCustomerProfile();
      } catch (_) {
        // retried before booking / on next login
      }
    });
  } catch (e) {
    debugPrint('Startup init failed: $e');
  }

  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runZonedGuarded(() => runApp(const CustomerApp()),
      (e, s) => debugPrint('Uncaught: $e\n$s'));
}

/// In release builds Flutter shows a blank grey box when a screen fails to
/// build. Show the actual error instead so a screenshot tells us the cause.
void _installErrorScreen() {
  if (kDebugMode) return;
  ErrorWidget.builder = (FlutterErrorDetails d) => Material(
        color: Colors.white,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Text('Something went wrong.\n\n${d.exceptionAsString()}',
                style: const TextStyle(color: Colors.black87, fontSize: 13)),
          ),
        ),
      );
}

class CustomerApp extends StatelessWidget {
  const CustomerApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HamaraService',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      navigatorKey: navigatorKey,
      home: const SplashScreen(),
    );
  }
}
