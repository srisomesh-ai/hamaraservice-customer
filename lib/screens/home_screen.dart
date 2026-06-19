import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../utils/theme.dart';
import 'test_console_screen.dart';
import 'login_screen.dart';
import 'location_screen.dart';
import 'booking/service_detail_screen.dart';
import 'services/service_screen.dart';
import 'dashboard/my_bookings_screen.dart';
import 'dashboard/booking_history_screen.dart';
import 'dashboard/profile_screen.dart';
import 'dashboard/completed_bookings_screen.dart';
import 'dashboard/cancelled_bookings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  int _currentIndex = 0;
  late TabController _bookingTabCtrl;
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  String _city = 'Your City';
  int _testTapCount = 0;
  DateTime? _lastTap;
  User? _user;
  int _selectedCat = 0;

  // App-level OTP listener — fires regardless of which tab is active
  StreamSubscription? _appOtpListener;
  bool _showAppOtpPopup = false;
  String _appOtpCode = '';
  String _appOtpService = '';
  String _appOtpBookingId = '';
  Map<String, dynamic> _appOtpBooking = {};

  final List<Map<String, dynamic>> _categories = [
    {'icon': '🏠', 'label': 'All'},
    {'icon': '🧹', 'label': 'Cleaning'},
    {'icon': '🔧', 'label': 'Repairs'},
    {'icon': '👶', 'label': 'Care'},
    {'icon': '💆', 'label': 'Beauty'},
    {'icon': '🚗', 'label': 'Vehicle'},
    {'icon': '❤️', 'label': 'Health'},
  ];

  final List<Map<String, dynamic>> _banners = [
    {'color': 0xFF0D3D47, 'title': '₹100 OFF', 'sub': 'On your first booking', 'emoji': '🎉', 'code': 'FIRST100'},
    {'color': 0xFFB84600, 'title': 'Deep Clean', 'sub': 'Starting ₹499 only', 'emoji': '🧽', 'code': ''},
    {'color': 0xFF1a4d2e, 'title': 'AC Service', 'sub': 'Summer special offer', 'emoji': '❄️', 'code': 'AC50'},
  ];

  final List<Map<String, dynamic>> _services = [
    {'id':'SVC001','icon':'🧹','name':'House Maid','cat':'Cleaning','color':0xFFE3F2FD,'popular':true,'img':'assets/images/house-maid.jpg'},
    {'id':'SVC002','icon':'🧽','name':'Deep Cleaning','cat':'Cleaning','color':0xFFE8F5E9,'popular':true,'img':'assets/images/deep-cleaning.jpg'},
    {'id':'SVC003','icon':'🛀','name':'Bathroom Cleaning','cat':'Cleaning','color':0xFFF3E5F5,'popular':false,'img':'assets/images/bathroom-cleaning.jpg'},
    {'id':'SVC004','icon':'🍳','name':'Kitchen Cleaning','cat':'Cleaning','color':0xFFFFF8E1,'popular':false,'img':'assets/images/kitchen-cleaning.jpg'},
    {'id':'SVC005','icon':'🛋️','name':'Sofa / Carpet','cat':'Cleaning','color':0xFFE0F7FA,'popular':true,'img':'assets/images/sofa-carpet-cleaning.jpg'},
    {'id':'SVC006','icon':'🧴','name':'Laundry / Ironing','cat':'Cleaning','color':0xFFEDE7F6,'popular':false,'img':'assets/images/laundry-ironing.jpg'},
    {'id':'SVC007','icon':'❄️','name':'AC Service','cat':'Repairs','color':0xFFE3F2FD,'popular':true,'img':'assets/images/ac-service.jpg'},
    {'id':'SVC009','icon':'🔧','name':'Appliance Repair','cat':'Repairs','color':0xFFFBE9E7,'popular':false,'img':'assets/images/laundry-ironing.jpg'},
    {'id':'SVC012','icon':'⚡','name':'Electrician','cat':'Repairs','color':0xFFFFF9C4,'popular':true,'img':'assets/images/electrician.jpg'},
    {'id':'SVC011','icon':'🔧','name':'Plumber','cat':'Repairs','color':0xFFE1F5FE,'popular':true,'img':'assets/images/plumber.jpg'},
    {'id':'SVC013','icon':'🔨','name':'Carpenter','cat':'Repairs','color':0xFFEFEBE9,'popular':false,'img':'assets/images/carpenter.jpg'},
    {'id':'SVC014','icon':'🎨','name':'Painter','cat':'Repairs','color':0xFFFCE4EC,'popular':false,'img':'assets/images/painter.jpg'},
    {'id':'SVC017','icon':'🚗','name':'Car / Bike Wash','cat':'Vehicle','color':0xFFE8EAF6,'popular':true,'img':'assets/images/car-wash.jpg'},
    {'id':'SVC019','icon':'🔩','name':'Car Mechanic','cat':'Vehicle','color':0xFFECEFF1,'popular':false,'img':'assets/images/mechanic.jpg'},
    {'id':'SVC033','icon':'🚙','name':'Driver','cat':'Vehicle','color':0xFFE8F5E9,'popular':false,'img':'assets/images/driver.jpg'},
    {'id':'SVC027','icon':'👨‍⚕️','name':'Doctor Visit','cat':'Health','color':0xFFE3F2FD,'popular':true,'img':'assets/images/doctor-visit.jpg'},
    {'id':'SVC028','icon':'💉','name':'Nurse Visit','cat':'Health','color':0xFFF3E5F5,'popular':false,'img':'assets/images/nurse-visit.jpg'},
    {'id':'SVC029','icon':'🧪','name':'Lab Test','cat':'Health','color':0xFFE8F5E9,'popular':false,'img':'assets/images/lab-test.jpg'},
    {'id':'SVC026','icon':'💪','name':'Fitness Trainer','cat':'Health','color':0xFFFFF3E0,'popular':false,'img':'assets/images/fitness-trainer.jpg'},
    {'id':'SVC025','icon':'💆','name':'Massage','cat':'Beauty','color':0xFFF3E5F5,'popular':true,'img':'assets/images/massage.jpg'},
    {'id':'SVC024','icon':'💇','name':'Women Beauty','cat':'Beauty','color':0xFFFCE4EC,'popular':true,'img':'assets/images/haircut-women.jpg'},
    {'id':'SVC023','icon':'💈','name':'Men Haircut','cat':'Beauty','color':0xFFE8EAF6,'popular':false,'img':'assets/images/haircut-men.jpg'},
    {'id':'SVC030','icon':'👶','name':'Babysitter','cat':'Care','color':0xFFFFF8E1,'popular':false,'img':'assets/images/babysitter.jpg'},
    {'id':'SVC031','icon':'🧓','name':'Elderly Care','cat':'Care','color':0xFFE8F5E9,'popular':false,'img':'assets/images/elderly-care.jpg'},
    {'id':'SVC021','icon':'🐛','name':'Pest Control','cat':'Cleaning','color':0xFFEFEBE9,'popular':false,'img':'assets/images/pest-control.jpg'},
    {'id':'SVC032','icon':'🌿','name':'Gardener','cat':'Cleaning','color':0xFFE8F5E9,'popular':false,'img':'assets/images/gardener.jpg'},
    {'id':'SVC016','icon':'☀️','name':'Solar Panel','cat':'Repairs','color':0xFFFFF9C4,'popular':false,'img':'assets/images/solar-panel.jpg'},
    {'id':'SVC010','icon':'💧','name':'Water Purifier','cat':'Repairs','color':0xFFE1F5FE,'popular':false,'img':'assets/images/water-purifier.jpg'},
    {'id':'SVC015','icon':'📷','name':'CCTV','cat':'Repairs','color':0xFFECEFF1,'popular':false,'img':'assets/images/cctv.jpg'},
    {'id':'SVC034','icon':'💂','name':'Security Guard','cat':'Care','color':0xFFEEEEEE,'popular':false,'img':'assets/images/security-guard.jpg'},
    {'id':'SVC022','icon':'🏗️','name':'Civil / Mason','cat':'Repairs','color':0xFFFBE9E7,'popular':false,'img':'assets/images/civil-mason.jpg'},
  ];

  List<Map<String, dynamic>> get _filtered {
    var list = _services;
    if (_selectedCat > 0) {
      final cat = _categories[_selectedCat]['label'] as String;
      list = list.where((s) => s['cat'] == cat).toList();
    }
    if (_searchQuery.isNotEmpty) {
      list = list.where((s) =>
        s['name'].toString().toLowerCase().contains(_searchQuery.toLowerCase())).toList();
    }
    return list;
  }

  List<Map<String, dynamic>> get _topPicks =>
    _services.where((s) => s['popular'] == true).take(6).toList();

  @override
  void initState() {
    super.initState();
    _startAppOtpListener();
    _user = FirebaseAuth.instance.currentUser;
    _bookingTabCtrl = TabController(length: 3, vsync: this);
    _loadAndUpdateCity();
  }

  Future<void> _loadAndUpdateCity() async {
    // 1. Show saved city immediately
    final prefs = await SharedPreferences.getInstance();
    final savedCity = prefs.getString('user_city') ?? '';
    if (savedCity.isNotEmpty && mounted) {
      setState(() => _city = savedCity);
    }
    // 2. Also load from Firebase
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      try {
        final snap = await FirebaseDatabase.instance.ref('customers/$uid').get();
        if (snap.exists) {
          final data = Map<String, dynamic>.from(snap.value as Map);
          final city = data['city']?.toString() ?? '';
          if (city.isNotEmpty && mounted) {
            setState(() => _city = city);
            await prefs.setString('user_city', city);
          }
        }
      } catch (_) {}
    }
    // 3. Silently refresh GPS in background
    _refreshGPSLocation();
  }

  Future<void> _refreshGPSLocation() async {
    try {
      // Request permission on first launch
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium);
      String city = '';
      try {
        final placemarks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
        if (placemarks.isNotEmpty) {
          city = placemarks.first.locality ??
              placemarks.first.subAdministrativeArea ?? '';
        }
      } catch (_) {}
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        await FirebaseDatabase.instance.ref('customers/$uid').update({
          'lat': pos.latitude,
          'lng': pos.longitude,
          if (city.isNotEmpty) 'city': city,
        });
      }
      if (city.isNotEmpty && mounted) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_city', city);
        setState(() => _city = city);
        HapticFeedback.selectionClick();
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _appOtpListener?.cancel();
    _searchCtrl.dispose();
    _bookingTabCtrl.dispose();
    super.dispose();
  }

  void _startAppOtpListener() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    // Listen to job_otp filtered by customerId — fires on any tab
    _appOtpListener = FirebaseDatabase.instance
        .ref('job_otp')
        .orderByChild('customerId')
        .equalTo(uid)
        .onValue
        .listen((event) {
      if (!event.snapshot.exists || !mounted) return;
      final all = Map<String, dynamic>.from(event.snapshot.value as Map);
      for (final entry in all.entries) {
        final data = Map<String, dynamic>.from(entry.value as Map);
        final status = data['status']?.toString() ?? '';
        final otp = data['otp']?.toString() ?? '';
        final bookingId = data['bookingId']?.toString() ?? entry.key;
        if (status == 'waiting' && otp.isNotEmpty && !_showAppOtpPopup) {
          setState(() {
            _showAppOtpPopup = true;
            _appOtpCode = otp;
            _appOtpBookingId = bookingId;
            _appOtpService = data['service']?.toString() ?? '';
            _appOtpBooking = data;
          });
        } else if (status == 'verified' && _appOtpBookingId == bookingId) {
          setState(() => _showAppOtpPopup = false);
          // Load booking and navigate to payment
          FirebaseDatabase.instance.ref('bookings/$bookingId').get().then((snap) {
            if (snap.exists && mounted) {
              final booking = Map<String, dynamic>.from(snap.value as Map);
              Navigator.push(context, MaterialPageRoute(
                  builder: (_) => PaymentScreen(bookingId: bookingId, booking: booking)));
            }
          });
        }
      }
    });
  }

  Widget _buildAppOtpPopup() {
    if (!_showAppOtpPopup) return const SizedBox.shrink();
    return Stack(children: [
      // Dark overlay
      Positioned.fill(child: GestureDetector(
        onTap: () {}, // prevent dismiss by tapping outside
        child: Container(color: Colors.black.withOpacity(0.7)))),
      // OTP card
      Center(child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 40)]),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                color: AppColors.teal,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24), topRight: Radius.circular(24))),
              child: Column(children: [
                const Icon(Icons.lock_rounded, color: Colors.white, size: 40),
                const SizedBox(height: 8),
                const Text('Job Completion OTP',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
                Text('Share with provider to complete $_appOtpService',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: Colors.white70)),
              ])),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(children: [
                const Text('YOUR OTP CODE',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                    color: AppColors.muted, letterSpacing: 1)),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: _appOtpCode.split('').map((d) => Container(
                    width: 56, height: 64, margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: AppColors.bg, borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.green, width: 2)),
                    child: Center(child: Text(d,
                      style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900,
                        color: AppColors.ink))))).toList()),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.yellow.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10)),
                  child: const Row(children: [
                    Icon(Icons.info_outline_rounded, color: AppColors.yellow, size: 16),
                    SizedBox(width: 8),
                    Expanded(child: Text('Do not share this code until the work is done',
                      style: TextStyle(fontSize: 12, color: AppColors.yellow,
                        fontWeight: FontWeight.w600))),
                  ])),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => setState(() => _showAppOtpPopup = false),
                  child: const Text('Dismiss',
                    style: TextStyle(color: AppColors.muted, fontSize: 13))),
              ])),
          ])),
      )),
    ]);
  }

  void _onServiceTap(Map<String, dynamic> svc) {
    final id = svc['id']?.toString() ?? '';
    if (id.isEmpty) return;
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => ServiceScreen(svcId: id, svcData: svc)));
  }


  void _secretTap() {
    final now = DateTime.now();
    if (_lastTap != null && now.difference(_lastTap!).inSeconds > 2) {
      _testTapCount = 0;
    }
    _lastTap = now;
    _testTapCount++;
    if (_testTapCount >= 5) {
      _testTapCount = 0;
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => const TestConsoleScreen()));
    }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
        selectedItemColor: AppColors.teal,
        unselectedItemColor: AppColors.muted,
        backgroundColor: Colors.white,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.receipt_long_rounded), label: 'Bookings'),
          BottomNavigationBarItem(icon: Icon(Icons.person_rounded), label: 'Profile'),
        ],
      ),
      body: Stack(children: [
        IndexedStack(
          index: _currentIndex,
          children: [_buildHome(), _buildBookings(), _buildProfile()],
        ),
        _buildAppOtpPopup(),
      ]),
    );
  }

  Widget _buildHome() {
    return Column(
      children: [
        _topBar(),
        _categoryTabs(),
        Expanded(
          child: _searchQuery.isNotEmpty ? _searchResults() : _mainContent(),
        ),
      ],
    );
  }

  Widget _topBar() {
    return Container(
      color: AppColors.teal,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 8,
        left: 16, right: 16, bottom: 12,
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const LocationScreen()))
                .then((_) => _loadAndUpdateCity()),
              child: Row(
                children: [
                  const Icon(Icons.location_on_rounded, color: AppColors.brand, size: 20),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Text(_city, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
                          const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 18),
                        ]),
                        const Text('Tap to change location', style: TextStyle(fontSize: 11, color: Colors.white60)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _currentIndex = 2),
            child: CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.brand,
              backgroundImage: _user?.photoURL != null ? NetworkImage(_user!.photoURL!) : null,
              child: _user?.photoURL == null
                  ? Text((_user?.displayName ?? 'U')[0].toUpperCase(),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14))
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _categoryTabs() {
    return Container(
      color: AppColors.teal,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Container(
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _searchQuery = v),
                decoration: InputDecoration(
                  hintText: 'Search for services...',
                  prefixIcon: const Icon(Icons.search, color: AppColors.muted, size: 20),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, color: AppColors.muted, size: 18),
                          onPressed: () { _searchCtrl.clear(); setState(() => _searchQuery = ''); })
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  hintStyle: const TextStyle(color: AppColors.muted, fontSize: 13),
                ),
              ),
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              itemCount: _categories.length,
              itemBuilder: (_, i) {
                final sel = i == _selectedCat;
                return GestureDetector(
                  onTap: () => setState(() => _selectedCat = i),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: sel ? Colors.white : Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: sel ? Colors.white : Colors.white30),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(_categories[i]['icon'] as String, style: const TextStyle(fontSize: 14)),
                      const SizedBox(width: 6),
                      Text(_categories[i]['label'] as String,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                          color: sel ? AppColors.teal : Colors.white)),
                    ]),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _mainContent() {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _bannersSection(),
        _sectionHeader('🔥 Top Picks', 'Most booked services'),
        _topPicksRow(),
        _sectionHeader('🛠️ All Services', '${_filtered.length} available'),
        _servicesGrid(),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _searchResults() {
    if (_filtered.isEmpty) {
      return const Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.search_off_rounded, size: 48, color: AppColors.muted),
          SizedBox(height: 12),
          Text('No services found', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.ink)),
          SizedBox(height: 6),
          Text('Try a different search term', style: TextStyle(color: AppColors.muted)),
        ]),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3, childAspectRatio: 0.85, crossAxisSpacing: 12, mainAxisSpacing: 12,
      ),
      itemCount: _filtered.length,
      itemBuilder: (_, i) => _serviceCard(_filtered[i]),
    );
  }

  Widget _bannersSection() {
    return SizedBox(
      height: 130,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        itemCount: _banners.length,
        itemBuilder: (_, i) {
          final b = _banners[i];
          return Container(
            width: 260,
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Color(b['color'] as int),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(b['title'] as String,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
                const SizedBox(height: 4),
                Text(b['sub'] as String,
                  style: const TextStyle(fontSize: 12, color: Colors.white70)),
                if ((b['code'] as String).isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(6)),
                    child: Text('USE: ${b['code']}',
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white)),
                  ),
                ],
              ])),
              Text(b['emoji'] as String, style: const TextStyle(fontSize: 48)),
            ]),
          );
        },
      ),
    );
  }

  Widget _sectionHeader(String title, String sub) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink)),
        Text(sub, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
      ]),
    );
  }

  Widget _topPicksRow() {
    return SizedBox(
      height: 110,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        itemCount: _topPicks.length,
        itemBuilder: (_, i) {
          final svc = _topPicks[i];
          final img = svc['img'] as String? ?? '';
          return GestureDetector(
            onTap: () => _onServiceTap(svc),
            child: Container(
              width: 80,
              margin: const EdgeInsets.only(right: 12),
              child: Column(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: img.isNotEmpty
                      ? Image.asset(img, width: 64, height: 64, fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => _iconBox(svc, 64))
                      : _iconBox(svc, 64),
                ),
                const SizedBox(height: 6),
                Text(svc['name'] as String,
                  textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.ink)),
              ]),
            ),
          );
        },
      ),
    );
  }

  Widget _servicesGrid() {
    final list = _selectedCat == 0 ? _services : _filtered;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3, childAspectRatio: 0.85, crossAxisSpacing: 12, mainAxisSpacing: 12,
      ),
      itemCount: list.length,
      itemBuilder: (_, i) => _serviceCard(list[i]),
    );
  }

  Widget _serviceCard(Map<String, dynamic> svc) {
  final img = svc['img'] as String? ?? '';
  return GestureDetector(
    onTap: () => _onServiceTap(svc),
    child: Container(
      decoration: BoxDecoration(
        color: Color(svc['color'] as int),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Image or icon background
            img.isNotEmpty
    ? Container(
        color: Color(svc['color'] as int),
        padding: const EdgeInsets.all(12),
        child: Image.asset(img, fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => Center(child: Text(svc['icon'] as String,
            style: const TextStyle(fontSize: 40)))))
    : Container(
        color: Color(svc['color'] as int),
        child: Center(child: Text(svc['icon'] as String,
          style: const TextStyle(fontSize: 40))),
      ),
            // Dark gradient overlay at bottom
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withOpacity(0.75),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Text(
                  svc['name'] as String,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

  Widget _iconBox(Map<String, dynamic> svc, double size) {
    return Container(
      width: size == double.infinity ? double.infinity : size,
      height: size == double.infinity ? double.infinity : size,
      color: Color(svc['color'] as int),
      child: Center(
        child: Text(svc['icon'] as String,
          style: TextStyle(fontSize: size == double.infinity ? 36 : 30)),
      ),
    );
  }

  Widget _buildBookings() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Bookings'),
        backgroundColor: AppColors.teal,
        bottom: TabBar(
          controller: _bookingTabCtrl,
          indicatorColor: AppColors.brand,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: '📋 Active'),
            Tab(text: '✅ Completed'),
            Tab(text: '❌ Cancelled'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _bookingTabCtrl,
        children: const [
          MyBookingsScreen(),
          CompletedBookingsScreen(),
          CancelledBookingsScreen(),
        ],
      ),
    );
  }

  Widget _buildProfile() {
    return Scaffold(
      appBar: AppBar(title: const Text('My Profile'), backgroundColor: AppColors.teal),
      body: const ProfileScreen(),
    );
  }
}
