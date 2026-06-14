import 'package:flutter/material.dart';
import '../../utils/theme.dart';
import 'service_widgets.dart';

class PlumberScreen extends StatefulWidget {
  const PlumberScreen({super.key});
  @override State<PlumberScreen> createState() => _PlumberState();
}
class _PlumberState extends State<PlumberScreen> {
  final Set<String> _issues = {};
  final _px = {'tap':399,'pipe':499,'flush':449,'block':549,'heater':599,'drain':499,'tank':699,'motor':799};
  int get _total => _issues.isEmpty ? 399 : _issues.fold(0,(s,k)=>s+_px[k]!);
  List<String> get _summary => [
    if (_issues.isEmpty) 'Plumber > General Visit',
    ..._issues.map((k)=>'Plumber > ${_il(k)}'),
  ];
  String _il(String k) => {'tap':'Tap / Faucet Repair','pipe':'Pipe Leak Fix','flush':'Flush Tank Repair','block':'Blockage / Drainage','heater':'Water Heater','drain':'Drain Cleaning','tank':'Water Tank','motor':'Water Motor/Pump'}[k]!;
  void _toggle(String k) => setState(()=>_issues.contains(k)?_issues.remove(k):_issues.add(k));
  @override
  Widget build(BuildContext ctx) => Scaffold(
    backgroundColor: AppColors.bg,
    appBar: AppBar(title: const Text('Plumber'), backgroundColor: AppColors.teal),
    body: Column(children: [
      Expanded(child: ListView(padding: const EdgeInsets.all(16), children: [
        svcHeader('🔧','Plumber Visit','Tap, pipe, flush, blockage & drainage fix',const Color(0xFF01579B)),
        const SizedBox(height:16),
        svcInfo('Select one or more issues. Minimum visit: ₹399.'),
        svcLabel('SELECT ISSUES (Multiple OK)'),
        svcChip('🚿','Tap / Faucet Repair','₹399',_issues.contains('tap'),()=>_toggle('tap')),
        svcChip('💧','Pipe Leak Fix','₹499',_issues.contains('pipe'),()=>_toggle('pipe')),
        svcChip('🚽','Flush Tank Repair','₹449',_issues.contains('flush'),()=>_toggle('flush')),
        svcChip('🚫','Blockage / Drainage','₹549',_issues.contains('block'),()=>_toggle('block')),
        svcChip('🔥','Water Heater Issue','₹599',_issues.contains('heater'),()=>_toggle('heater')),
        svcChip('🕳️','Drain Cleaning','₹499',_issues.contains('drain'),()=>_toggle('drain')),
        svcChip('🪣','Water Tank Issue','₹699',_issues.contains('tank'),()=>_toggle('tank')),
        svcChip('⚙️','Water Motor / Pump','₹799',_issues.contains('motor'),()=>_toggle('motor')),
        const SizedBox(height:80),
      ])),
      svcBottomBar(ctx,true,_issues.isEmpty?399:_total,'SVC021','Plumber Visit','🔧','Repairs',
        _issues.isEmpty?['Plumber > General Visit']:_summary),
    ]));
}