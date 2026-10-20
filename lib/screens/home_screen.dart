import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../services/session.dart';
import 'booking/booking_status_screen.dart';
import 'dashboard/bookings_tab.dart';
import 'dashboard/profile_screen.dart';
import 'home/home_tab.dart';
import 'support_screen.dart';
import '../utils/theme.dart';

/// Sample data used by widget/golden tests so screens render without
/// Firebase or the network. Never set in the app.
class HomePreview {
  final String name;
  final String city;
  final Map<String, dynamic> priceRanges;
  final Map<String, dynamic>? activeBooking;
  final List<Map<String, dynamic>>? history;
  final Map<String, dynamic>? profile;
  final Map<String, dynamic> siteConfig;
  const HomePreview({
    this.name = '',
    this.city = '',
    this.priceRanges = const {},
    this.activeBooking,
    this.history,
    this.profile,
    this.siteConfig = const {},
  });
}

/// Main shell: Material 3 NavigationBar with Home / Bookings / Help /
/// Account. Each tab keeps its state (IndexedStack). Android back on a
/// non-Home tab returns to Home before leaving the app.
class HomeScreen extends StatefulWidget {
  final int initialTab;
  final HomePreview? preview;
  const HomeScreen({super.key, this.initialTab = 0, this.preview});

  static const int tabHome = 0;
  static const int tabBookings = 1;
  static const int tabHelp = 2;
  static const int tabAccount = 3;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late int _index = widget.initialTab;
  final ValueNotifier<int> _bookingsRefresh = ValueNotifier(0);
  final ValueNotifier<int> _accountRefresh = ValueNotifier(0);

  // Active booking banner + badge (bookings.php?action=active)
  Map<String, dynamic>? _active;
  Timer? _activeTimer;
  bool _activeLoading = false;

  bool get _live => widget.preview == null;

  @override
  void initState() {
    super.initState();
    _active = widget.preview?.activeBooking;
    if (_live) {
      WidgetsBinding.instance.addObserver(this);
      _loadActive();
      _startPolling();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        NotificationService.markHomeReady();
      });
    }
  }

  @override
  void dispose() {
    if (_live) WidgetsBinding.instance.removeObserver(this);
    _activeTimer?.cancel();
    _bookingsRefresh.dispose();
    _accountRefresh.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _activeTimer?.cancel();
      _activeTimer = null;
    } else if (state == AppLifecycleState.resumed) {
      _loadActive();
      _startPolling();
    }
  }

  void _startPolling() {
    _activeTimer?.cancel();
    if (!Session.signedIn) return;
    _activeTimer =
        Timer.periodic(const Duration(seconds: 15), (_) => _loadActive());
  }

  Future<void> _loadActive() async {
    if (!_live || !Session.signedIn || _activeLoading) return;
    _activeLoading = true;
    try {
      final b = await ApiService.getActiveBooking();
      if (mounted) setState(() => _active = b);
    } on ApiException catch (e) {
      debugPrint('Active booking check failed: ${e.message}');
    } finally {
      _activeLoading = false;
    }
  }

  Future<void> _openBooking(String id) async {
    if (id.isEmpty) return;
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => BookingStatusScreen(bookingId: id)));
    _loadActive();
    _bookingsRefresh.value++;
  }

  void _select(int i) {
    if (i == _index) return;
    setState(() => _index = i);
    if (i == HomeScreen.tabHome) _loadActive();
    if (i == HomeScreen.tabBookings) _bookingsRefresh.value++;
    if (i == HomeScreen.tabAccount) _accountRefresh.value++;
  }

  /// Called after sign-in / sign-out so every tab reflects the new user.
  void _onAuthChanged() {
    _startPolling();
    _loadActive();
    _bookingsRefresh.value++;
    _accountRefresh.value++;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final hasActive = _active != null;
    return PopScope(
      canPop: _index == HomeScreen.tabHome,
      onPopInvoked: (didPop) {
        if (!didPop) setState(() => _index = HomeScreen.tabHome);
      },
      child: Scaffold(
        body: IndexedStack(
          index: _index,
          children: [
            HomeTab(
              preview: widget.preview,
              activeBooking: _active,
              onOpenBooking: _openBooking,
              onOpenAccount: () => _select(HomeScreen.tabAccount),
              onAuthChanged: _onAuthChanged,
            ),
            BookingsTab(
              preview: widget.preview?.history,
              refresh: _bookingsRefresh,
              onOpenBooking: _openBooking,
              onBrowse: () => _select(HomeScreen.tabHome),
              onAuthChanged: _onAuthChanged,
            ),
            SupportScreen(preview: widget.preview?.siteConfig),
            ProfileScreen(
              preview: widget.preview?.profile,
              refresh: _accountRefresh,
              onAuthChanged: _onAuthChanged,
            ),
          ],
        ),
        bottomNavigationBar: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.line)),
          ),
          child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: _select,
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: hasActive,
                child: const Icon(Icons.receipt_long_outlined),
              ),
              selectedIcon: Badge(
                isLabelVisible: hasActive,
                child: const Icon(Icons.receipt_long_rounded),
              ),
              label: 'Bookings',
            ),
            const NavigationDestination(
              icon: Icon(Icons.support_agent_outlined),
              selectedIcon: Icon(Icons.support_agent_rounded),
              label: 'Help',
            ),
            const NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(Icons.person_rounded),
              label: 'Account',
            ),
          ],
        ),
        ),
      ),
    );
  }
}
