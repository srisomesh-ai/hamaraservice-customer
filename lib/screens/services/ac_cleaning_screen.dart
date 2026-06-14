import 'package:flutter/material.dart';
import '../../utils/theme.dart';
import 'service_widgets.dart';

class ACCleaningScreen extends StatefulWidget {
  const ACCleaningScreen({super.key});
  @override State<ACCleaningScreen> createState() => _ACCleaningState();
}
class _ACCleaningState extends State<ACCleaningScreen> {
  int _units = 1;
  String _type = 'split';
  bool _deepCoil = false, _drainCheck = false;
  final _typePx = {'split':599,'window':499,'cassette':799,'central':999};
  int get _total => (_typePx[_type]! * _units) + (_deepCoil?200*_units:0) + (_drainCheck?150*_units:0);
  List<String> get _summary => [
    'AC Cleaning > $_units ${_tl(_type)} AC${_units>1?"s":""}',
    if (_deepCoil) 'AC Cleaning > Deep Coil Wash +₹${200*_units}',
    if (_drainCheck) 'AC Cleaning > Drainage Check +₹${150*_units}',
  ];
  String _tl(String k) => {'split':'Split','window':'Window','cassette':'Cassette','central':'Central'}[k]!;
  @override
  Widget build(BuildContext ctx) => Scaffold(
    backgroundColor: AppColors.bg,
    appBar: AppBar(title: const Text('AC Cleaning'), backgroundColor: AppColors.teal),
    body: Column(children: [
      Expanded(child: ListView(padding: const EdgeInsets.all(16), children: [
        svcHeader('❄️','AC Cleaning','Filter clean, coil wash & performance test',const Color(0xFF0288D1)),
        const SizedBox(height:16),
        svcLabel('AC TYPE'),
        svcOptionGrid(title:'AC TYPE',options:[
          {'k':'split','l':'Split AC','p':599},{'k':'window','l':'Window AC','p':499},
          {'k':'cassette','l':'Cassette','p':799},{'k':'central','l':'Central','p':999},
        ],selected:_type,onSelect:(v)=>setState(()=>_type=v)),
        svcLabel('NUMBER OF UNITS'),
        svcCounter('AC Units','Price multiplied per unit',_units,1,5,(v)=>setState(()=>_units=v)),
        svcInfo('Price per unit: Split ₹599 · Window ₹499 · Cassette ₹799 · Central ₹999'),
        svcLabel('ADD-ONS (per unit)'),
        svcChip('🧽','Deep Coil Wash','+ ₹200/unit',_deepCoil,()=>setState(()=>_deepCoil=!_deepCoil)),
        svcChip('💧','Drainage Line Check','+ ₹150/unit',_drainCheck,()=>setState(()=>_drainCheck=!_drainCheck)),
        const SizedBox(height:80),
      ])),
      svcBottomBar(ctx,true,_total,'SVC005','AC Cleaning','❄️','Appliance Care',_summary),
    ]));
}