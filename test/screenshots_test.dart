// Screenshots of the main screens at 1080×2400 (360×800 dp, DPR 3) with
// sample data — no device, Firebase or network needed.
//
//   flutter test test/screenshots_test.dart --update-goldens   # regenerate
//   flutter test                                               # compare
//
// Real fonts are loaded (Roboto + Material Icons from test/fonts, colour
// emoji from the system when available) so the PNGs look like the app.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hamaraservice_customer/screens/booking/booking_flow_screen.dart';
import 'package:hamaraservice_customer/screens/booking/booking_status_screen.dart';
import 'package:hamaraservice_customer/screens/email_otp_screen.dart';
import 'package:hamaraservice_customer/screens/home_screen.dart';
import 'package:hamaraservice_customer/screens/login_screen.dart';
import 'package:hamaraservice_customer/screens/services/service_screen.dart';
import 'package:hamaraservice_customer/services/api_service.dart';
import 'package:hamaraservice_customer/utils/booking_format.dart' as fmt;
import 'package:hamaraservice_customer/utils/service_visuals.dart';
import 'package:hamaraservice_customer/utils/theme.dart';

const _emojiFont = '/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf';

Future<void> _loadFonts() async {
  Future<ByteData> file(String p) async => ByteData.view((await File(p).readAsBytes()).buffer);
  final roboto = FontLoader('Roboto')
    ..addFont(file('test/fonts/Roboto-Regular.ttf'))
    ..addFont(file('test/fonts/Roboto-Medium.ttf'))
    ..addFont(file('test/fonts/Roboto-Bold.ttf'));
  await roboto.load();
  await (FontLoader('MaterialIcons')..addFont(file('test/fonts/MaterialIcons-Regular.otf'))).load();
  if (File(_emojiFont).existsSync()) {
    await (FontLoader('NotoColorEmoji')..addFont(file(_emojiFont))).load();
  }
}

ThemeData get _theme {
  final t = AppTheme.theme;
  // Emoji fall back to Noto Color Emoji like on Android.
  TextStyle? f(TextStyle? s) => s?.copyWith(fontFamilyFallback: const ['NotoColorEmoji']);
  final tt = t.textTheme;
  return t.copyWith(
    textTheme: tt.copyWith(
      displayLarge: f(tt.displayLarge), displayMedium: f(tt.displayMedium), displaySmall: f(tt.displaySmall),
      headlineLarge: f(tt.headlineLarge), headlineMedium: f(tt.headlineMedium), headlineSmall: f(tt.headlineSmall),
      titleLarge: f(tt.titleLarge), titleMedium: f(tt.titleMedium), titleSmall: f(tt.titleSmall),
      bodyLarge: f(tt.bodyLarge), bodyMedium: f(tt.bodyMedium), bodySmall: f(tt.bodySmall),
      labelLarge: f(tt.labelLarge), labelMedium: f(tt.labelMedium), labelSmall: f(tt.labelSmall),
    ),
  );
}

/// 20 Oct 2026, 11:05 IST — fixed so dates/durations never change.
final _now = DateTime.utc(2026, 10, 20, 5, 35);

const _ranges = {
  'SVC001': {'min': 199, 'max': 499, 'provider_count': 6},
  'SVC002': {'min': 1499, 'max': 3499, 'provider_count': 3},
  'SVC003': {'min': 299, 'max': 699, 'provider_count': 4},
  'SVC011': {'min': 149, 'max': 399, 'provider_count': 8},
  'SVC012': {'min': 149, 'max': 349, 'provider_count': 11},
  'SVC007': {'min': 399, 'max': 899, 'provider_count': 5},
};

Map<String, dynamic> _booking(String status, [Map<String, dynamic> extra = const {}]) => {
      'id': 'BK-20261020-4821',
      'svc_id': 'SVC012',
      'svc_name': 'Electrician',
      'svc_icon': '⚡',
      'status': status,
      'address': 'Flat 302, Sai Residency, Dwaraka Nagar, Visakhapatnam 530016',
      'landmark': 'Near Diamond Park',
      'city': 'Visakhapatnam',
      'slot_date': '2026-10-20',
      'slot_time': 'Now / ASAP',
      'contact_name': 'Priya Sharma',
      'contact_phone': '9876543210',
      'notes': 'Work: Fan / light installation, Points: 3–5, Property: Apartment / flat',
      'est_price': 149,
      'payment_status': 'pending',
      'created_at': '2026-10-20 10:12:44',
      ...extra,
    };

const _provider = {
  'provider_name': 'Ravi Kumar',
  'provider_rating': '4.8',
  'provider_reviews': 126,
  'distance_km': 1.6,
};

Future<void> _shot(WidgetTester tester, Widget home, String name,
    {Future<void> Function(WidgetTester)? act}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: _theme,
    home: home,
  ));
  // Decode the asset images for real (FakeAsync would never finish them).
  final ctx = tester.element(find.byType(MaterialApp));
  await tester.runAsync(() async {
    for (final p in {...ServiceVisuals.images.values, 'assets/images/rlogo.png'}) {
      await precacheImage(AssetImage(p), ctx);
    }
  });
  await tester.pump(const Duration(milliseconds: 400));
  if (act != null) await act(tester);
  await tester.pump(const Duration(milliseconds: 600));
  await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$name.png'));
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadFonts();
    fmt.clock = () => _now;
  });

  final preview = HomePreview(
    name: 'Priya',
    city: 'Visakhapatnam',
    priceRanges: _ranges,
    siteConfig: const {'support_whatsapp': '919000000000', 'support_email': 'info@hamaraservice.com'},
    profile: const {
      'id': 'k9Fq2LmX7aPz',
      'name': 'Priya Sharma',
      'email': 'priya.sharma@gmail.com',
      'phone': '9876543210',
      'address': 'Flat 302, Sai Residency, Dwaraka Nagar',
      'city': 'Visakhapatnam',
      'gender': 'female',
    },
    history: [
      _booking('price_quoted', {..._provider, 'other_party': 'Ravi Kumar', 'quoted_price': 249}),
      _booking('completed', {
        'id': 'BK-20261012-1177', 'svc_id': 'SVC001', 'svc_name': 'House Maid',
        'slot_date': '2026-10-12', 'slot_time': 'Morning (8 AM – 12 PM) · 9 AM',
        'other_party': 'Lakshmi Devi', 'amount': 349, 'payment_status': 'paid',
        'payment_method': 'online', 'rating': 5,
      }),
      _booking('cancelled', {
        'id': 'BK-20261003-0912', 'svc_id': 'SVC007', 'svc_name': 'AC Cleaning & Repair',
        'slot_date': '2026-10-03', 'cancel_reason': 'Booked by mistake', 'cancelled_by': 'customer',
      }),
    ],
  );

  testWidgets('01 home', (t) => _shot(t, HomeScreen(preview: preview), '01_home'));

  testWidgets('02 home with active booking', (t) => _shot(
      t,
      HomeScreen(
          preview: HomePreview(
              name: 'Priya',
              city: 'Visakhapatnam',
              priceRanges: _ranges,
              activeBooking: _booking('confirmed', _provider))),
      '02_home_active'));

  testWidgets('03 bookings', (t) => _shot(t, HomeScreen(preview: preview, initialTab: 1), '03_bookings'));
  testWidgets('04 help', (t) => _shot(t, HomeScreen(preview: preview, initialTab: 2), '04_help'));
  testWidgets('05 account', (t) => _shot(t, HomeScreen(preview: preview, initialTab: 3), '05_account'));

  testWidgets('06 service house maid', (t) => _shot(
        t,
        const ServiceScreen(
          svcId: 'SVC001',
          svcData: {'id': 'SVC001', 'name': 'House Maid'},
          previewPrices: {
            'task': {'dishes': 99, 'clothes': 79, 'laundry': 149},
            'sweep': {'studio': 79, '1bhk': 129, '2bhk': 199, '3bhk': 279, '4bhk': 369, 'villa': 499},
          },
          previewRange: {'min': 199, 'max': 499, 'provider_count': 6},
        ),
        '06_service_tasks',
        act: (t) async {
          await t.tap(find.text('Sweeping & Mopping'));
          await t.pump();
          await t.drag(find.byType(CustomScrollView), const Offset(0, -260));
          await t.pump();
        },
      ));

  testWidgets('07 service electrician', (t) => _shot(
        t,
        const ServiceScreen(
          svcId: 'SVC012',
          svcData: {'id': 'SVC012', 'name': 'Electrician'},
          previewPrices: {'visit': {'visit': 149}},
          previewRange: {'min': 149, 'max': 349, 'provider_count': 11},
        ),
        '07_service_visit',
      ));

  final flowPreview = {
    'address': 'Dwaraka Nagar, Visakhapatnam, 530016',
    'flat': 'Flat 302, Sai Residency',
    'name': 'Priya Sharma',
    'phone': '9876543210',
    'city': 'Visakhapatnam',
    'lat': 17.7287,
    'lng': 83.3010,
    'pinned': true,
    'window': 'Morning',
    'day': 1,
  };
  const flowSvc = {'id': 'SVC012', 'name': 'Electrician', 'icon': '⚡', 'cat': 'Home Services'};
  testWidgets('08 booking when', (t) => _shot(
      t,
      BookingFlowScreen(service: flowSvc, basePrice: 149, preview: flowPreview,
          summary: const ['Visit / Call-out Price: Visit fee (work quoted on-site)', 'Work: Fan / light installation']),
      '08_flow_when'));
  testWidgets('09 booking address', (t) => _shot(
      t,
      BookingFlowScreen(service: flowSvc, basePrice: 149, preview: flowPreview, initialStep: 1),
      '09_flow_address'));
  testWidgets('10 booking review', (t) => _shot(
      t,
      BookingFlowScreen(service: flowSvc, basePrice: 149, preview: flowPreview, initialStep: 2,
          summary: const ['Visit / Call-out Price: Visit fee (work quoted on-site)', 'Work: Fan / light installation', 'Points: 3–5']),
      '10_flow_review'));

  testWidgets('11 status searching', (t) => _shot(
      t,
      BookingStatusScreen(
        bookingId: 'BK-20261020-4821',
        preview: _booking('searching'),
        previewNearby: const [
          {'name': 'Ravi Kumar', 'rating': '4.8', 'distance_km': 1.6, 'min_price': 149, 'max_price': 349},
          {'name': 'Suresh Electricals', 'rating': '4.5', 'distance_km': 2.9, 'min_price': 199, 'max_price': 0},
          {'name': 'Anil', 'rating': '0', 'distance_km': 4.2, 'min_price': 0, 'max_price': 0},
        ],
      ),
      '11_status_searching'));

  testWidgets('12 status quoted', (t) => _shot(
      t,
      BookingStatusScreen(
          bookingId: 'BK-20261020-4821',
          preview: _booking('price_quoted', {..._provider, 'quoted_price': 249, 'quote_expires_in': 262})),
      '12_status_quoted'));

  testWidgets('12c status cancelled by admin', (t) => _shot(
      t,
      BookingStatusScreen(
          bookingId: 'BK-20261020-4821',
          preview: _booking('cancelled', {
            'cancelled_by': 'admin',
            'cancel_reason': 'Sorry, no service provider is available in your area right now. Please try again later, or call us at +91 93462 20090.',
          })),
      '12c_status_cancelled_admin'));

  testWidgets('13 status confirmed', (t) => _shot(
      t,
      BookingStatusScreen(
          bookingId: 'BK-20261020-4821',
          preview: _booking('confirmed', {
            ..._provider, 'quoted_price': 249, 'confirmed_price': 249, 'amount': 249,
            'start_otp': '4827', 'provider_phone': '9123456780',
          })),
      '13_status_confirmed'));

  testWidgets('13b status on the way', (t) => _shot(
      t,
      BookingStatusScreen(
          bookingId: 'BK-20261020-4821',
          preview: _booking('confirmed', {
            ..._provider, 'quoted_price': 249, 'confirmed_price': 249, 'amount': 249,
            'travel_started_at': '2026-10-22 10:05:00', 'provider_phone': '9123456780',
          })),
      '13b_status_on_the_way'));

  testWidgets('14 status active', (t) => _shot(
      t,
      BookingStatusScreen(
          bookingId: 'BK-20261020-4821',
          preview: _booking('active', {
            ..._provider, 'confirmed_price': 249, 'amount': 249, 'provider_phone': '9123456780',
            'started_at': '2026-10-20 10:20:00', 'completion_otp': '9051',
          })),
      '14_status_active'));

  testWidgets('15 status payment due', (t) => _shot(
      t,
      BookingStatusScreen(
          bookingId: 'BK-20261020-4821',
          preview: _booking('completed', {
            ..._provider, 'confirmed_price': 249, 'amount': 249, 'provider_phone': '9123456780',
            'started_at': '2026-10-20 10:20:00', 'completed_at': '2026-10-20 11:02:00',
            'cash_allowed': 1,
          })),
      '15_status_payment'));

  testWidgets('16 status paid rate', (t) => _shot(
      t,
      BookingStatusScreen(
          bookingId: 'BK-20261020-4821',
          preview: _booking('completed', {
            ..._provider, 'confirmed_price': 249, 'amount': 249,
            'started_at': '2026-10-20 10:20:00', 'completed_at': '2026-10-20 11:02:00',
            'payment_status': 'paid', 'payment_method': 'online', 'review_requested': 1,
          })),
      '16_status_rate',
      act: (t) async {
        await t.drag(find.byType(ListView).first, const Offset(0, -300));
        await t.pump();
      }));

  testWidgets('17 login', (t) async {
    await _shot(t, const LoginScreen(), '17_login');
    expect(find.textContaining('Google'), findsNothing);
  });

  testWidgets('18 register', (t) async {
    await _shot(t, const LoginScreen(startInRegister: true), '18_register',
        act: (t) async {
      await t.enterText(find.byType(TextField).at(0), 'Priya Sharma');
      await t.enterText(find.byType(TextField).at(1), '9876543210');
      await t.enterText(find.byType(TextField).at(2), 'priya@example.com');
      await t.enterText(find.byType(TextField).at(3), 'password1');
      FocusManager.instance.primaryFocus?.unfocus();
    });
    expect(find.text('Send OTP'), findsOneWidget);
    expect(find.textContaining('Google'), findsNothing);
  });

  // ── Email verification code (registration step 2) ──
  EmailOtpScreen otp({Future<String> Function(String)? verify, Future<int> Function()? resend}) =>
      EmailOtpScreen(
        email: 'priya@example.com',
        verify: verify ?? (c) async => 'tok-$c',
        resend: resend ?? () async => 60,
      );

  testWidgets('19 email otp', (t) async {
    await _shot(t, otp(), '19_email_otp', act: (t) async {
      await t.enterText(find.byKey(const ValueKey('otp-field')), '482');
    });
    expect(find.text('Resend in 0:59'), findsOneWidget);
    expect(find.text('Change email'), findsOneWidget);
  });

  testWidgets('20 email otp wrong code', (t) async {
    await _shot(
        t,
        otp(verify: (c) async => throw const ApiException('Incorrect code. 4 attempts left.', 400)),
        '20_email_otp_error', act: (t) async {
      await t.enterText(find.byKey(const ValueKey('otp-field')), '123456'); // auto-submits
      await t.pump();
    });
    expect(find.text('Incorrect code. 4 attempts left.'), findsOneWidget);
  });

  testWidgets('email otp: verify pops the otp_token, resend after countdown', (t) async {
    String? popped;
    var sends = 0;
    await t.pumpWidget(MaterialApp(
      theme: _theme,
      home: Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async {
                popped = await Navigator.push<String>(ctx,
                    MaterialPageRoute(builder: (_) => otp(resend: () async { sends++; return 60; })));
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    // countdown: resend disabled until 60 s have passed
    await t.tap(find.textContaining('Resend in'));
    await t.pump();
    expect(sends, 0);
    await t.pump(const Duration(seconds: 61));
    expect(find.text('Resend code'), findsOneWidget);
    await t.tap(find.text('Resend code'));
    await t.pump();
    expect(sends, 1);
    expect(find.text('A new code has been sent'), findsOneWidget);
    // too short → message, no verify
    await t.enterText(find.byKey(const ValueKey('otp-field')), '12');
    await t.tap(find.text('Verify & Create Account'));
    await t.pump();
    expect(find.text('Enter the 6-digit code from the email'), findsOneWidget);
    // letters are filtered out; 6 digits auto-submit and pop the token
    await t.enterText(find.byKey(const ValueKey('otp-field')), '65a4321');
    await t.pumpAndSettle();
    expect(popped, 'tok-654321');
  });

  testWidgets('email otp: change email pops null', (t) async {
    String? popped = 'unset';
    await t.pumpWidget(MaterialApp(
      theme: _theme,
      home: Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(
            onPressed: () async {
              popped = await Navigator.push<String>(ctx, MaterialPageRoute(builder: (_) => otp()));
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await t.tap(find.text('Change email'));
    await t.pumpAndSettle();
    expect(popped, isNull);
  });
}
