import 'package:flutter/material.dart';
import '../../utils/theme.dart';
import 'service_widgets.dart';

class ElectricianScreen extends StatefulWidget {
  const ElectricianScreen({super.key});
  @override State<ElectricianScreen> createState() => _ElectricianState();
}
class _ElectricianState extends State<ElectricianScreen> {
  final Set<String> _issues = {};
  final _px = {'switch':399,'fan':399,'wiring':599,'mcb':499,'socket':399,'short':699,'light':299,'exhaust':349};
  int get _total {
    if (_issues.isEmpty) return 399;
    return _issues.fold(0,(s,k)=>s+_px[k]!);
  }
  bool get _any => _issues.isNotEmpty;
  List<String> get _summary => [
    if (_issues.isEmpty) 'Electrician > General Visit',
    ..._issues.map((k)=>'Electrician > ${_il(k)}'),
  ];
  String _il(String k) => {'switch':'Switch/Socket Repair','fan':'Fan Installation/Repair','wiring':'Wiring & Cabling','mcb':'MCB/Fuse Box','socket':'Socket/Plug Issue','short':'Short Circuit Fix','light':'Light Fitting','exhaust':'Exhaust Fan'}[k]!;
  void _toggle(String k) => setState(()=>_issues.contains(k)?_issues.remove(k):_issues.add(k));
  @override
  Widget build(BuildContext ctx) => Scaffold(
    backgroundColor: AppColors.bg,
    appBar: AppBar(title: const Text('Electrician'), backgroundColor: AppColors.teal),
    body: Column(children: [
      Expanded(child: ListView(padding: const EdgeInsets.all(16), children: [
        svcHeader('⚡','Electrician Visit','Switch, wiring, fan, MCB & circuit repair',const Color(0xFFF57F17)),
        const SizedBox(height:16),
        svcInfo('Select one or more issues. Minimum visit charge: ₹399.'),
        svcLabel('SELECT ISSUES (Multiple OK)'),
        svcChip('🔌','Switch / Socket Repair','₹399',_issues.contains('switch'),()=>_toggle('switch')),
        svcChip('💡','Light Fitting / Bulb','₹299',_issues.contains('light'),()=>_toggle('light')),
        svcChip('🌀','Fan Install / Repair','₹399',_issues.contains('fan'),()=>_toggle('fan')),
        svcChip('💨','Exhaust Fan','₹349',_issues.contains('exhaust'),()=>_toggle('exhaust')),
        svcChip('🔧','MCB / Fuse Box','₹499',_issues.contains('mcb'),()=>_toggle('mcb')),
        svcChip('⚡','Short Circuit Fix','₹699',_issues.contains('short'),()=>_toggle('short')),
        svcChip('🔀','Wiring & Cabling','₹599',_issues.contains('wiring'),()=>_toggle('wiring')),
        svcInfo('Final price confirmed after inspection.'),
        const SizedBox(height:80),
      ])),
      svcBottomBar(ctx,true,_issues.isEmpty?399:_total,'SVC020','Electrician Visit','⚡','Repairs',
        _issues.isEmpty?['Electrician > General Visit']:_summary),
    ]));
}