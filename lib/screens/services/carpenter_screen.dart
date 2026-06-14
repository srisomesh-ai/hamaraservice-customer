import 'package:flutter/material.dart';
import '../../utils/theme.dart';
import '../../services/service_price_service.dart';
import 'service_widgets.dart';

class CarpenterScreen extends StatefulWidget {
  const CarpenterScreen({super.key});
  @override State<CarpenterScreen> createState() => _CarpenterState();
}
class _CarpenterState extends State<CarpenterScreen> {
  final Set<String> _issues = {};

  int _p(String key) => ServicePriceService().getPrice('SVC022', key);

  int get _total => _issues.isEmpty
      ? _p('furniture')
      : _issues.fold<int>(0, (s, k) => s + _p(k));

  List<String> get _summary => [
    if (_issues.isEmpty) 'Carpenter > General Visit',
    ..._issues.map((k) => 'Carpenter > ${_il(k)}'),
  ];

  String _il(String k) => {
    'furniture': 'Furniture Assembly',
    'door': 'Door Repair/Fix',
    'window': 'Window/Frame Fix',
    'hinge': 'Hinge/Handle Fix',
    'lock': 'Lock & Key Issue',
    'shelf': 'Shelf Installation',
    'cabinet': 'Cabinet Repair',
    'bed': 'Bed Assembly',
  }[k]!;

  void _toggle(String k) =>
      setState(() => _issues.contains(k) ? _issues.remove(k) : _issues.add(k));

  @override
  Widget build(BuildContext ctx) => Scaffold(
    backgroundColor: AppColors.bg,
    appBar: AppBar(title: const Text('Carpenter'), backgroundColor: AppColors.teal),
    body: Column(children: [
      Expanded(child: ListView(padding: const EdgeInsets.all(16), children: [
        svcHeader('🪚', 'Carpenter Visit', 'Furniture, door, window & lock repair', const Color(0xFF4E342E)),
        const SizedBox(height: 16),
        svcInfo('Select your requirement. Minimum visit: ₹${_p("furniture")}.'),
        svcLabel('SELECT WORK (Multiple OK)'),
        svcChip('🪑', 'Furniture Assembly',    '₹${_p("furniture")}', _issues.contains('furniture'), () => _toggle('furniture')),
        svcChip('🛏️', 'Bed Assembly / Repair', '₹${_p("bed")}',       _issues.contains('bed'),       () => _toggle('bed')),
        svcChip('🚪', 'Door Repair / Adjust',  '₹${_p("door")}',      _issues.contains('door'),      () => _toggle('door')),
        svcChip('🪟', 'Window / Frame Fix',    '₹${_p("window")}',    _issues.contains('window'),    () => _toggle('window')),
        svcChip('🔩', 'Hinge / Handle Fix',    '₹${_p("hinge")}',     _issues.contains('hinge'),     () => _toggle('hinge')),
        svcChip('🔐', 'Lock & Key Issue',      '₹${_p("lock")}',      _issues.contains('lock'),      () => _toggle('lock')),
        svcChip('📚', 'Shelf Installation',    '₹${_p("shelf")}',     _issues.contains('shelf'),     () => _toggle('shelf')),
        svcChip('🗄️', 'Cabinet Repair',        '₹${_p("cabinet")}',   _issues.contains('cabinet'),   () => _toggle('cabinet')),
        const SizedBox(height: 80),
      ])),
      svcBottomBar(ctx, true, _total, 'SVC022', 'Carpenter Visit', '🪚', 'Repairs',
        _issues.isEmpty ? ['Carpenter > General Visit'] : _summary),
    ]));
}
