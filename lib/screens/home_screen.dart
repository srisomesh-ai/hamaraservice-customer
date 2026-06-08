import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import '../utils/theme.dart';
import '../services/firebase_service.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  User? _user;

  final List<Map<String, dynamic>> _services = [
    {'id':'SVC001','icon':'🧹','name':'House Maid','cat':'Home Cleaning','color':0xFFE3F2FD},
    {'id':'SVC002','icon':'🧽','name':'Deep Cleaning','cat':'Home Cleaning','color':0xFFE8F5E9},
    {'id':'SVC003','icon':'🛀','name':'Bathroom Cleaning','cat':'Home Cleaning','color':0xFFF3E5F5},
    {'id':'SVC004','icon':'🍳','name':'Kitchen Cleaning','cat':'Home Cleaning','color':0xFFFFF8E1},
    {'id':'SVC005','icon':'🛋️','name':'Sofa / Carpet Cleaning','cat':'Home Cleaning','color':0xFFE0F7FA},
    {'id':'SVC006','icon':'🧴','name':'Laundry / Ironing','cat':'Home Cleaning','color':0xFFEDE7F6},
    {'id':'SVC007','icon':'❄️','name':'AC Service','cat':'Appliances','color':0xFFE3F2FD},
    {'id':'SVC008','icon':'🔧','name':'Appliance Repair','cat':'Appliances','color':0xFFFBE9E7},
    {'id':'SVC009','icon':'⚡','name':'Electrician','cat':'Home Repair','color':0xFFFFF9C4},
    {'id':'SVC010','icon':'🔧','name':'Plumber','cat':'Home Repair','color':0xFFE1F5FE},
    {'id':'SVC011','icon':'🔨','name':'Carpenter','cat':'Home Repair','color':0xFFEFEBE9},
    {'id':'SVC012','icon':'🎨','name':'Painter','cat':'Home Repair','color':0xFFFCE4EC},
    {'id':'SVC013','icon':'🚗','name':'Car / Bike Wash','cat':'Vehicle','color':0xFFE8EAF6},
    {'id':'SVC014','icon':'🔩','name':'Car Mechanic','cat':'Vehicle','color':0xFFECEFF1},
    {'id':'SVC015','icon':'🚙','name':'Driver','cat':'Vehicle','color':0xFFE8F5E9},
    {'id':'SVC016','icon':'👨‍⚕️','name':'Doctor Visit','cat':'Health','color':0xFFE3F2FD},
    {'id':'SVC017','icon':'💉','name':'Nurse Visit','cat':'Health','color':0xFFF3E5F5},
    {'id':'SVC018','icon':'🧪','name':'Lab Test','cat':'Health','color':0xFFE8F5E9},
    {'id':'SVC019','icon':'💪','name':'Fitness Trainer','cat':'Health','color':0xFFFFF3E0},
    {'id':'SVC020','icon':'💆','name':'Massage','cat':'Wellness','color':0xFFF3E5F5},
    {'id':'SVC021','icon':'💇','name':'Women Beauty','cat':'Wellness','color':0xFFFCE4EC},
    {'id':'SVC022','icon':'💈','name':'Men Haircut','cat':'Wellness','color':0xFFE8EAF6},
    {'id':'SVC023','icon':'👶','name':'Babysitter','cat':'Care','color':0xFFFFF8E1},
    {'id':'SVC024','icon':'🧓','name':'Elderly Care','cat':'Care','color':0xFFE8F5E9},
    {'id':'SVC025','icon':'🐛','name':'Pest Control','cat':'Home Services','color':0xFFEFEBE9},
    {'id':'SVC026','icon':'🌿','name':'Gardener','cat':'Home Services','color':0xFFE8F5E9},
    {'id':'SVC027','icon':'☀️','name':'Solar Panel','cat':'Home Services','color':0xFFFFF9C4},
    {'id':'SVC028','icon':'💧','name':'Water Purifier','cat':'Home Services','color':0xFFE1F5FE},
    {'id':'SVC029','icon':'📷','name':'CCTV','cat':'Security','color':0xFFECEFF1},
    {'id':'SVC030','icon':'💂','name':'Security Guard','cat':'Security','color':0xFFEEEEEE},
    {'id':'SVC031','icon':'🏗️','name':'Civil / Mason','cat':'Construction','color':0xFFFBE9E7},
  ];

  List<Map<String, dynamic>> get _filtered {
    if (_searchQuery.isEmpty) return _services;
    return _services.where((s) =>
      s['name'].toString().toLowerCase().contains(_searchQuery.toLowerCase()) ||
      s['cat'].toString().toLowerCase().contains(_searchQuery.toLowerCase())
    ).toList();
  }

  @override
  void initState() {
    super.initState();
    _user = FirebaseAuth.instance.currentUser;
  }

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

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
      body: _currentIndex == 0 ? _buildHome() :
            _currentIndex == 1 ? _buildBookings() : _buildProfile(),
    );
  }

  Widget _buildHome() {
    return CustomScrollView(
      slivers: [
        SliverAppBar(
          expandedHeight: 160,
          floating: false,
          pinned: true,
          backgroundColor: AppColors.teal,
          flexibleSpace: FlexibleSpaceBar(
            background: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [Color(0xFF0D3D47), AppColors.teal],
                ),
              ),
              padding: const EdgeInsets.fromLTRB(20, 50, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Hello, ${_user?.displayName?.split(' ').first ?? 'there'} 👋',
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white),
                          ),
                          const Text('What service do you need?', style: TextStyle(fontSize: 13, color: Colors.white70)),
                        ],
                      ),
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: AppColors.brand,
                        backgroundImage: _user?.photoURL != null ? NetworkImage(_user!.photoURL!) : null,
                        child: _user?.photoURL == null
                            ? Text((_user?.displayName ?? 'U')[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))
                            : null,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(56),
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8)],
              ),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _searchQuery = v),
                decoration: InputDecoration(
                  hintText: 'Search services — e.g. Plumber, AC...',
                  prefixIcon: const Icon(Icons.search, color: AppColors.muted),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(icon: const Icon(Icons.clear, color: AppColors.muted), onPressed: () { _searchCtrl.clear(); setState(() => _searchQuery = ''); })
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  hintStyle: const TextStyle(color: AppColors.muted, fontSize: 13),
                ),
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 0.85,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final svc = _filtered[index];
                return GestureDetector(
                  onTap: () => _onServiceTap(svc),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 52, height: 52,
                          decoration: BoxDecoration(
                            color: Color(svc['color'] as int),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Center(
                            child: Text(svc['icon'] as String, style: const TextStyle(fontSize: 26)),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Text(
                            svc['name'] as String,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.ink),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
              childCount: _filtered.length,
            ),
          ),
        ),
      ],
    );
  }

  void _onServiceTap(Map<String, dynamic> svc) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 56, height: 56,
                decoration: BoxDecoration(color: Color(svc['color'] as int), borderRadius: BorderRadius.circular(14)),
                child: Center(child: Text(svc['icon'] as String, style: const TextStyle(fontSize: 30))),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(svc['name'] as String, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.ink)),
                  Text(svc['cat'] as String, style: const TextStyle(fontSize: 13, color: AppColors.muted)),
                ],
              )),
            ]),
            const SizedBox(height: 20),
            const Text('This service will be available for booking soon.\nFull booking flow coming in the next update!',
              style: TextStyle(fontSize: 14, color: AppColors.ink2, height: 1.5)),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Got it'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBookings() {
    return Scaffold(
      appBar: AppBar(title: const Text('My Bookings')),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long_rounded, size: 64, color: AppColors.muted),
            SizedBox(height: 16),
            Text('No bookings yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink)),
            SizedBox(height: 8),
            Text('Your bookings will appear here', style: TextStyle(color: AppColors.muted)),
          ],
        ),
      ),
    );
  }

  Widget _buildProfile() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await FirebaseService.signOut();
              if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const SizedBox(height: 20),
            CircleAvatar(
              radius: 44,
              backgroundColor: AppColors.teal,
              backgroundImage: _user?.photoURL != null ? NetworkImage(_user!.photoURL!) : null,
              child: _user?.photoURL == null
                  ? Text((_user?.displayName ?? 'U')[0].toUpperCase(), style: const TextStyle(fontSize: 32, color: Colors.white, fontWeight: FontWeight.w700))
                  : null,
            ),
            const SizedBox(height: 16),
            Text(_user?.displayName ?? 'User', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.ink)),
            const SizedBox(height: 4),
            Text(_user?.email ?? _user?.phoneNumber ?? '', style: const TextStyle(fontSize: 14, color: AppColors.muted)),
            const SizedBox(height: 32),
            _profileTile(Icons.receipt_long_rounded, 'My Bookings', () => setState(() => _currentIndex = 1)),
            _profileTile(Icons.location_on_rounded, 'Saved Addresses', () {}),
            _profileTile(Icons.help_outline_rounded, 'Help & Support', () {}),
            _profileTile(Icons.logout, 'Sign Out', () async {
              await FirebaseService.signOut();
              if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
            }, color: AppColors.red),
          ],
        ),
      ),
    );
  }

  Widget _profileTile(IconData icon, String title, VoidCallback onTap, {Color color = AppColors.ink}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)]),
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: color)),
        trailing: color == AppColors.red ? null : const Icon(Icons.chevron_right, color: AppColors.muted),
        onTap: onTap,
      ),
    );
  }
}
