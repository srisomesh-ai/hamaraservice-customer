import 'package:flutter/material.dart';
import '../../utils/theme.dart';
import 'service_widgets.dart';
import '../../services/service_price_service.dart';

class PestControlScreen extends StatefulWidget {
  const PestControlScreen({super.key});
  @override State<PestControlScreen> createState() => _PestControlState();
}
class _PestControlState extends State<PestControlScreen> {
  String _bhk = '2bhk';
  bool _ants = false, _lizard = false, _mosquito = false, _bedbugs = false;
  int _p(String key) => ServicePriceService().getPrice('SVC023', key);
  int get _total => _p(_bhk) + (_ants?_p('addon_ants'):0) + (_lizard?_p('addon_lizard'):0) + (_mosquito?_p('addon_mosquito'):0) + (_bedbugs?_p('addon_bedbugs'):0);
  List<String> get _summary => [
    'Pest Control > Cockroach Control > ${_bl(_bhk)}',
    if (_ants) 'Pest Control > Ant Treatment +₹200',
    if (_lizard) 'Pest Control > Lizard Repellent +₹150',
    if (_mosquito) 'Pest Control > Mosquito Treatment +₹250',
    if (_bedbugs) 'Pest Control > Bed Bugs +₹499',
  ];
  String _bl(String k) => {'studio':'Studio','1bhk':'1 BHK','2bhk':'2 BHK','3bhk':'3 BHK','4bhk':'4 BHK','villa':'Villa'}[k]!;
  @override
  Widget build(BuildContext ctx) => Scaffold(
    backgroundColor: AppColors.bg,
    appBar: AppBar(title: const Text('Pest Control'), backgroundColor: AppColors.teal),
    body: Column(children: [
      Expanded(child: ListView(padding: const EdgeInsets.all(16), children: [
        svcHeader('🐛','Cockroach Control','Gel treatment + spray for all rooms',const Color(0xFF1B5E20)),
        const SizedBox(height:16),
        svcLabel('HOME SIZE'),
        svcOptionGrid(title:'HOME SIZE',options:[
          {'k':'studio','l':'Studio','p':599},{'k':'1bhk','l':'1 BHK','p':799},
          {'k':'2bhk','l':'2 BHK','p':999},{'k':'3bhk','l':'3 BHK','p':1299},
          {'k':'4bhk','l':'4 BHK','p':1599},{'k':'villa','l':'Villa','p':2499},
        ],selected:_bhk,onSelect:(v)=>setState(()=>_bhk=v)),
        svcInfo('Gel treatment + chemical spray. Safe for children & pets after 2 hrs.'),
        svcLabel('ADD PEST CONTROL FOR'),
        svcChip('🐜','Ants Treatment','+ ₹200',_ants,()=>setState(()=>_ants=!_ants)),
        svcChip('🦎','Lizard Repellent','+ ₹150',_lizard,()=>setState(()=>_lizard=!_lizard)),
        svcChip('🦟','Mosquito Treatment','+ ₹250',_mosquito,()=>setState(()=>_mosquito=!_mosquito)),
        svcChip('🐞','Bed Bugs Treatment','+ ₹499',_bedbugs,()=>setState(()=>_bedbugs=!_bedbugs)),
        const SizedBox(height:80),
      ])),
      svcBottomBar(ctx,true,_total,'SVC023','Cockroach Control','🐛','Pest Control',_summary),
    ]));
}