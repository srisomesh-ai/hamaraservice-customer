import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../firebase_options.dart';
import '../screens/booking/booking_status_screen.dart';
import 'api_service.dart';

// ─────────────────────────────────────────────────────────────
// Push notifications. The backend sends DATA-ONLY FCM messages
// ({event, bookingId, title, body}), so the app always displays them
// itself — in the foreground (onMessage) and in the background /
// terminated state (onBackgroundMessage). Taps open the booking.
// ─────────────────────────────────────────────────────────────

/// Global navigator so notification taps can open screens.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

const String _channelId = 'hamaraservice_high_priority';
const String _channelName = 'HamaraService Alerts';
const String _channelDesc = 'Booking and payment notifications';

const AndroidNotificationChannel _channel = AndroidNotificationChannel(
  _channelId,
  _channelName,
  description: _channelDesc,
  importance: Importance.max,
  playSound: true,
  enableVibration: true,
);

const NotificationDetails _details = NotificationDetails(
  android: AndroidNotificationDetails(
    _channelId,
    _channelName,
    channelDescription: _channelDesc,
    importance: Importance.max,
    priority: Priority.high,
    playSound: true,
    enableVibration: true,
    visibility: NotificationVisibility.public,
  ),
);

const InitializationSettings _initSettings = InitializationSettings(
  android: AndroidInitializationSettings('@mipmap/ic_launcher'),
);

/// Shows a local notification for a data message. Returns false when there
/// is nothing to show.
Future<bool> _showFromMessage(
    FlutterLocalNotificationsPlugin plugin, RemoteMessage message) async {
  final data = message.data;
  final title = (data['title'] ?? message.notification?.title ?? '').toString();
  final body = (data['body'] ?? message.notification?.body ?? '').toString();
  if (title.isEmpty && body.isEmpty) return false;
  final bookingId = (data['bookingId'] ?? '').toString();
  // One notification slot per booking (newer updates replace older ones).
  final id = bookingId.isNotEmpty
      ? bookingId.hashCode & 0x7fffffff
      : (message.messageId ?? DateTime.now().toIso8601String()).hashCode &
          0x7fffffff;
  await plugin.show(id, title.isEmpty ? 'HamaraService' : title, body, _details,
      payload: bookingId);
  return true;
}

/// Background / terminated handler — runs in its own isolate.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // If the message carries a `notification` block Android already shows it;
  // displaying it again would duplicate it.
  if (message.notification != null) return;
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (_) {}
  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(_initSettings);
  await plugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(_channel);
  await _showFromMessage(plugin, message);
}

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static String? _pendingBookingId;
  static bool _homeReady = false;
  static bool _initialised = false;

  /// Call once from main() after Firebase.initializeApp.
  static Future<void> init() async {
    if (_initialised) return;
    _initialised = true;

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    await _plugin.initialize(
      _initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse r) {
        _openBooking(r.payload);
      },
    );

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    try {
      await FirebaseMessaging.instance.requestPermission(
          alert: true, badge: true, sound: true);
    } catch (_) {}

    // Foreground: Android never shows FCM messages itself while the app is
    // in the foreground, so always display locally.
    FirebaseMessaging.onMessage.listen((RemoteMessage m) async {
      try {
        await _showFromMessage(_plugin, m);
      } catch (_) {}
    });

    // Taps on system-displayed (notification-block) messages.
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage m) {
      _openBooking(m.data['bookingId']?.toString());
    });
    try {
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) _openBooking(initial.data['bookingId']?.toString());
    } catch (_) {}

    // App launched by tapping one of our local notifications.
    try {
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp == true) {
        _openBooking(launch?.notificationResponse?.payload);
      }
    } catch (_) {}

    // Keep the server's FCM token current.
    FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
      if (FirebaseAuth.instance.currentUser == null) return;
      try {
        await ApiService.saveFcmToken(token);
      } catch (_) {
        // will be re-sent on next login / app start
      }
    });
  }

  /// Saves the current FCM token for the signed-in customer.
  static Future<void> syncToken() async {
    if (FirebaseAuth.instance.currentUser == null) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) {
        await ApiService.saveFcmToken(token);
      }
    } catch (_) {
      // retried on next start / token refresh
    }
  }

  /// Called by HomeScreen once it is on screen; opens a booking that was
  /// tapped before the UI was ready.
  static void markHomeReady() {
    _homeReady = true;
    final pending = _pendingBookingId;
    _pendingBookingId = null;
    if (pending != null) _openBooking(pending);
  }

  static void _openBooking(String? bookingId) {
    if (bookingId == null || bookingId.isEmpty) return;
    if (FirebaseAuth.instance.currentUser == null) return;
    final nav = navigatorKey.currentState;
    if (!_homeReady || nav == null) {
      _pendingBookingId = bookingId;
      return;
    }
    if (BookingStatusScreen.openBookingId == bookingId) return; // already open
    nav.push(MaterialPageRoute(
        builder: (_) => BookingStatusScreen(bookingId: bookingId)));
  }
}
