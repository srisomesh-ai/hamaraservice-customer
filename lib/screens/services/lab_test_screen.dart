import 'package:flutter/material.dart';
import '../../utils/theme.dart';
import 'service_widgets.dart';

class LabTestScreen extends StatefulWidget {
  const LabTestScreen({super.key});
  @override State<LabTestScreen> createState() => _LabTestState();
}
class _LabTestState extends State<LabTestScreen> {
  bool _blood = false, _urine = false, _stool = false, _swab = false, _bp = false;
  int _patients = 1;
  int get _sampleCount => (_blood?1:0)+(_urine?1:0)+(_stool?1:0)+(_swab?1:0)+(_bp?1:0);
  int get _basePrice => _sampleCount == 0 ? 0 : _sampleCount == 1 ? 199 : 199 + ((_sampleCount-1)*99);
  int get _total => _basePrice * _patients;
  bool get _any => _sampleCount > 0;
  List<String> get _summary => [
    if (_blood) 'Lab Test > Blood Sample Collection',
    if (_urine) 'Lab Test > Urine Sample',
    if (_stool) 'Lab Test > Stool Sample',
    if (_swab) 'Lab Test > Throat/Nasal Swab',
    if (_bp) 'Lab Test > BP & Vitals Check',
    'Lab Test > $_patients Patient${_patients>1?"s":""}',
  ];
  @override
  Widget build(BuildContext ctx) => Scaffold(
    backgroundColor: AppColors.bg,
    appBar: AppBar(title: const Text('Lab Test Collection'), backgroundColor: AppColors.teal),
    body: Column(children: [
      Expanded(child: ListView(padding: const EdgeInsets.all(16), children: [
        svcHeader('🧪','Lab Test Collection','Blood, urine & sample collection at doorstep',const Color(0xFF880E4F)),
        const SizedBox(height:16),
        svcInfo('₹199 for first sample · ₹99 per additional sample. Reports via WhatsApp.'),
        svcLabel('SELECT TESTS'),
        svcChip('🩸','Blood Sample','₹199',_blood,()=>setState(()=>_blood=!_blood)),
        svcChip('🫗','Urine Sample','₹99 (add-on)',_urine,()=>setState(()=>_urine=!_urine)),
        svcChip('🧫','Stool Sample','₹99 (add-on)',_stool,()=>setState(()=>_stool=!_stool)),
        svcChip('🦠','Throat / Nasal Swab','₹99 (add-on)',_swab,()=>setState(()=>_swab=!_swab)),
        svcChip('💊','BP & Vitals Check','₹99 (add-on)',_bp,()=>setState(()=>_bp=!_bp)),
        svcLabel('NUMBER OF PATIENTS'),
        svcCounter('Patients','',_patients,1,5,(v)=>setState(()=>_patients=v)),
        const SizedBox(height:80),
      ])),
      svcBottomBar(ctx,_any,_total,'SVC011','Lab Test Collection','🧪','Medical',_summary),
    ]));
}