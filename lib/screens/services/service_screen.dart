import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_database/firebase_database.dart';
import '../theme.dart';
import '../services/hs_catalog.dart';

class ServicesScreen extends StatefulWidget {
  const ServicesScreen({super.key});
  @override
  State<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends State<ServicesScreen> {
  // Live prices from Firebase: { 'SVC001': { 'bhk_1bhk': 999, ... } }
  Map<String, Map<String, dynamic>> _fbPrices = {};
  bool _loading = true;
  String _cat = 'All';

  final _cats = [
    'All', 'Home Cleaning', 'Home Services', 'Vehicle Care',
    'Cooking', 'Beauty & Wellness', 'Health Services',
    'Care Services', 'Outdoor', 'Security', 'Pest Control',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final snap = await FirebaseDatabase.instance.ref('hs_service_prices').get();
      if (snap.exists) {
        final data = Map<String, dynamic>.from(snap.value as Map);
        _fbPrices = data.map((k, v) => MapEntry(k, Map<String, dynamic>.from(v as Map)));
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  List<HSService> get _filtered {
    if (_cat == 'All') return HSCatalog.services;
    return HSCatalog.services.where((s) => s.cat == _cat).toList();
  }

  // Get base price for a service — from Firebase if set, else 0
  int _basePrice(String id) {
    final fb = _fbPrices[id];
    if (fb != null && fb['basePrice'] is int) return fb['basePrice'] as int;
    return HSCatalog.getById(id)?.basePrice ?? 0;
  }

  void _editService(HSService svc) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _EditSheet(svc: svc, fbData: _fbPrices[svc.id] ?? {},
        onSaved: (updated) {
          setState(() => _fbPrices[svc.id] = updated);
        }),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return Column(children: [
      // Category filter
      Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: _cats.map((c) {
            final sel = _cat == c;
            return GestureDetector(
              onTap: () { HapticFeedback.selectionClick(); setState(() => _cat = c); },
              child: Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: sel ? AppColors.teal : AppColors.bg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: sel ? AppColors.teal : AppColors.line)),
                child: Text(c, style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700,
                  color: sel ? Colors.white : AppColors.muted))));
          }).toList())),
      ),
      // Service list
      Expanded(child: RefreshIndicator(
        onRefresh: _load,
        child: ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: _filtered.length,
          itemBuilder: (_, i) {
            final svc = _filtered[i];
            final bp = _basePrice(svc.id);
            final isActive = (_fbPrices[svc.id]?['status'] ?? 'active') != 'inactive';
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                leading: Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: isActive ? AppColors.tealSoft : AppColors.bg,
                    borderRadius: BorderRadius.circular(12)),
                  child: Center(child: Text(svc.icon,
                    style: const TextStyle(fontSize: 26)))),
                title: Row(children: [
                  Expanded(child: Text(svc.name, style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700,
                    color: isActive ? AppColors.ink : AppColors.muted))),
                  if (!isActive)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.redSoft,
                        borderRadius: BorderRadius.circular(6)),
                      child: const Text('OFF', style: TextStyle(
                        fontSize: 10, color: AppColors.red, fontWeight: FontWeight.w800))),
                ]),
                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(svc.cat, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                  const SizedBox(height: 4),
                  Row(children: [
                    _pill(bp == 0 ? 'Price not set' : 'Base: ₹$bp',
                      bp == 0 ? AppColors.muted : AppColors.teal),
                    const SizedBox(width: 6),
                    _pill('${svc.groups.length} groups', AppColors.purple),
                  ]),
                ]),
                trailing: IconButton(
                  icon: const Icon(Icons.edit_rounded, color: AppColors.teal),
                  onPressed: () => _editService(svc)),
              ));
          }))),
    ]);
  }

  Widget _pill(String t, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
    child: Text(t, style: TextStyle(
      fontSize: 10, fontWeight: FontWeight.w700, color: c)));
}

// ── Edit Sheet ──────────────────────────────────────────────────────
class _EditSheet extends StatefulWidget {
  final HSService svc;
  final Map<String, dynamic> fbData;
  final Function(Map<String, dynamic>) onSaved;
  const _EditSheet({required this.svc, required this.fbData, required this.onSaved});
  @override
  State<_EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends State<_EditSheet> {
  late bool _active;
  // Controllers for every option: key = 'groupKey_optionKey'
  late Map<String, TextEditingController> _ctrls;

  @override
  void initState() {
    super.initState();
    _active = (widget.fbData['status'] ?? 'active') != 'inactive';
    _ctrls = {};
    for (final g in widget.svc.groups) {
      if (g.style == 'info') continue;
      for (final o in g.items) {
        final fbKey = '${g.key}_${o.key}';
        final existing = widget.fbData['prices']?[fbKey];
        final val = (existing is int) ? existing.toString() : '0';
        _ctrls[fbKey] = TextEditingController(text: val);
      }
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) c.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    HapticFeedback.mediumImpact();
    final prices = <String, int>{};
    int firstPrice = 0;
    for (final entry in _ctrls.entries) {
      final val = int.tryParse(entry.value.text) ?? 0;
      prices[entry.key] = val;
      if (firstPrice == 0 && val > 0) firstPrice = val;
    }
    final updated = {
      ...widget.fbData,
      'id': widget.svc.id,
      'name': widget.svc.name,
      'icon': widget.svc.icon,
      'cat': widget.svc.cat,
      'basePrice': firstPrice,
      'prices': prices,
      'status': _active ? 'active' : 'inactive',
      'updatedAt': DateTime.now().toIso8601String(),
      'updatedBy': 'admin',
    };
    await FirebaseDatabase.instance
        .ref('hs_service_prices/${widget.svc.id}')
        .update(updated);
    widget.onSaved(updated);
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${widget.svc.name} saved to Firebase'),
        backgroundColor: AppColors.green));
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (_, ctrl) => Column(children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4)]),
          child: Column(children: [
            Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(
                color: AppColors.line, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 12),
            Row(children: [
              Text(widget.svc.icon, style: const TextStyle(fontSize: 32)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.svc.name, style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink)),
                Text(widget.svc.cat, style: const TextStyle(
                  fontSize: 12, color: AppColors.muted)),
              ])),
              Row(children: [
                const Text('Active', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                Switch(value: _active, activeColor: AppColors.green,
                  onChanged: (v) => setState(() => _active = v)),
              ]),
            ]),
          ])),
        // Price fields
        Expanded(child: ListView(controller: ctrl,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          children: [
            Container(padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.tealSoft, borderRadius: BorderRadius.circular(10)),
              child: const Text(
                '💡 Set price for each option. Leave 0 if not applicable.',
                style: TextStyle(fontSize: 12, color: AppColors.teal, fontWeight: FontWeight.w600))),
            const SizedBox(height: 16),
            ...widget.svc.groups.map((g) {
              if (g.style == 'info') {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.bg, borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.line)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(g.title, style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.muted)),
                      const SizedBox(height: 4),
                      Text(g.info ?? '', style: const TextStyle(
                        fontSize: 12, color: AppColors.ink)),
                    ])));
              }
              return Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(g.title, style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.ink))),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.purple.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10)),
                      child: Text(g.style, style: const TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.purple))),
                  ]),
                  const SizedBox(height: 10),
                  ...g.items.map((o) {
                    final fbKey = '${g.key}_${o.key}';
                    final ctrl = _ctrls[fbKey];
                    if (ctrl == null) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(children: [
                        if (o.ico.isNotEmpty)
                          Padding(padding: const EdgeInsets.only(right: 8),
                            child: Text(o.ico, style: const TextStyle(fontSize: 18))),
                        Expanded(child: Text(o.name, style: const TextStyle(
                          fontSize: 13, color: AppColors.ink))),
                        const SizedBox(width: 12),
                        SizedBox(width: 90, child: TextField(
                          controller: ctrl,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.teal),
                          decoration: InputDecoration(
                            prefixText: '₹',
                            prefixStyle: const TextStyle(
                              fontSize: 12, color: AppColors.muted),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8))))),
                      ]));
                  }).toList(),
                ]));
            }).toList(),
          ])),
        // Save button
        Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          color: Colors.white,
          child: ElevatedButton(
            onPressed: _save,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            child: const Text('Save to Firebase',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)))),
      ]));
  }
}
