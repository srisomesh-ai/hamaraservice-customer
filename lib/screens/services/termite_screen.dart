import 'package:flutter/material.dart';
import '../../utils/theme.dart';
import 'service_widgets.dart';

class TermiteScreen extends StatefulWidget {
  const TermiteScreen({super.key});
  @override State<TermiteScreen> createState() => _TermiteState();
}
class _TermiteState extends State<TermiteScreen> {
  String _type = 'inspection';
  String _area = 'apartment';
  final _typePx = {'inspection':499,'prevention':1499,'treatment':2999,'complete':4999};
  final _areaAdd = {'apartment':0,'villa':500,'office':800,'warehouse':1500};
  int get _total => _typePx[_type]! + _areaAdd[_area]!;
  List<String> get _summary => ['Termite > ${_tl(_type)} > ${_al(_area)}'];
  String _tl(String k) => {'inspection':'Inspection Only','prevention':'Prevention Treatment','treatment':'Active Termite Treatment','complete':'Complete Package'}[k]!;
  String _al(String k) => {'apartment':'Apartment/Flat','villa':'Villa/Bungalow','office':'Office Space','warehouse':'Warehouse'}[k]!;
  @override
  Widget build(BuildContext ctx) => Scaffold(
    backgroundColor: AppColors.bg,
    appBar: AppBar(title: const Text('Termite Control'), backgroundColor: AppColors.teal),
    body: Column(children: [
      Expanded(child: ListView(padding: const EdgeInsets.all(16), children: [
        svcHeader('🔍','Termite Inspection','Full inspection + infestation report & treatment',const Color(0xFF4E342E)),
        const SizedBox(height:16),
        svcLabel('SERVICE TYPE'),
        svcChip('🔍','Inspection Only','₹499',_type=='inspection',()=>setState(()=>_type='inspection')),
        svcChip('🛡️','Prevention Treatment','₹1499',_type=='prevention',()=>setState(()=>_type='prevention')),
        svcChip('⚗️','Active Termite Treatment','₹2999',_type=='treatment',()=>setState(()=>_type='treatment')),
        svcChip('✅','Complete Package','₹4999',_type=='complete',()=>setState(()=>_type='complete')),
        svcLabel('PROPERTY TYPE'),
        svcOptionGrid(title:'PROPERTY',options:[
          {'k':'apartment','l':'Apartment','p':0},{'k':'villa','l':'Villa','p':'+500'},
          {'k':'office','l':'Office','p':'+800'},{'k':'warehouse','l':'Warehouse','p':'+1500'},
        ],selected:_area,onSelect:(v)=>setState(()=>_area=v)),
        const SizedBox(height:80),
      ])),
      svcBottomBar(ctx,true,_total,'SVC024','Termite Inspection','🔍','Pest Control',_summary),
    ]));
}