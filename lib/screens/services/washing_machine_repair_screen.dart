import 'package:flutter/material.dart';
import '../../utils/theme.dart';
import 'service_widgets.dart';
import '../../services/service_price_service.dart';

class WashingMachineRepairScreen extends StatefulWidget {
  const WashingMachineRepairScreen({super.key});
  @override State<WashingMachineRepairScreen> createState() => _WashingMachineRepairState();
}
class _WashingMachineRepairState extends State<WashingMachineRepairScreen> {
  String _type = 'front';
  String _issue = 'notstart';
  int _p(String key) => ServicePriceService().getPrice('SVC007', key);

  int get _total => _p('${_type}_base') + (_issue=='notstart'?0:_p('addon_${_issue}'));
  List<String> get _summary => ['Washing Machine Repair > ${_tl(_type)} > ${_il(_issue)}'];
  String _tl(String k) => {'front':'Front Load','top':'Top Load','semi':'Semi-Auto'}[k]!;
  String _il(String k) => {'notstart':'Not Starting','noise':'Noise/Vibration','leak':'Water Leak','notdrain':'Not Draining','drum':'Drum Issue','motor':'Motor Fault','panel':'Control Panel'}[k]!;
  @override
  Widget build(BuildContext ctx) => Scaffold(
    backgroundColor: AppColors.bg,
    appBar: AppBar(title: const Text('Washing Machine Repair'), backgroundColor: AppColors.teal),
    body: Column(children: [
      Expanded(child: ListView(padding: const EdgeInsets.all(16), children: [
        svcHeader('🫙','Washing Machine Repair','Drum, motor, pump & panel diagnosis',const Color(0xFF1565C0)),
        const SizedBox(height:16),
        svcLabel('MACHINE TYPE'),
        svcOptionGrid(title:'MACHINE TYPE',options:[
          {'k':'front','l':'Front Load','p':549},{'k':'top','l':'Top Load','p':449},{'k':'semi','l':'Semi-Auto','p':349},
        ],selected:_type,onSelect:(v)=>setState(()=>_type=v)),
        svcLabel('ISSUE TYPE'),
        svcChip('🚫','Not Starting','Base price',_issue=='notstart',()=>setState(()=>_issue='notstart')),
        svcChip('🔊','Noise / Vibration','+ ₹100',_issue=='noise',()=>setState(()=>_issue='noise')),
        svcChip('💧','Water Leak','+ ₹150',_issue=='leak',()=>setState(()=>_issue='leak')),
        svcChip('🚿','Not Draining','+ ₹100',_issue=='notdrain',()=>setState(()=>_issue='notdrain')),
        svcChip('🔄','Drum Not Rotating','+ ₹200',_issue=='drum',()=>setState(()=>_issue='drum')),
        svcChip('⚙️','Motor Fault','+ ₹300',_issue=='motor',()=>setState(()=>_issue='motor')),
        svcChip('📟','Control Panel Error','+ ₹400',_issue=='panel',()=>setState(()=>_issue='panel')),
        svcInfo('Visiting charge included. Spare parts extra if needed.'),
        const SizedBox(height:80),
      ])),
      svcBottomBar(ctx,true,_total,'SVC007','Washing Machine Repair','🫙','Appliance Care',_summary),
    ]));
}