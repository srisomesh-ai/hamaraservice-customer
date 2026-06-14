import 'package:flutter/material.dart';
import '../../utils/theme.dart';
import 'service_widgets.dart';
import '../../services/service_price_service.dart';

class HaircutMenScreen extends StatefulWidget {
  const HaircutMenScreen({super.key});
  @override State<HaircutMenScreen> createState() => _HaircutMenState();
}
class _HaircutMenState extends State<HaircutMenScreen> {
  String _style = 'regular';
  int _persons = 1;
  bool _beard = false, _massage = false;
  int _p(String key) => ServicePriceService().getPrice('SVC013', key);
  int get _total => (_p(_style) * _persons) + (_beard?_p('addon_beard')*_persons:0) + (_massage?_p('addon_massage'):0);
  List<String> get _summary => [
    'Haircut (Men) > $_persons × ${_sl(_style)}',
    if (_beard) 'Haircut > Beard Trim +₹${149*_persons}',
    if (_massage) 'Haircut > Head Massage +₹99',
  ];
  String _sl(String k) => {'regular':'Regular Cut','fade':'Fade/Taper Cut','design':'Design Cut','kids':'Kids Cut (≤10yr)'}[k]!;
  @override
  Widget build(BuildContext ctx) => Scaffold(
    backgroundColor: AppColors.bg,
    appBar: AppBar(title: const Text('Haircut (Men)'), backgroundColor: AppColors.teal),
    body: Column(children: [
      Expanded(child: ListView(padding: const EdgeInsets.all(16), children: [
        svcHeader('✂️','Haircut (Men)','Cut, trim, styling & finishing at home',const Color(0xFF1B5E20)),
        const SizedBox(height:16),
        svcLabel('CUT STYLE'),
        svcChip('💈','Regular Haircut','₹199',_style=='regular',()=>setState(()=>_style='regular')),
        svcChip('🎯','Fade / Taper Cut','₹299',_style=='fade',()=>setState(()=>_style='fade')),
        svcChip('🎨','Design / Pattern Cut','₹349',_style=='design',()=>setState(()=>_style='design')),
        svcChip('👦','Kids Cut (under 10)','₹149',_style=='kids',()=>setState(()=>_style='kids')),
        svcLabel('NUMBER OF PERSONS'),
        svcCounter('Persons','',_persons,1,6,(v)=>setState(()=>_persons=v)),
        svcLabel('ADD-ONS'),
        svcChip('🧔','Beard Trim & Shape','+ ₹149/person',_beard,()=>setState(()=>_beard=!_beard)),
        svcChip('🤲','Head Massage (10 min)','+ ₹99',_massage,()=>setState(()=>_massage=!_massage)),
        const SizedBox(height:80),
      ])),
      svcBottomBar(ctx,true,_total,'SVC013','Haircut (Men)','✂️','Beauty & Grooming',_summary),
    ]));
}