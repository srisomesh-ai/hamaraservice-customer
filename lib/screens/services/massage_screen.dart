import 'package:flutter/material.dart';
import '../../utils/theme.dart';
import 'service_widgets.dart';
import '../../services/service_price_service.dart';

class MassageScreen extends StatefulWidget {
  const MassageScreen({super.key});
  @override State<MassageScreen> createState() => _MassageState();
}
class _MassageState extends State<MassageScreen> {
  String _type = 'relaxation';
  String _duration = '60';
  int _persons = 1;
  int _p(String key) => ServicePriceService().getPrice('SVC015', key);

  int get _total => (_p('${_type}_${_duration}') > 0 ? _p('${_type}_${_duration}') : _p('${_type}_60') * (1.0)).round() * _persons;
  List<String> get _summary => [
    'Massage > $_persons × ${_tl(_type)} · ${_duration}min',
  ];
  String _tl(String k) => {'relaxation':'Relaxation','deep':'Deep Tissue','swedish':'Swedish','ayurvedic':'Ayurvedic','foot':'Foot Reflexology','head':'Head & Shoulder'}[k]!;
  @override
  Widget build(BuildContext ctx) => Scaffold(
    backgroundColor: AppColors.bg,
    appBar: AppBar(title: const Text('Full Body Massage'), backgroundColor: AppColors.teal),
    body: Column(children: [
      Expanded(child: ListView(padding: const EdgeInsets.all(16), children: [
        svcHeader('💆','Massage at Home','Relaxation & therapy by certified therapist',const Color(0xFF4A148C)),
        const SizedBox(height:16),
        svcLabel('MASSAGE TYPE'),
        svcChip('🌿','Relaxation Massage','From ₹999',_type=='relaxation',()=>setState(()=>_type='relaxation')),
        svcChip('💪','Deep Tissue Massage','From ₹1299',_type=='deep',()=>setState(()=>_type='deep')),
        svcChip('🍃','Swedish Massage','From ₹1499',_type=='swedish',()=>setState(()=>_type='swedish')),
        svcChip('🪔','Ayurvedic Massage','From ₹1199',_type=='ayurvedic',()=>setState(()=>_type='ayurvedic')),
        svcChip('🦶','Foot Reflexology','From ₹499',_type=='foot',()=>setState(()=>_type='foot')),
        svcChip('🤲','Head & Shoulder','From ₹399',_type=='head',()=>setState(()=>_type='head')),
        svcLabel('DURATION'),
        svcOptionGrid(title:'DURATION',options:[
          {'k':'45','l':'45 min','p':'85%'},{'k':'60','l':'60 min','p':'Base'},
          {'k':'90','l':'90 min','p':'+40%'},{'k':'120','l':'120 min','p':'+80%'},
        ],selected:_duration,onSelect:(v)=>setState(()=>_duration=v)),
        svcLabel('NUMBER OF PERSONS'),
        svcCounter('Persons','',_persons,1,4,(v)=>setState(()=>_persons=v)),
        const SizedBox(height:80),
      ])),
      svcBottomBar(ctx,true,_total,'SVC015','Full Body Massage','💆','Beauty & Grooming',_summary),
    ]));
}