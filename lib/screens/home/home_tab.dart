import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../../services/api_service.dart';
import '../../services/hs_catalog.dart';
import '../../services/session.dart';
import '../../utils/booking_format.dart';
import '../../utils/service_visuals.dart';
import '../../utils/theme.dart';
import '../../widgets/common.dart';
import '../home_screen.dart';
import '../location_screen.dart';
import '../services/service_screen.dart';

/// Home tab: logo, location, search, category chips and the service grid
/// grouped by category — same catalog, order and price lines as the web app.
class HomeTab extends StatefulWidget {
  final HomePreview? preview;
  final Map<String, dynamic>? activeBooking;
  final ValueChanged<String> onOpenBooking;
  final VoidCallback onOpenAccount;
  final VoidCallback onAuthChanged;
  const HomeTab({
    super.key,
    this.preview,
    required this.activeBooking,
    required this.onOpenBooking,
    required this.onOpenAccount,
    required this.onAuthChanged,
  });

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  String _cat = 'All';
  String _city = '';
  String _name = '';
  Map<String, dynamic> _ranges = {};
  Set<String> _inactive = {};


  @override
  void initState() {
    super.initState();
    final p = widget.preview;
    if (p != null) {
      _city = p.city;
      _name = p.name;
      _ranges = p.priceRanges;
      return;
    }
    _name = Session.user?.displayName ?? '';
    _loadCity();
    _loadRanges();
    ApiService.getInactiveServices().then((s) {
      if (mounted && s.isNotEmpty) setState(() => _inactive = s);
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRanges() async {
    try {
      final r = await ApiService.getServicePriceRanges();
      if (mounted) setState(() => _ranges = r);
    } on ApiException catch (e) {
      debugPrint('Price ranges failed: ${e.message}');
    }
  }

  Future<void> _loadCity() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('user_city') ?? '';
      if (saved.isNotEmpty && mounted) setState(() => _city = saved);
      if (Session.signedIn) {
        try {
          final profile = await ApiService.getCustomer();
          if (profile != null) {
            final city = asStr(profile['city']);
            final name = asStr(profile['name']);
            if (mounted) {
              setState(() {
                if (city.isNotEmpty) _city = city;
                if (name.isNotEmpty) _name = name;
              });
            }
            if (city.isNotEmpty) await prefs.setString('user_city', city);
            await ApiService.saveCurrentUser(profile);
          }
        } on ApiException catch (e) {
          debugPrint('Profile load failed: ${e.message}');
        }
      }
    } catch (_) {}
    _refreshGps();
  }

  Future<void> _refreshGps() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium);
      String city = '';
      try {
        final marks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
        if (marks.isNotEmpty) {
          city = marks.first.locality ?? marks.first.subAdministrativeArea ?? '';
        }
      } catch (_) {}
      if (Session.signedIn) {
        try {
          await ApiService.updateCustomer({
            'lat': pos.latitude,
            'lng': pos.longitude,
            if (city.isNotEmpty) 'city': city,
          });
        } on ApiException catch (e) {
          debugPrint('Saving location failed: ${e.message}');
        }
      }
      if (city.isNotEmpty && mounted) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_city', city);
        setState(() => _city = city);
      }
    } catch (e) {
      debugPrint('GPS refresh failed: $e');
    }
  }

  Future<void> _pickCity() async {
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => const LocationScreen()));
    try {
      final prefs = await SharedPreferences.getInstance();
      final c = prefs.getString('user_city') ?? '';
      if (c.isNotEmpty && mounted) setState(() => _city = c);
    } catch (_) {}
  }

  void _openService(HSService s) {
    HapticFeedback.selectionClick();
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => ServiceScreen(
                svcId: s.id,
                svcData: {'id': s.id, 'name': s.name, 'icon': s.icon, 'cat': s.cat})));
  }

  List<HSService> get _visible {
    final q = _query.trim().toLowerCase();
    return ServiceVisuals.ordered.where((s) {
      if (_inactive.contains(s.id)) return false;
      if (_cat != 'All' && s.cat != _cat) return false;
      // Web: match on name or category
      if (q.isNotEmpty &&
          !s.name.toLowerCase().contains(q) &&
          !s.cat.toLowerCase().contains(q)) return false;
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final list = _visible;
    final grouped = _cat == 'All' && _query.trim().isEmpty;
    final slivers = <Widget>[
      _appBar(context),
      if (widget.activeBooking != null)
        SliverToBoxAdapter(child: _activeBanner(widget.activeBooking!)),
      if (grouped) SliverToBoxAdapter(child: _promise(context)),
    ];

    if (list.isEmpty) {
      slivers.add(const SliverFillRemaining(
        hasScrollBody: false,
        child: EmptyState(
          icon: Icons.search_off_rounded,
          title: 'No services found',
          message: 'Try a different word or category.',
        ),
      ));
    } else if (grouped) {
      for (final c in ServiceVisuals.categoryOrder) {
        final group = list.where((s) => s.cat == c).toList();
        if (group.isEmpty) continue;
        slivers.add(SliverToBoxAdapter(
            child: SectionHeader(c, trailing: '${group.length}')));
        slivers.add(_grid(group));
      }
    } else {
      slivers.add(SliverToBoxAdapter(
          child: SectionHeader(
              _query.trim().isNotEmpty ? 'Results' : _cat,
              trailing: '${list.length}')));
      slivers.add(_grid(list));
    }
    slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 24)));

    return CustomScrollView(slivers: slivers);
  }

  Widget _appBar(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final initial = (_name.isNotEmpty ? _name : 'U').characters.first.toUpperCase();
    final photo = widget.preview == null ? Session.user?.photoURL : null;
    return SliverAppBar(
      pinned: true,
      toolbarHeight: 64,
      titleSpacing: 16,
      title: Image.asset('assets/images/rlogo.png',
          height: 40,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => Text('HamaraService', style: t.titleLarge)),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: widget.onOpenAccount,
            child: CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.teal,
              foregroundColor: Colors.white,
              backgroundImage: photo != null ? NetworkImage(photo) : null,
              child: photo == null
                  ? Text(initial, style: t.titleSmall?.copyWith(color: Colors.white))
                  : null,
            ),
          ),
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(150),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
            child: Row(children: [
              Expanded(
                child: Text(
                  _name.isNotEmpty ? 'Hi $_name 👋' : 'Book trusted services near you',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.titleMedium,
                ),
              ),
              TextButton.icon(
                onPressed: _pickCity,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.teal2,
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.location_on_rounded, size: 18),
                label: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 120),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Flexible(
                      child: Text(_city.isEmpty ? 'Set location' : _city,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    const Icon(Icons.arrow_drop_down_rounded, size: 20),
                  ]),
                ),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SearchBar(
              controller: _searchCtrl,
              hintText: 'Search services…',
              elevation: const MaterialStatePropertyAll(0),
              backgroundColor: const MaterialStatePropertyAll(Color(0xFFEFF3F4)),
              constraints: const BoxConstraints(minHeight: 48, maxHeight: 48),
              padding: const MaterialStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 12)),
              leading: const Icon(Icons.search_rounded, color: AppColors.muted),
              trailing: [
                if (_query.isNotEmpty)
                  IconButton(
                    tooltip: 'Clear',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() => _query = '');
                    },
                  ),
              ],
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              children: [
                _catChip('All', Icons.apps_rounded),
                for (final c in ServiceVisuals.categoryOrder)
                  _catChip(c, ServiceVisuals.categoryIcons[c] ?? Icons.category_outlined),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _catChip(String c, IconData icon) {
    final sel = _cat == c;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        selected: sel,
        showCheckmark: false,
        avatar: Icon(icon, size: 18, color: sel ? AppColors.teal2 : AppColors.muted),
        label: Text(c),
        onSelected: (_) => setState(() => _cat = c),
      ),
    );
  }

  Widget _activeBanner(Map<String, dynamic> b) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Card(
        color: AppColors.tealSoft,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppColors.teal.withOpacity(0.25)),
        ),
        child: InkWell(
          onTap: () => widget.onOpenBooking(asStr(b['id'])),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              ServiceImage(asStr(b['svc_id']), size: 52, radius: 12),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Your active booking',
                      style: t.labelMedium?.copyWith(color: AppColors.teal2)),
                  const SizedBox(height: 2),
                  Text(asStr(b['svc_name']),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleMedium),
                  const SizedBox(height: 4),
                  StatusChip(b),
                ]),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.teal2),
            ]),
          ),
        ),
      ),
    );
  }

  /// The three promises of the web app's hero, in one card.
  Widget _promise(BuildContext context) {
    final t = Theme.of(context).textTheme;
    Widget item(IconData i, String a, String b) => Expanded(
          child: Column(children: [
            Icon(i, color: Colors.white, size: 22),
            const SizedBox(height: 6),
            Text(a,
                textAlign: TextAlign.center,
                style: t.labelLarge?.copyWith(color: Colors.white)),
            Text(b,
                textAlign: TextAlign.center,
                style: t.labelSmall?.copyWith(color: Colors.white70)),
          ]),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            colors: [AppColors.teal, AppColors.teal2],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          item(Icons.handshake_outlined, 'Price first', 'Agree before work'),
          item(Icons.verified_user_outlined, 'OTP protected', 'Start & finish'),
          item(Icons.payments_outlined, 'Pay after', 'Online or cash'),
        ]),
      ),
    );
  }

  Widget _grid(List<HSService> list) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          mainAxisExtent: 232,
        ),
        delegate: SliverChildBuilderDelegate(
          (_, i) => ServiceTile(
            service: list[i],
            range: _ranges[list[i].id],
            onTap: () => _openService(list[i]),
          ),
          childCount: list.length,
        ),
      ),
    );
  }
}

/// Grid tile: image, name, price line ("₹min – ₹max" + "N providers", or
/// "from ₹X") — the web app's tile.
class ServiceTile extends StatelessWidget {
  final HSService service;
  final dynamic range;
  final VoidCallback onTap;
  const ServiceTile({super.key, required this.service, this.range, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final price = TilePrice.of(service, range);
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: ServiceImage(service.id,
                size: double.infinity, radius: 0, padding: const EdgeInsets.all(10)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                height: 40,
                child: Text(service.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: t.titleSmall?.copyWith(height: 1.25)),
              ),
              const SizedBox(height: 4),
              Text.rich(
                TextSpan(children: [
                  if (price.from)
                    TextSpan(
                        text: 'from ',
                        style: t.labelSmall?.copyWith(color: AppColors.muted)),
                  TextSpan(text: price.main),
                ]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.labelLarge?.copyWith(
                    color: AppColors.brand2, fontWeight: FontWeight.w700),
              ),
              Text(
                price.providers > 0 ? providerCountLabel(price.providers) : 'Price agreed before work',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.labelSmall?.copyWith(color: AppColors.muted),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
