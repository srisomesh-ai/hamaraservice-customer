import 'package:flutter/material.dart';
import '../../utils/theme.dart';
import 'service_widgets.dart';
import '../../services/service_price_service.dart';

class DoctorVisitScreen extends StatefulWidget {
  const DoctorVisitScreen({super.key});
  @override State<DoctorVisitScreen> createState() => _DoctorVisitState();
}
class _DoctorVisitState extends State<DoctorVisitScreen> {
  String _type = 'gp';
  int _patients = 1;
  bool _prescription = false, _report = false;
  int _p(String key) => ServicePriceService().getPrice('SVC010', key);
  int get _total => (_p(_type) * _patients) + (_report?_p('addon_report'):0);
  List<String> get _summary => [
    'Doctor Visit > $_patients ${_tl(_type)} Consultation',
    if (_report) 'Doctor > Medical Report Writing +₹199',
  ];
  String _tl(String k) => {'gp':'General Physician','pediatric':'Pediatrician','senior':'Senior Care','specialist':'Specialist'}[k]!;
  @override
  Widget build(BuildContext ctx) => Scaffold(
    backgroundColor: AppColors.bg,
    appBar: AppBar(title: const Text('Doctor Visit'), backgroundColor: AppColors.teal),
    body: Column(children: [
      Expanded(child: ListView(padding: const EdgeInsets.all(16), children: [
        svcHeader('👨‍⚕️','Doctor Home Visit','In-home consultation, prescription & vitals',const Color(0xFF1A237E)),
        const SizedBox(height:16),
        svcInfo('All doctors are MBBS certified & verified.'),
        svcLabel('DOCTOR TYPE'),
        svcChip('🩺','General Physician (GP)','₹699/visit',_type=='gp',()=>setState(()=>_type='gp')),
        svcChip('👶','Pediatrician (Children)','₹799/visit',_type=='pediatric',()=>setState(()=>_type='pediatric')),
        svcChip('👴','Senior Care Physician','₹799/visit',_type=='senior',()=>setState(()=>_type='senior')),
        svcChip('🔬','Specialist Consultation','₹999/visit',_type=='specialist',()=>setState(()=>_type='specialist')),
        svcLabel('NUMBER OF PATIENTS'),
        svcCounter('Patients','',_patients,1,5,(v)=>setState(()=>_patients=v)),
        svcLabel('ADD-ONS'),
        svcChip('📋','Detailed Medical Report','+ ₹199',_report,()=>setState(()=>_report=!_report)),
        const SizedBox(height:80),
      ])),
      svcBottomBar(ctx,true,_total,'SVC010','Doctor Visit','👨‍⚕️','Medical',_summary),
    ]));
}