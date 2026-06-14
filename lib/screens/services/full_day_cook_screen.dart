import 'package:flutter/material.dart';
import '../../utils/theme.dart';
import 'service_widgets.dart';

class FullDayCookScreen extends StatefulWidget {
  const FullDayCookScreen({super.key});
  @override State<FullDayCookScreen> createState() => _FullDayCookState();
}
class _FullDayCookState extends State<FullDayCookScreen> {
  int _persons = 4;
  int _days = 1;
  bool _veg = true;
  bool _cleaning = true;
  bool _special = false;
  int get _base => _persons <= 4 ? 799 : 799 + ((_persons-4)*100);
  int get _total => (_base * _days) + (_special?300*_days:0);
  List<String> get _summary => [
    'Full-Day Cook > $_days day${_days>1?"s":""} · $_persons persons · ${_veg?"Veg":"Non-Veg"}',
    'Full-Day Cook > All 3 meals${_cleaning?" + Kitchen Clean":""}',
    if (_special) 'Full-Day Cook > Special/Festive Dishes +₹${300*_days}',
  ];
  @override
  Widget build(BuildContext ctx) => Scaffold(
    backgroundColor: AppColors.bg,
    appBar: AppBar(title: const Text('Full-Day Cook'), backgroundColor: AppColors.teal),
    body: Column(children: [
      Expanded(child: ListView(padding: const EdgeInsets.all(16), children: [
        svcHeader('👨‍🍳','Full-Day Cook','All 3 meals + kitchen cleaning · 6-8 hrs',const Color(0xFFBF360C)),
        const SizedBox(height:16),
        svcInfo('Base price for 4 persons · +₹100 per extra person · Includes breakfast, lunch & dinner.'),
        svcLabel('NUMBER OF PERSONS'),
        svcCounter('Family Members / Persons','',_persons,1,20,(v)=>setState(()=>_persons=v)),
        svcLabel('NUMBER OF DAYS'),
        svcCounter('Days','Book multiple days for better availability',_days,1,30,(v)=>setState(()=>_days=v)),
        svcLabel('FOOD PREFERENCE'),
        Row(children:[
          Expanded(child:GestureDetector(onTap:()=>setState(()=>_veg=true),
            child:Container(padding:const EdgeInsets.all(12),
              decoration:BoxDecoration(color:_veg?AppColors.greenSoft:Colors.white,
                border:Border.all(color:_veg?AppColors.green:AppColors.line),borderRadius:BorderRadius.circular(10)),
              child:const Row(mainAxisAlignment:MainAxisAlignment.center,children:[Text('🥦',style:TextStyle(fontSize:20)),SizedBox(width:8),Text('Veg',style:TextStyle(fontWeight:FontWeight.w700))])))),
          const SizedBox(width:10),
          Expanded(child:GestureDetector(onTap:()=>setState(()=>_veg=false),
            child:Container(padding:const EdgeInsets.all(12),
              decoration:BoxDecoration(color:!_veg?AppColors.redSoft:Colors.white,
                border:Border.all(color:!_veg?AppColors.red:AppColors.line),borderRadius:BorderRadius.circular(10)),
              child:const Row(mainAxisAlignment:MainAxisAlignment.center,children:[Text('🍗',style:TextStyle(fontSize:20)),SizedBox(width:8),Text('Non-Veg',style:TextStyle(fontWeight:FontWeight.w700))])))),
        ]),
        const SizedBox(height:12),
        svcLabel('OPTIONS'),
        svcChip('🎉','Special / Festive Dishes','+ ₹300/day',_special,()=>setState(()=>_special=!_special)),
        const SizedBox(height:80),
      ])),
      svcBottomBar(ctx,true,_total,'SVC019','Full-Day Cook','👨‍🍳','Cooking',_summary),
    ]));
}