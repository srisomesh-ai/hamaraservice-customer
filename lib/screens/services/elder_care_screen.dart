import 'package:flutter/material.dart';
import '../../utils/theme.dart';
import 'service_widgets.dart';
import '../../services/service_price_service.dart';

class ElderCareScreen extends StatefulWidget {
  const ElderCareScreen({super.key});
  @override State<ElderCareScreen> createState() => _ElderCareState();
}
class _ElderCareState extends State<ElderCareScreen> {
  String _shift = 'half';
  String _type = 'companion';
  int _p(String key) => ServicePriceService().getPrice('SVC017', key);

  int get _total => _p('${_shift}_${_type}') > 0 ? _p('${_shift}_${_type}') : _p('${_shift}_companion');
  List<String> get _summary => ['Elder Care > ${_sl(_shift)} · ${_tl(_type)}'];
  String _sl(String k) => {'half':'Half Day (4hrs)','full':'Full Day (8hrs)','night':'Night Shift','24hr':'24 Hours'}[k]!;
  String _tl(String k) => {'companion':'Companionship','medical':'Medical Assistance','physio':'Physiotherapy Support','alzheimer':'Alzheimer/Dementia Care'}[k]!;
  @override
  Widget build(BuildContext ctx) => Scaffold(
    backgroundColor: AppColors.bg,
    appBar: AppBar(title: const Text('Elder Care Attendant'), backgroundColor: AppColors.teal),
    body: Column(children: [
      Expanded(child: ListView(padding: const EdgeInsets.all(16), children: [
        svcHeader('👴','Elder Care','Companionship, medication & mobility assistance',const Color(0xFF33691E)),
        const SizedBox(height:16),
        svcLabel('SHIFT'),
        svcOptionGrid(title:'SHIFT',options:[
          {'k':'half','l':'Half Day','p':499},{'k':'full','l':'Full Day','p':899},
          {'k':'night','l':'Night','p':799},{'k':'24hr','l':'24 Hours','p':1499},
        ],selected:_shift,onSelect:(v)=>setState(()=>_shift=v)),
        svcLabel('CARE TYPE'),
        svcChip('👥','Companionship & Basic Care','Base price',_type=='companion',()=>setState(()=>_type='companion')),
        svcChip('💊','Medical Assistance','+ ₹200',_type=='medical',()=>setState(()=>_type='medical')),
        svcChip('🏃','Physiotherapy Support','+ ₹300',_type=='physio',()=>setState(()=>_type='physio')),
        svcChip('🧠','Alzheimer / Dementia Care','+ ₹400',_type=='alzheimer',()=>setState(()=>_type='alzheimer')),
        svcInfo('All attendants are trained & background-verified.'),
        const SizedBox(height:80),
      ])),
      svcBottomBar(ctx,true,_total,'SVC017','Elder Care Attendant','👴','Care Services',_summary),
    ]));
}