import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import '../../services/api_service.dart';
import '../../utils/theme.dart';
import '../../services/hs_catalog.dart';
import '../booking/booking_flow_screen.dart';
import '../login_screen.dart';

// ══════════════════════════════════════════════════════════════
// Universal Service Screen
// Matches svc001-house-maid.html design exactly
// Template A: task cards + BHK grid (House Maid, Deep Cleaning etc)
// Template B: visit fee card (Electrician, Plumber etc)
// ══════════════════════════════════════════════════════════════
class ServiceScreen extends StatefulWidget {
  final String svcId;
  final Map<String, dynamic> svcData;
  const ServiceScreen({super.key, required this.svcId, required this.svcData});
  @override
  State<ServiceScreen> createState() => _ServiceScreenState();
}

class _ServiceScreenState extends State<ServiceScreen> {
  HSService? _svc;
  Map<String, int> _prices = {};
  Set<String> _selectedTasks = {};    // 'task_sweep', 'task_dust' ...
  Map<String, String> _selectedBhk = {}; // groupKey → optionKey
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    _svc = HSCatalog.getById(widget.svcId);
    if (_svc == null) { setState(() => _loading = false); return; }
    try {
      // Load prices from MySQL API
      final grouped = await ApiService.getServicePrices(widget.svcId);
      final flat = <String, int>{};
      grouped.forEach((groupKey, groupVal) {
        if (groupVal is Map) {
          (groupVal as Map).forEach((optKey, price) {
            if (price is int || price is double) {
              flat['${groupKey}_$optKey'] = price is int ? price : (price as double).toInt();
            }
          });
        }
      });
      _prices = flat;
    } catch (_) {}
    // For visit-only services auto-select first option
    if (_isVisitOnly) {
      final g = _svc!.groups.first;
      if (g.items.isNotEmpty) _selectedBhk[g.key] = g.items.first.key;
    }
    if (mounted) setState(() => _loading = false);
  }

  int _p(String groupKey, String optKey) {
    // Direct price first, then admin min price as starting price
    final direct = _prices['${groupKey}_$optKey'] ?? 0;
    if (direct > 0) return direct;
    return _prices['${groupKey}_${optKey}_min'] ?? 0;
  }

  bool get _isVisitOnly =>
      _svc != null &&
      _svc!.groups.length == 1 &&
      _svc!.groups.first.style == 'bhk' &&
      _svc!.groups.first.showOn == null;

  int get _total {
    if (_svc == null) return 0;
    int t = 0;
    for (final g in _svc!.groups) {
      if (g.style == 'task' || g.style == 'info') continue;
      if (g.style == 'bhk') {
        final show = g.showOn == null || _selectedTasks.contains('task_${g.showOn}');
        if (!show) continue;
        final sel = _selectedBhk[g.key] ?? '';
        if (sel.isNotEmpty) t += _p(g.key, sel);
      }
    }
    return t;
  }

  List<String> get _summary {
    if (_svc == null) return [_svc?.name ?? ''];
    final List<String> lines = [];
    for (final g in _svc!.groups) {
      if (g.style == 'task') {
        for (final o in g.items) {
          if (_selectedTasks.contains('task_${o.key}')) lines.add('${_svc!.name} > ${o.name}');
        }
      }
      if (g.style == 'bhk') {
        final show = g.showOn == null || _selectedTasks.contains('task_${g.showOn}');
        if (!show) continue;
        final sel = _selectedBhk[g.key] ?? '';
        final opt = g.items.where((o) => o.key == sel).firstOrNull;
        if (opt != null) lines.add('${g.title}: ${opt.name}');
      }
    }
    return lines.isEmpty ? [_svc!.name] : lines;
  }

  bool get _canBook {
    if (_svc == null) return false;
    if (_isVisitOnly) return true;
    final hasTasks = _svc!.groups.any((g) => g.style == 'task');
    return hasTasks ? _selectedTasks.isNotEmpty : true;
  }

  void _toggleTask(String taskKey) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedTasks.contains(taskKey)) {
        _selectedTasks.remove(taskKey);
        for (final g in _svc!.groups) {
          if ('task_${g.showOn}' == taskKey) _selectedBhk.remove(g.key);
        }
      } else {
        _selectedTasks.add(taskKey);
        for (final g in _svc!.groups) {
          if ('task_${g.showOn}' == taskKey && g.items.isNotEmpty) {
            _selectedBhk[g.key] = g.items.first.key;
          }
        }
      }
    });
  }

  void _selectBhk(String groupKey, String optKey) {
    HapticFeedback.selectionClick();
    setState(() => _selectedBhk[groupKey] = optKey);
  }

  void _book() {
    HapticFeedback.mediumImpact();
    if (FirebaseAuth.instance.currentUser == null) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
      return;
    }
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => BookingFlowScreen(
        service: {...widget.svcData, 'id': widget.svcId,
          'name': _svc!.name, 'icon': _svc!.icon, 'cat': _svc!.cat},
        basePrice: _total,
        summary: _summary)));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(child: CircularProgressIndicator(color: AppColors.teal)));
    if (_svc == null) return Scaffold(
      appBar: AppBar(backgroundColor: AppColors.teal, foregroundColor: Colors.white,
        title: const Text('Service')),
      body: const Center(child: Text('Service not found')));

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(children: [
        CustomScrollView(slivers: [
          // ── HERO ────────────────────────────────────────────
          SliverToBoxAdapter(child: _buildHero()),
          // ── TRUST BAR ───────────────────────────────────────
          SliverToBoxAdapter(child: _buildTrustBar()),
          // ── CONTENT ─────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 110),
            sliver: SliverList(delegate: SliverChildListDelegate([
              if (_isVisitOnly) ...[
                _buildVisitCard(),
                const SizedBox(height: 16),
                _buildNoteBox('How pricing works: You pay the visit fee when booking. After inspection the provider gives you a quote for parts & labour. No hidden charges.'),
                const SizedBox(height: 24),
                _buildHowItWorks(),
              ] else
                _buildTasksBody(),
            ]))),
        ]),
        // ── BOTTOM BAR (always on top) ───────────────────────
        Positioned(bottom: 0, left: 0, right: 0, child: _buildBottomBar()),
      ]));
  }

  // ── HERO ─────────────────────────────────────────────────────
  Widget _buildHero() => Container(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        colors: [Color(0xFF071e25), Color(0xFF0d3541), AppColors.teal],
        begin: Alignment.topLeft, end: Alignment.bottomRight)),
    padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 16, 20, 28),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Back + category pill
      Row(children: [
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20))),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            border: Border.all(color: Colors.white.withOpacity(0.15)),
            borderRadius: BorderRadius.circular(100)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 5, height: 5, decoration: const BoxDecoration(
              color: AppColors.green, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(_svc!.cat, style: const TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white)),
          ])),
      ]),
      const SizedBox(height: 20),
      // Emoji
      Text(_svc!.icon, style: const TextStyle(fontSize: 52)),
      const SizedBox(height: 10),
      // Title
      Text(_svc!.name, style: const TextStyle(
        fontFamily: 'Sora', fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white)),
      const SizedBox(height: 6),
      Text('Verified professionals at your doorstep',
        style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.6))),
      const SizedBox(height: 16),
      // Tags
      Wrap(spacing: 6, runSpacing: 6, children: [
        _heroTag('⭐ 4.8 Rated'),
        _heroTag('✅ Verified'),
        _heroTag('🕐 On-time'),
        _heroTag('🛡️ Insured'),
        _heroTag('💳 Pay after service'),
      ]),
    ]));

  Widget _heroTag(String t) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.08),
      border: Border.all(color: Colors.white.withOpacity(0.12)),
      borderRadius: BorderRadius.circular(100)),
    child: Text(t, style: TextStyle(
      fontSize: 11, color: Colors.white.withOpacity(0.8), fontWeight: FontWeight.w500)));

  // ── TRUST BAR ─────────────────────────────────────────────────
  Widget _buildTrustBar() => Container(
    color: Colors.white,
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        _trustItem('👥', 'Verified Pros'),
        _trustItem('⚡', 'Book in 60s'),
        _trustItem('🔒', 'Background checked'),
        _trustItem('💳', 'Pay after service'),
      ])));

  Widget _trustItem(String ico, String t) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
    decoration: const BoxDecoration(
      border: Border(right: BorderSide(color: Color(0xFFe8eaef)))),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Text(ico, style: const TextStyle(fontSize: 14)),
      const SizedBox(width: 6),
      Text(t, style: const TextStyle(
        fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.ink2)),
    ]));

  // ── TEMPLATE A: TASKS BODY ────────────────────────────────────
  Widget _buildTasksBody() {
    final taskGroup = _svc!.groups.where((g) => g.style == 'task').firstOrNull;
    if (taskGroup == null) {
      // No task group — just bhk groups directly
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ..._svc!.groups.map((g) {
          if (g.style == 'bhk') return _buildBhkSection(g);
          if (g.style == 'info') return _buildInfoBox(g.info ?? g.title);
          return const SizedBox.shrink();
        }),
      ]);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Section header — "1. Select Tasks"
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Text('1. Select Tasks', style: TextStyle(
          fontFamily: 'Sora', fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.ink)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: const Color(0xFFdbeafe), borderRadius: BorderRadius.circular(100)),
          child: const Text('✓ Multi-select', style: TextStyle(
            fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF1d4ed8)))),
      ]),
      const SizedBox(height: 12),
      // Task cards
      ...taskGroup.items.map((opt) {
        final taskKey = 'task_${opt.key}';
        final isSelected = _selectedTasks.contains(taskKey);
        // Find related bhk/info group
        final subGroup = _svc!.groups.where((g) => g.showOn == opt.key).firstOrNull;
        return Column(children: [
          _buildTaskCard(opt, taskKey, isSelected),
          if (isSelected && subGroup != null) _buildSubSection(subGroup),
        ]);
      }),
    ]);
  }

  // ── TASK CARD ─────────────────────────────────────────────────
  Widget _buildTaskCard(HSOption opt, String taskKey, bool isSelected) =>
    GestureDetector(
      onTap: () => _toggleTask(taskKey),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.tealSoft : Colors.white,
          border: Border.all(
            color: isSelected ? AppColors.teal : AppColors.line, width: 2),
          borderRadius: BorderRadius.circular(20),
          boxShadow: isSelected
            ? [BoxShadow(color: AppColors.teal.withOpacity(0.15), blurRadius: 12, offset: const Offset(0,4))]
            : [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)]),
        child: Row(children: [
          // Icon box
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 46, height: 46,
            decoration: BoxDecoration(
              color: isSelected ? AppColors.teal.withOpacity(0.15) : AppColors.bg,
              borderRadius: BorderRadius.circular(14)),
            child: Center(child: Text(
              opt.ico.isNotEmpty ? opt.ico : '✓',
              style: const TextStyle(fontSize: 24)))),
          const SizedBox(width: 12),
          // Name + desc
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(opt.name, style: TextStyle(
              fontSize: 14, fontWeight: FontWeight.w700,
              color: isSelected ? AppColors.teal : AppColors.ink)),
          ])),
          // Check circle
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 24, height: 24,
            decoration: BoxDecoration(
              color: isSelected ? AppColors.teal : Colors.transparent,
              border: Border.all(
                color: isSelected ? AppColors.teal : AppColors.line, width: 2),
              shape: BoxShape.circle),
            child: isSelected
              ? const Icon(Icons.check_rounded, color: Colors.white, size: 14)
              : null),
        ])));

  // ── SUB SECTION (BHK grid slides under task) ──────────────────
  Widget _buildSubSection(HSGroup g) {
    if (g.style == 'info') {
      return Container(
        margin: const EdgeInsets.only(bottom: 6, left: 2, right: 2),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: AppColors.teal, width: 2),
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16))),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('💡', style: TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
            Expanded(child: Text(g.info ?? g.title,
              style: const TextStyle(fontSize: 12, color: Color(0xFF92400e), height: 1.5))),
          ])));
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 6, left: 2, right: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.teal, width: 2),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16)),
        boxShadow: [BoxShadow(color: AppColors.teal.withOpacity(0.12), blurRadius: 10)]),
      child: Column(children: [
        // Sub-header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: AppColors.tealSoft,
            borderRadius: BorderRadius.zero),
          child: Row(children: [
            const Text('🏠', style: TextStyle(fontSize: 14)),
            const SizedBox(width: 8),
            Expanded(child: Text(g.title, style: const TextStyle(
              fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.teal2))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFdcfce7), borderRadius: BorderRadius.circular(100)),
              child: const Text('Select one', style: TextStyle(
                fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFF15803d)))),
          ])),
        // BHK grid — 2 columns, same as HTML
        Padding(
          padding: const EdgeInsets.all(12),
          child: GridView.count(
            crossAxisCount: 2, shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 8, mainAxisSpacing: 8,
            childAspectRatio: 2.0,
            children: g.items.map((o) => _buildBhkCard(g.key, o)).toList())),
      ]));
  }

  // ── BHK SECTION (standalone, no task parent) ──────────────────
  Widget _buildBhkSection(HSGroup g) => Column(
    crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Expanded(child: Text(g.title, style: const TextStyle(
        fontFamily: 'Sora', fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.ink))),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFdcfce7), borderRadius: BorderRadius.circular(100)),
        child: const Text('Select one', style: TextStyle(
          fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFF15803d)))),
    ]),
    const SizedBox(height: 10),
    GridView.count(
      crossAxisCount: 2, shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 8, mainAxisSpacing: 8,
      childAspectRatio: 2.0,
      children: g.items.map((o) => _buildBhkCard(g.key, o)).toList()),
    const SizedBox(height: 20),
  ]);

  // ── BHK CARD — matches HTML exactly ───────────────────────────
  Widget _buildBhkCard(String groupKey, HSOption o) {
    final isSelected = _selectedBhk[groupKey] == o.key;
    final price = _p(groupKey, o.key);
    return GestureDetector(
      onTap: () => _selectBhk(groupKey, o.key),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.tealSoft : AppColors.bg,
          border: Border.all(
            color: isSelected ? AppColors.teal : AppColors.line,
            width: isSelected ? 2 : 1.5),
          borderRadius: BorderRadius.circular(14),
          boxShadow: isSelected
            ? [BoxShadow(color: AppColors.teal.withOpacity(0.18), blurRadius: 8)]
            : []),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          // Name
          Text(o.name, textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
              color: isSelected ? AppColors.teal2 : AppColors.ink2)),
          const SizedBox(height: 4),
          // Price — big bold like HTML
          Text(price > 0 ? '₹$price' : '₹0',
            style: TextStyle(
              fontFamily: 'Sora', fontSize: 20, fontWeight: FontWeight.w800,
              color: isSelected ? AppColors.teal2 : AppColors.teal)),
          const SizedBox(height: 4),
          // Selector dot
          Container(
            width: 18, height: 18,
            decoration: BoxDecoration(
              color: isSelected ? AppColors.teal : Colors.transparent,
              border: Border.all(
                color: isSelected ? AppColors.teal : AppColors.line, width: 1.5),
              shape: BoxShape.circle),
            child: isSelected
              ? const Icon(Icons.circle, color: Colors.white, size: 8)
              : null),
        ])));
  }

  // ── TEMPLATE B: VISIT CARD ────────────────────────────────────
  Widget _buildVisitCard() {
    final g = _svc!.groups.first;
    final selKey = _selectedBhk[g.key] ?? (g.items.isNotEmpty ? g.items.first.key : '');
    final price = selKey.isNotEmpty ? _p(g.key, selKey) : 0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.teal, width: 2),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(
          color: AppColors.teal.withOpacity(0.2), blurRadius: 20, offset: const Offset(0,4))]),
      child: Column(children: [
        // Top gradient header
        Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.teal, AppColors.teal2],
              begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
          child: Row(children: [
            Container(width: 52, height: 52,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(14)),
              child: Center(child: Text(_svc!.icon,
                style: const TextStyle(fontSize: 28)))),
            const SizedBox(width: 14),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_svc!.name, style: const TextStyle(
                fontFamily: 'Sora', fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
              Text('Visit / Call-out fee', style: TextStyle(
                fontSize: 12, color: Colors.white.withOpacity(0.7))),
            ]),
          ])),
        // Price row
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Row(children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('VISIT FEE', style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w700,
                color: AppColors.muted, letterSpacing: 0.5)),
              Text(price > 0 ? '₹$price' : '₹0', style: const TextStyle(
                fontFamily: 'Sora', fontSize: 38, fontWeight: FontWeight.w800,
                color: AppColors.teal)),
              const Text('Work charges quoted on-site',
                style: TextStyle(fontSize: 11, color: AppColors.muted)),
            ]),
            const Spacer(),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              const Text('You pay now', style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.muted)),
              Text(price > 0 ? '₹$price' : '₹0', style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.green)),
              const Text('+ work after', style: TextStyle(
                fontSize: 10, color: AppColors.muted)),
            ]),
          ])),
        const Divider(height: 24),
        // What's included
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text("WHAT'S INCLUDED", style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w700,
              color: AppColors.muted, letterSpacing: 0.5)),
            const SizedBox(height: 10),
            _includeRow('Professional travels to your location'),
            _includeRow('Full inspection and diagnosis'),
            _includeRow('Transparent cost estimate before work'),
            _includeRow('Minor fixes completed on the spot'),
          ])),
      ]));
  }

  Widget _includeRow(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(children: [
      Container(width: 6, height: 6, decoration: const BoxDecoration(
        color: AppColors.green, shape: BoxShape.circle)),
      const SizedBox(width: 10),
      Text(t, style: const TextStyle(fontSize: 13, color: AppColors.ink2)),
    ]));

  // ── INFO BOX ──────────────────────────────────────────────────
  Widget _buildInfoBox(String text) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFfffbeb),
      border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.3)),
      borderRadius: BorderRadius.circular(14)),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('💡', style: TextStyle(fontSize: 16)),
      const SizedBox(width: 10),
      Expanded(child: Text(text, style: const TextStyle(
        fontSize: 12, color: Color(0xFF92400e), height: 1.5, fontWeight: FontWeight.w500))),
    ]));

  Widget _buildNoteBox(String text) => _buildInfoBox(text);

  // ── HOW IT WORKS (Template B only) ───────────────────────────
  Widget _buildHowItWorks() => Column(
    crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('How it works', style: TextStyle(
      fontFamily: 'Sora', fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.ink)),
    const SizedBox(height: 14),
    Container(
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]),
      child: Column(children: [
        _stepRow('1', 'Book online in 60 seconds', 'Select your slot and confirm.'),
        _stepRow('2', 'Professional arrives at your door', 'On-time guaranteed. Track live.'),
        _stepRow('3', 'Inspection & transparent quote', 'Diagnose and show price before work.'),
        _stepRow('4', 'Work done — you pay', 'Pay via UPI, card or cash.', last: true),
      ])),
  ]);

  Widget _stepRow(String n, String title, String desc, {bool last = false}) =>
    Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: last ? null : const Border(bottom: BorderSide(color: Color(0xFFe8eaef)))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 30, height: 30,
          decoration: const BoxDecoration(color: AppColors.teal, shape: BoxShape.circle),
          child: Center(child: Text(n, style: const TextStyle(
            fontFamily: 'Sora', fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white)))),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(
            fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink)),
          const SizedBox(height: 2),
          Text(desc, style: const TextStyle(
            fontSize: 12, color: AppColors.muted, height: 1.5)),
        ])),
      ]));

  // ── BOTTOM BAR — matches HTML exactly ─────────────────────────
  Widget _buildBottomBar() {
    final total = _total;
    final hasAny = _selectedTasks.isNotEmpty || _isVisitOnly;

    // Build summary chips
    final chips = <String>[];
    for (final g in (_svc?.groups ?? [])) {
      if (g.style == 'task') {
        for (final o in g.items) {
          if (_selectedTasks.contains('task_${o.key}')) {
            final bhkG = _svc!.groups.where((bg) => bg.showOn == o.key).firstOrNull;
            if (bhkG != null) {
              final sel = _selectedBhk[bhkG.key] ?? '';
              final bhkOpt = bhkG.items.where((bo) => bo.key == sel).firstOrNull;
              chips.add('${o.name}${bhkOpt != null ? ' · ${bhkOpt.name}' : ''}');
            } else {
              chips.add(o.name);
            }
          }
        }
      }
    }

    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: AppColors.line, width: 1.5)),
        boxShadow: [BoxShadow(
          color: Colors.black.withOpacity(0.1), blurRadius: 16, offset: const Offset(0,-4))]),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min, children: [
          const Text('TOTAL', style: TextStyle(
            fontSize: 10, fontWeight: FontWeight.w700,
            color: AppColors.muted, letterSpacing: 0.5)),
          Text(total > 0 ? '₹$total' : '₹0', style: const TextStyle(
            fontFamily: 'Sora', fontSize: 28, fontWeight: FontWeight.w800,
            color: AppColors.ink)),
          if (chips.isNotEmpty)
            Wrap(spacing: 4, children: chips.map((c) => Container(
              margin: const EdgeInsets.only(top: 3),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.tealSoft,
                border: Border.all(color: AppColors.teal.withOpacity(0.2)),
                borderRadius: BorderRadius.circular(100)),
              child: Text(c, style: const TextStyle(
                fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.teal)))).toList())
          else if (!_isVisitOnly)
            const Text('Select tasks above', style: TextStyle(
              fontSize: 10, color: AppColors.muted))
          else
            const Text('Work charges quoted on-site', style: TextStyle(
              fontSize: 10, color: AppColors.muted)),
        ])),
        const SizedBox(width: 14),
        GestureDetector(
          onTap: _canBook ? _book : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            decoration: BoxDecoration(
              gradient: _canBook
                ? const LinearGradient(
                    colors: [AppColors.teal, AppColors.teal2],
                    begin: Alignment.topLeft, end: Alignment.bottomRight)
                : null,
              color: _canBook ? null : AppColors.line,
              borderRadius: BorderRadius.circular(100),
              boxShadow: _canBook
                ? [BoxShadow(color: AppColors.teal.withOpacity(0.35),
                    blurRadius: 14, offset: const Offset(0,4))]
                : []),
            child: Text(
              _isVisitOnly ? 'Book Visit →' : 'Book Now →',
              style: TextStyle(
                fontFamily: 'Sora', fontSize: 15, fontWeight: FontWeight.w700,
                color: _canBook ? Colors.white : AppColors.muted)))),
      ]));
  }
}
