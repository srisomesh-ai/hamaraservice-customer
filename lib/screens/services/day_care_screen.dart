import 'package:flutter/material.dart';
import '../../utils/theme.dart';
import 'service_widgets.dart';

class DayCareScreen extends StatefulWidget {
  const DayCareScreen({super.key});
  @override State<DayCareScreen> createState() => _DayCareState();
}
class _DayCareState extends State<DayCareScreen> {
  int _hours = 2;
  int _children = 1;
  String _type = 'general';
  final _typePx = {'general':200,'homework':250,'activity':280,'overnight':1500};
  int get _total => _type == 'overnight' ? _typePx[_type]! * _children
    : _typePx[_type]! * _hours * _children;
  List<String> get _summary => [
    'Day Care > $_children child${_children>1?"ren":""} · ${_type=="overnight"?"Overnight":"$_hours hrs"} · ${_tl(_type)}',
  ];
  String _tl(String k) => {'general':'General Care','homework':'Homework Help','activity':'Activity & Play','overnight':'Overnight Care'}[k]!;
  @override
  Widget build(BuildContext ctx) => Scaffold(
    backgroundColor: AppColors.bg,
    appBar: AppBar(title: const Text('Day Care Helper'), backgroundColor: AppColors.teal),
    body: Column(children: [
      Expanded(child: ListView(padding: const EdgeInsets.all(16), children: [
        svcHeader('🧒','Day Care Helper','Child supervision, play & activity assistance',const Color(0xFFE65100)),
        const SizedBox(height:16),
        svcLabel('CARE TYPE'),
        svcChip('🤱','General Supervision','₹200/hr',_type=='general',()=>setState(()=>_type='general')),
        svcChip('📚','Homework Help','₹250/hr',_type=='homework',()=>setState(()=>_type='homework')),
        svcChip('🎮','Activity & Play','₹280/hr',_type=='activity',()=>setState(()=>_type='activity')),
        svcChip('🌙','Overnight Care','₹1500/night',_type=='overnight',()=>setState(()=>_type='overnight')),
        if (_type != 'overnight') ...[
          svcLabel('HOURS'),
          svcCounter('Hours','',_hours,1,12,(v)=>setState(()=>_hours=v)),
        ],
        svcLabel('NUMBER OF CHILDREN'),
        svcCounter('Children','',_children,1,5,(v)=>setState(()=>_children=v)),
        svcInfo('Background-verified caregivers only.'),
        const SizedBox(height:80),
      ])),
      svcBottomBar(ctx,true,_total,'SVC016','Day Care Helper','🧒','Care Services',_summary),
    ]));
}