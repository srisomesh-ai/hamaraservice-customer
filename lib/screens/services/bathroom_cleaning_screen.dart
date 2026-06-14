import 'package:flutter/material.dart';
import '../../utils/theme.dart';
import 'service_widgets.dart';

class BathroomCleaningScreen extends StatefulWidget {
  const BathroomCleaningScreen({super.key});
  @override State<BathroomCleaningScreen> createState() => _BathroomCleaningState();
}
class _BathroomCleaningState extends State<BathroomCleaningScreen> {
  int _count = 1;
  bool _deep = false, _exhaust = false, _tank = false;
  int get _basePrice => [0,399,699,999,1299][_count];
  int get _total => _basePrice + (_deep?200:0) + (_exhaust?150:0) + (_tank?299:0);
  List<String> get _summary => [
    'Bathroom Cleaning > $_count Bathroom${_count>1?"s":""}',
    if (_deep) 'Bathroom > Deep Scrub +₹200',
    if (_exhaust) 'Bathroom > Exhaust Fan +₹150',
    if (_tank) 'Bathroom > Water Tank Clean +₹299',
  ];
  @override
  Widget build(BuildContext ctx) => Scaffold(
    backgroundColor: AppColors.bg,
    appBar: AppBar(title: const Text('Bathroom Cleaning'), backgroundColor: AppColors.teal),
    body: Column(children: [
      Expanded(child: ListView(padding: const EdgeInsets.all(16), children: [
        svcHeader('🚿','Bathroom Cleaning','Tiles, fixtures, floor & toilet deep clean',AppColors.teal),
        const SizedBox(height:16),
        svcLabel('NUMBER OF BATHROOMS'),
        svcCounter('Bathrooms','1→₹399  2→₹699  3→₹999  4→₹1299',_count,1,4,(v)=>setState(()=>_count=v)),
        svcLabel('ADD-ONS'),
        svcChip('🧴','Deep Scrub & Stain Removal','+ ₹200',_deep,()=>setState(()=>_deep=!_deep)),
        svcChip('💨','Exhaust Fan Cleaning','+ ₹150',_exhaust,()=>setState(()=>_exhaust=!_exhaust)),
        svcChip('🪣','Water Tank Cleaning','+ ₹299',_tank,()=>setState(()=>_tank=!_tank)),
        const SizedBox(height:80),
      ])),
      svcBottomBar(ctx,true,_total,'SVC003','Bathroom Cleaning','🚿','Home Cleaning',_summary),
    ]));
}