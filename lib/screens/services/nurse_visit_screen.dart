import 'package:flutter/material.dart';
import '../../utils/theme.dart';
import 'service_widgets.dart';

class NurseVisitScreen extends StatefulWidget {
  const NurseVisitScreen({super.key});
  @override State<NurseVisitScreen> createState() => _NurseVisitState();
}
class _NurseVisitState extends State<NurseVisitScreen> {
  String _service = 'injection';
  int _days = 1;
  final _svcPx = {'injection':399,'dressing':499,'iv':799,'catheter':699,'vitals':299,'icu':1499};
  int get _total => _svcPx[_service]! * _days;
  List<String> get _summary => ['Nurse Visit > ${_sl(_service)} × $_days day${_days>1?"s":""}'];
  String _sl(String k) => {'injection':'Injection','dressing':'Wound Dressing','iv':'IV Drip','catheter':'Catheter Care','vitals':'Vitals Monitoring','icu':'ICU-Level Care'}[k]!;
  @override
  Widget build(BuildContext ctx) => Scaffold(
    backgroundColor: AppColors.bg,
    appBar: AppBar(title: const Text('Nurse Visit'), backgroundColor: AppColors.teal),
    body: Column(children: [
      Expanded(child: ListView(padding: const EdgeInsets.all(16), children: [
        svcHeader('💉','Nurse Visit','Injection, dressing, IV drip & vitals monitoring',const Color(0xFFB71C1C)),
        const SizedBox(height:16),
        svcInfo('All nurses are GNM/B.Sc Nursing certified.'),
        svcLabel('SERVICE TYPE'),
        svcChip('💉','Injection Administration','₹399/visit',_service=='injection',()=>setState(()=>_service='injection')),
        svcChip('🩹','Wound Dressing','₹499/visit',_service=='dressing',()=>setState(()=>_service='dressing')),
        svcChip('🩸','IV Drip / Saline','₹799/visit',_service=='iv',()=>setState(()=>_service='iv')),
        svcChip('🏥','Catheter Care','₹699/visit',_service=='catheter',()=>setState(()=>_service='catheter')),
        svcChip('📊','Vitals Monitoring (1hr)','₹299/visit',_service=='vitals',()=>setState(()=>_service='vitals')),
        svcChip('🛏️','ICU-Level Home Care','₹1499/visit',_service=='icu',()=>setState(()=>_service='icu')),
        svcLabel('NUMBER OF DAYS / VISITS'),
        svcCounter('Days/Visits','',_days,1,30,(v)=>setState(()=>_days=v)),
        const SizedBox(height:80),
      ])),
      svcBottomBar(ctx,true,_total,'SVC012','Nurse Visit','💉','Medical',_summary),
    ]));
}