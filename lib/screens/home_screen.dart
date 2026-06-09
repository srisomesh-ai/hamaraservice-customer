import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/theme.dart';
import 'login_screen.dart';
import 'location_screen.dart';
import 'booking/service_detail_screen.dart';
import 'services/house_maid_screen.dart';
import 'dashboard/my_bookings_screen.dart';
import 'dashboard/booking_history_screen.dart';
import 'dashboard/profile_screen.dart';

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
  User? _user;
  int _selectedCat = 0;

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
    {'id':'SVC004','icon':'🍳','name':'Kitchen Cleaning','cat':'Cleaning','color':0xFFFFF8E1,'popular':false,'img':''},
    {'id':'SVC005','icon':'🛋️','name':'Sofa / Carpet','cat':'Cleaning','color':0xFFE0F7FA,'popular':true,'img':''},
    {'id':'SVC006','icon':'🧴','name':'Laundry / Ironing','cat':'Cleaning','color':0xFFEDE7F6,'popular':false,'img':''},
    {'id':'SVC007','icon':'❄️','name':'AC Service','cat':'Repairs','color':0xFFE3F2FD,'popular':true,'img':''},
    {'id':'SVC008','icon':'🔧','name':'Appliance Repair','cat':'Repairs','color':0xFFFBE9E7,'popular':false,'img':''},
    {'id':'SVC009','icon':'⚡','name':'Electrician','cat':'Repairs','color':0xFFFFF9C4,'popular':true,'img':''},
    {'id':'SVC010','icon':'🔧','name':'Plumber','cat':'Repairs','color':0xFFE1F5FE,'popular':true,'img':''},
    {'id':'SVC011','icon':'🔨','name':'Carpenter','cat':'Repairs','color':0xFFEFEBE9,'popular':false,'img':''},
    {'id':'SVC012','icon':'🎨','name':'Painter','cat':'Repairs','color':0xFFFCE4EC,'popular':false,'img':''},
    {'id':'SVC013','icon':'🚗','name':'Car / Bike Wash','cat':'Vehicle','color':0xFFE8EAF6,'popular':true,'img':''},
    {'id':'SVC014','icon':'🔩','name':'Car Mechanic','cat':'Vehicle','color':0xFFECEFF1,'popular':false,'img':''},
    {'id':'SVC015','icon':'🚙','name':'Driver','cat':'Vehicle','color':0xFFE8F5E9,'popular':false,'img':''},
    {'id':'SVC016','icon':'👨‍⚕️','name':'Doctor Visit','cat':'Health','color':0xFFE3F2FD,'popular':true,'img':''},
    {'id':'SVC017','icon':'💉','name':'Nurse Visit','cat':'Health','color':0xFFF3E5F5,'popular':false,'img':''},
    {'id':'SVC018','icon':'🧪','name':'Lab Test','cat':'Health','color':0xFFE8F5E9,'popular':false,'img':''},
    {'id':'SVC019','icon':'💪','name':'Fitness Trainer','cat':'Health','color':0xFFFFF3E0,'popular':false,'img':''},
    {'id':'SVC020','icon':'💆','name':'Massage','cat':'Beauty','color':0xFFF3E5F5,'popular':true,'img':''},
    {'id':'SVC021','icon':'💇','name':'Women Beauty','cat':'Beauty','color':0xFFFCE4EC,'popular':true,'img':''},
    {'id':'SVC022','icon':'💈','name':'Men Haircut','cat':'Beauty','color':0xFFE8EAF6,'popular':false,'img':''},
    {'id':'SVC023','icon':'👶','name':'Babysitter','cat':'Care','color':0xFFFFF8E1,'popular':false,'img':''},
    {'id':'SVC024','icon':'🧓','name':'Elderly Care','cat':'Care','color':0xFFE8F5E9,'popular':false,'img':''},
    {'id':'SVC025','icon':'🐛','name':'Pest Control','cat':'Cleaning','color':0xFFEFEBE9,'popular':false,'img':''},
    {'id':'SVC026','icon':'🌿','name':'Gardener','cat':'Cleaning','color':0xFFE8F5E9,'popular':false,'img':''},
    {'id':'SVC027','icon':'☀️','name':'Solar Panel','cat':'Repairs','color':0xFFFFF9C4,'popular':false,'img':''},
    {'id':'SVC028','icon':'💧','name':'Water Purifier','cat':'Repairs','color':0xFFE1F5FE,'popular':false,'img':''},
    {'id':'SVC029','icon':'📷','name':'CCTV','cat':'Repairs','color':0xFFECEFF1,'popular':false,'img':''},
    {'id':'SVC030','icon':'💂','name':'Security Guard','cat':'Care','color':0xFFEEEEEE,'popular':false,'img':''},
    {'id':'SVC031','icon':'🏗️','name':'Civil / Mason','cat':'Repairs','color':0xFFFBE9E7,'popular':false,'img':''},
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
    _user = FirebaseAuth.instance.currentUser;
    _bookingTabCtrl = TabController(length: 2, vsync: this);
    _loadCity();
  }

  Future<void> _loadCity() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _city = prefs.getString('user_city') ?? 'Your City');
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _bookingTabCtrl.dispose();
    super.dispose();
  }

  void _onServiceTap(Map<String, dynamic> svc) {
    if (svc['id'] == 'SVC001') {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const HouseMaidScreen()));
      return;
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => ServiceDetailScreen(service: svc)));
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
      body: IndexedStack(
        index: _currentIndex,
        children: [_buildHome(), _buildBookings(), _buildProfile()],
      ),
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
                .then((_) => _loadCity()),
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
          tabs: const [Tab(text: '📋 Active'), Tab(text: '🕑 History')],
        ),
      ),
      body: TabBarView(
        controller: _bookingTabCtrl,
        children: const [MyBookingsScreen(), BookingHistoryScreen()],
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
