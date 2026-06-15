import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import '../../utils/theme.dart';
import '../../services/hs_catalog.dart';
import '../booking/booking_flow_screen.dart';
import '../login_screen.dart';

/// Universal Service Screen
/// Reads from HSCatalog — renders correctly for ALL services
/// No hardcoded content — 100% driven by hs_catalog.dart + Firebase prices
class ServiceScreen extends StatefulWidget {
  final String svcId;
  final Map<String, dynamic> svcData; // from home screen services list
  const ServiceScreen({super.key, required this.svcId, required this.svcData});
  @override
  State<ServiceScreen> createState() => _ServiceScreenState();
}

class _ServiceScreenState extends State<ServiceScreen> {
  HSService? _svc;
  Map<String, int> _prices = {};      // groupKey_optionKey → price from Firebase
  Map<String, String> _selected = {}; // groupKey → selected optionKey (bhk style)
  Set<String> _tasks = {};            // selected task keys (task style)
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _svc = HSCatalog.getById(widget.svcId);
    if (_svc == null) { setState(() => _loading = false); return; }

    // Load prices from Firebase
    try {
      final snap = await FirebaseDatabase.instance
          .ref('hs_service_prices/${widget.svcId}/prices')
          .get();
      if (snap.exists) {
        final data = Map<String, dynamic>.from(snap.value as Map);
        _prices = data.map((k, v) => MapEntry(k, (v is int) ? v : 0));
      }
    } catch (_) {}

    // Set first option of first bhk group as default selected
    for (final g in _svc!.groups) {
      if (g.style == 'bhk' && g.items.isNotEmpty && g.showOn == null) {
        _selected[g.key] = g.items.first.key;
        break;
      }
    }

    if (mounted) setState(() => _loading = false);
  }

  // Get price for an option
  int _price(String groupKey, String optionKey) {
    return _prices['${groupKey}_$optionKey'] ?? 0;
  }

  // Calculate total based on selections
  int get _total {
    if (_svc == null) return 0;
    int total = 0;

    for (final g in _svc!.groups) {
      if (g.style == 'info') continue;

      // For task groups — show per task if selected
      if (g.style == 'task') {
        for (final o in g.items) {
          if (_tasks.contains('${g.key}_${o.key}')) {
            total += _price(g.key, o.key);
          }
        }
      }

      // For bhk groups — add selected option price
      if (g.style == 'bhk') {
        // Only add if group has no showOn, OR showOn task is selected
        bool shouldAdd = g.showOn == null;
        if (g.showOn != null) {
          // Check if the parent task is selected
          shouldAdd = _tasks.contains('task_${g.showOn}');
        }
        if (shouldAdd) {
          final selKey = _selected[g.key] ?? (g.items.isNotEmpty ? g.items.first.key : '');
          if (selKey.isNotEmpty) {
            total += _price(g.key, selKey);
          }
        }
      }
    }

    return total;
  }

  // Summary list for booking
  List<String> get _summary {
    if (_svc == null) return [];
    final List<String> lines = [];

    for (final g in _svc!.groups) {
      if (g.style == 'info') continue;

      if (g.style == 'task') {
        for (final o in g.items) {
          if (_tasks.contains('${g.key}_${o.key}')) {
            lines.add('${_svc!.name} > ${o.name}');
          }
        }
      }

      if (g.style == 'bhk') {
        bool shouldShow = g.showOn == null;
        if (g.showOn != null) shouldShow = _tasks.contains('task_${g.showOn}');
        if (shouldShow) {
          final selKey = _selected[g.key] ?? (g.items.isNotEmpty ? g.items.first.key : '');
          final selOpt = g.items.where((o) => o.key == selKey).firstOrNull;
          if (selOpt != null) lines.add('${g.title}: ${selOpt.name}');
        }
      }
    }

    if (lines.isEmpty) lines.add(_svc!.name);
    return lines;
  }

  bool get _canBook {
    if (_svc == null) return false;
    // Can always book — even with 0 price (provider will quote on site)
    return true;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(backgroundColor: AppColors.teal),
        body: const Center(child: CircularProgressIndicator()));
    }
    if (_svc == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Service'), backgroundColor: AppColors.teal),
        body: const Center(child: Text('Service not found')));
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text(_svc!.name),
        backgroundColor: AppColors.teal,
        foregroundColor: Colors.white),
      body: Column(children: [
        Expanded(child: ListView(padding: const EdgeInsets.all(16), children: [
          // Header
          _buildHeader(),
          const SizedBox(height: 16),
          // Groups
          ..._svc!.groups.map((g) => _buildGroup(g)),
          const SizedBox(height: 80),
        ])),
        // Bottom bar
        _buildBottomBar(),
      ]));
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.teal.withOpacity(0.9), const Color(0xFF0D2B33)],
          begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        Text(_svc!.icon, style: const TextStyle(fontSize: 40)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_svc!.name, style: const TextStyle(
            fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
          Text(_svc!.cat, style: const TextStyle(fontSize: 12, color: Colors.white70)),
          const SizedBox(height: 4),
          const Row(children: [
            Icon(Icons.star_rounded, color: Color(0xFFFBBC04), size: 14),
            SizedBox(width: 4),
            Text('4.8 · Verified Professionals',
              style: TextStyle(color: Colors.white70, fontSize: 11)),
          ]),
        ])),
      ]));
  }

  Widget _buildGroup(HSGroup g) {
    // info style
    if (g.style == 'info') {
      return Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.tealSoft,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.teal.withOpacity(0.2))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.info_outline, color: AppColors.teal, size: 16),
          const SizedBox(width: 8),
          Expanded(child: Text(g.info ?? '',
            style: const TextStyle(fontSize: 12, color: AppColors.teal))),
        ]));
    }

    // For showOn groups — only show if parent task selected
    if (g.showOn != null && !_tasks.contains('task_${g.showOn}')) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Group title
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            Expanded(child: Text(g.title, style: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.ink))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: g.style == 'task'
                  ? AppColors.purple.withOpacity(0.1)
                  : AppColors.teal.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10)),
              child: Text(g.style == 'task' ? 'Multi-select' : 'Select one',
                style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w700,
                  color: g.style == 'task' ? AppColors.purple : AppColors.teal))),
          ])),
        // Options
        ...g.items.map((o) => _buildOption(g, o)),
      ]));
  }

  Widget _buildOption(HSGroup g, HSOption o) {
    final taskKey = '${g.key}_${o.key}';
    final bool selected = g.style == 'task'
        ? _tasks.contains(taskKey)
        : (_selected[g.key] == o.key);
    final int price = _price(g.key, o.key);
    final priceLabel = price == 0 ? 'Quote on-site' : '₹$price';

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() {
          if (g.style == 'task') {
            if (_tasks.contains(taskKey)) {
              _tasks.remove(taskKey);
              // Also deselect related bhk groups
              for (final sg in _svc!.groups) {
                if (sg.showOn == o.key) _selected.remove(sg.key);
              }
            } else {
              _tasks.add(taskKey);
              // Auto-select first option of related bhk group
              for (final sg in _svc!.groups) {
                if (sg.showOn == o.key && sg.items.isNotEmpty) {
                  _selected[sg.key] = sg.items.first.key;
                }
              }
            }
          } else {
            // bhk — single select
            _selected[g.key] = o.key;
          }
        });
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? AppColors.tealSoft : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.teal : AppColors.line,
            width: selected ? 2 : 1)),
        child: Row(children: [
          if (o.ico.isNotEmpty) ...[
            Text(o.ico, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
          ] else ...[
            Container(width: 8, height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? AppColors.teal : AppColors.line)),
            const SizedBox(width: 10),
          ],
          Expanded(child: Text(o.name, style: TextStyle(
            fontSize: 13, fontWeight: FontWeight.w600,
            color: selected ? AppColors.teal : AppColors.ink))),
          Text(priceLabel, style: TextStyle(
            fontSize: 13, fontWeight: FontWeight.w800,
            color: price == 0
              ? AppColors.muted
              : (selected ? AppColors.teal : AppColors.ink))),
          if (selected) ...[
            const SizedBox(width: 8),
            const Icon(Icons.check_circle_rounded, color: AppColors.teal, size: 18),
          ],
        ])));
  }

  Widget _buildBottomBar() {
    final total = _total;
    final priceText = total == 0 ? 'Quote on-site' : '₹$total';

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(
          color: Colors.black.withOpacity(0.08),
          blurRadius: 12, offset: const Offset(0, -4))]),
      child: Row(children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Total', style: TextStyle(fontSize: 11, color: AppColors.muted)),
          Text(priceText, style: const TextStyle(
            fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.ink)),
          if (total == 0)
            const Text('Provider will quote on arrival',
              style: TextStyle(fontSize: 10, color: AppColors.muted)),
        ]),
        const SizedBox(width: 16),
        Expanded(child: ElevatedButton(
          onPressed: _canBook ? () {
            HapticFeedback.mediumImpact();
            final user = FirebaseAuth.instance.currentUser;
            if (user == null) {
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => const LoginScreen()));
              return;
            }
            Navigator.push(context, MaterialPageRoute(
              builder: (_) => BookingFlowScreen(
                service: {
                  ...widget.svcData,
                  'id': widget.svcId,
                  'name': _svc!.name,
                  'icon': _svc!.icon,
                  'cat': _svc!.cat,
                },
                basePrice: total,
                summary: _summary,
              )));
          } : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.teal,
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
          child: const Text('Book Now',
            style: TextStyle(
              fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)))),
      ]));
  }
}
