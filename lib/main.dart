import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'firebase_options.dart';
import 'utils/theme.dart';
import 'screens/splash_screen.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Request permission — critical for iOS
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      criticalAlert: true,
      announcement: true,
      provisional: false,
    );
    print('FCM permission: \${settings.authorizationStatus}');

    await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
      alert: true, badge: true, sound: true);

    // Handle foreground messages — show overlay banner when app is open
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      final n = message.notification;
      if (n == null) return;
      // Use flutter_local_notifications to show heads-up even when app is open
      try {
        final flnp = FlutterLocalNotificationsPlugin();
        await flnp.show(
          message.hashCode,
          n.title ?? 'HamaraService',
          n.body ?? '',
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'hamaraservice_high_priority',
              'HamaraService Alerts',
              channelDescription: 'Booking and payment notifications',
              importance: Importance.max,
              priority: Priority.high,
              playSound: true,
              enableVibration: true,
              visibility: NotificationVisibility.public,
            ),
          ),
        );
      } catch (_) {}
    });

    // Handle notification tap from background
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('Notification tapped: \${message.data}');
    });

    // App opened from terminated via notification
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      print('Opened from notification: \${initialMessage.data}');
    }

    // Save FCM token on launch + on login
    Future<void> saveFcmToken(String uid) async {
      try {
        final token = await FirebaseMessaging.instance.getToken();
        if (token != null && token.isNotEmpty) {
          await FirebaseDatabase.instance.ref('customers/\$uid/fcmToken').set(token);
        }
      } catch (_) {}
    }

    // Save immediately if user already logged in (handles guest who later logged in)
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      saveFcmToken(currentUser.uid);
      _requestAndSaveLocation(currentUser.uid);
    }

    // Also save on future auth state changes (new login)
    FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (user != null) {
        saveFcmToken(user.uid);
        _requestAndSaveLocation(user.uid);
      }
    });
    // Refresh token
    FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseDatabase.instance
            .ref('customers/\${user.uid}/fcmToken').set(token);
      }
    });

  } catch (_) {}

  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const CustomerApp());
}

Future<void> _requestAndSaveLocation(String uid) async {
  try {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) return;
    final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high);
    String city = '';
    try {
      final placemarks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
      if (placemarks.isNotEmpty) {
        city = placemarks.first.locality ??
            placemarks.first.subAdministrativeArea ?? '';
      }
    } catch (_) {}
    await FirebaseDatabase.instance.ref('customers/\$uid').update({
      'lat': pos.latitude,
      'lng': pos.longitude,
      if (city.isNotEmpty) 'city': city,
    });
  } catch (_) {}
}

class CustomerApp extends StatelessWidget {
  const CustomerApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HamaraService',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      home: const SplashScreen(),
    );
  }
}