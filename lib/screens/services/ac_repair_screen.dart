import 'package:flutter/material.dart';
import '../../utils/theme.dart';
import 'service_widgets.dart';
import '../../services/service_price_service.dart';

class ACRepairScreen extends StatefulWidget {
  const ACRepairScreen({super.key});
  @override State<ACRepairScreen> createState() => _ACRepairState();
}
class _ACRepairState extends State<ACRepairScreen> {
  String _issue = 'notcooling';
  String _type = 'split';
  int _p(String key) => ServicePriceService().getPrice('SVC006', key);
  // type add handled via key combo
  int get _total => _p('${_issue}_${_type}') > 0 ? _p('${_issue}_${_type}') : _p('${_issue}_split').clamp(299,9999);
  List<String> get _summary => ['AC Repair > ${_tl(_type)} > ${_il(_issue)}'];
  String _tl(String k) => {'split':'Split','window':'Window','cassette':'Cassette','central':'Central'}[k]!;
  String _il(String k) => {'notcooling':'Not Cooling','gasleak':'Gas Leak/Refill','noise':'Noise Issue','notstart':'Not Starting','remote':'Remote Issue','pcb':'PCB Board'}[k]!;
  @override
  Widget build(BuildContext ctx) => Scaffold(
    backgroundColor: AppColors.bg,
    appBar: AppBar(title: const Text('AC Repair'), backgroundColor: AppColors.teal),
    body: Column(children: [
      Expanded(child: ListView(padding: const EdgeInsets.all(16), children: [
        svcHeader('🔩','AC Repair','Gas refill, compressor & electrical diagnosis',const Color(0xFF01579B)),
        const SizedBox(height:16),
        svcLabel('AC TYPE'),
        svcOptionGrid(title:'AC TYPE',options:[
          {'k':'split','l':'Split AC','p':0},{'k':'window','l':'Window AC','p':-100},
          {'k':'cassette','l':'Cassette','p':'+200'},{'k':'central','l':'Central','p':'+400'},
        ],selected:_type,onSelect:(v)=>setState(()=>_type=v)),
        svcLabel('ISSUE TYPE'),
        svcChip('🌡️','Not Cooling Properly','From ₹599',_issue=='notcooling',()=>setState(()=>_issue='notcooling')),
        svcChip('💨','Gas Leak / Refill','From ₹1499',_issue=='gasleak',()=>setState(()=>_issue='gasleak')),
        svcChip('🔊','Noise / Vibration','From ₹699',_issue=='noise',()=>setState(()=>_issue='noise')),
        svcChip('⚡','Not Starting / Tripping','From ₹799',_issue=='notstart',()=>setState(()=>_issue='notstart')),
        svcChip('📡','Remote / Sensor Issue','From ₹299',_issue=='remote',()=>setState(()=>_issue='remote')),
        svcChip('🖥️','PCB / Circuit Board','From ₹1299',_issue=='pcb',()=>setState(()=>_issue='pcb')),
        svcInfo('Visiting charge included. Final amount after diagnosis.'),
        const SizedBox(height:80),
      ])),
      svcBottomBar(ctx,true,_total,'SVC006','AC Repair','🔩','Appliance Care',_summary),
    ]));
}