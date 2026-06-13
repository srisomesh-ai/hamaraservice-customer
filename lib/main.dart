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
    await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);
    await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(alert: true, badge: true, sound: true);

    // Save FCM token + update location whenever user logs in
    FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (user != null) {
        try {
          final token = await FirebaseMessaging.instance.getToken();
          if (token != null) {
            await FirebaseDatabase.instance.ref('customers/${user.uid}/fcmToken').set(token);
          }
        } catch (e) {}
        _updateUserLocation(user.uid);
      }
    });
  } catch (e) {}

  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const CustomerApp());
}

Future<void> _updateUserLocation(String uid) async {
  try {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return;
    final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium);
    String city = '';
    try {
      final placemarks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
      if (placemarks.isNotEmpty) {
        city = placemarks.first.locality ?? placemarks.first.subAdministrativeArea ?? '';
      }
    } catch (e) {}
    await FirebaseDatabase.instance.ref('customers/$uid').update({
      'lat': pos.latitude,
      'lng': pos.longitude,
      if (city.isNotEmpty) 'city': city,
    });
  } catch (e) {}
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
