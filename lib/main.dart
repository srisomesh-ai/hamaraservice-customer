import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'firebase_options.dart';
import 'utils/theme.dart';
import 'screens/splash_screen.dart';

// Global notification plugin instance
final FlutterLocalNotificationsPlugin flnp = FlutterLocalNotificationsPlugin();

// Notification channel details
const _channel = AndroidNotificationChannel(
  'hamaraservice_high_priority',
  'HamaraService Alerts',
  description: 'Booking and payment notifications',
  importance: Importance.max,
  playSound: true,
  enableVibration: true,
);

const _notifDetails = NotificationDetails(
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
);

// Background handler — fires even when app is killed
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Get title/body from data payload (since we send data-only messages)
  final title = message.data['title'] ?? 'HamaraService';
  final body  = message.data['body']  ?? 'You have a new update.';

  if (title.isEmpty && body.isEmpty) return;

  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
  );
  await plugin.show(message.hashCode, title, body, _notifDetails,
    payload: message.data['bookingId'] ?? '');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

    // Create notification channel on Android
    await flnp.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    // Init local notifications
    await flnp.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );

    // Register background handler BEFORE anything else
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Request notification permission
    await FirebaseMessaging.instance.requestPermission(
      alert: true, badge: true, sound: true,
      criticalAlert: false, provisional: false,
    );

    // Foreground notifications — read from data since we send data-only
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      final title = message.data['title'] ?? message.notification?.title ?? 'HamaraService';
      final body  = message.data['body']  ?? message.notification?.body  ?? '';
      if (title.isEmpty) return;
      try {
        await flnp.show(message.hashCode, title, body, _notifDetails,
          payload: message.data['bookingId'] ?? '');
      } catch (_) {}
    });

    // Save FCM token to Firebase
    Future<void> saveFcmToken(String uid) async {
      try {
        final token = await FirebaseMessaging.instance.getToken();
        if (token != null && token.isNotEmpty) {
          await FirebaseDatabase.instance.ref('customers/$uid/fcmToken').set(token);
        }
      } catch (_) {}
    }

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      saveFcmToken(currentUser.uid);
      _requestAndSaveLocation(currentUser.uid);
    }

    FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (user != null) {
        saveFcmToken(user.uid);
        _requestAndSaveLocation(user.uid);
      }
    });

    FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseDatabase.instance
            .ref('customers/${user.uid}/fcmToken').set(token);
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
    await FirebaseDatabase.instance.ref('customers/$uid').update({
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
