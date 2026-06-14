import 'package:flutter/material.dart';
import '../../utils/theme.dart';
import 'service_widgets.dart';
import '../../services/service_price_service.dart';

class CookingScreen extends StatefulWidget {
  const CookingScreen({super.key});
  @override State<CookingScreen> createState() => _CookingState();
}
class _CookingState extends State<CookingScreen> {
  String _meal = 'lunch';
  int _persons = 2;
  bool _veg = true;
  bool _dishes = false;
  int _p(String key) => ServicePriceService().getPrice('SVC018', key);
  int get _personsAdd => _persons <= 2 ? 0 : (_persons - 2) * _p('extra_person');
  int get _total => _p(_meal) + _personsAdd + (_dishes ? _p('addon_dishes') : 0);
  List<String> get _summary => [
    'Cooking > ${_ml(_meal)} for $_persons · ${_veg?"Veg":"Non-Veg"}',
    if (_dishes) 'Cooking > Dishwashing After +₹99',
  ];
  String _ml(String k) => {'breakfast':'Breakfast','lunch':'Lunch','dinner':'Dinner','tiffin':'Tiffin Packing'}[k]!;
  @override
  Widget build(BuildContext ctx) => Scaffold(
    backgroundColor: AppColors.bg,
    appBar: AppBar(title: const Text('Cooking Service'), backgroundColor: AppColors.teal),
    body: Column(children: [
      Expanded(child: ListView(padding: const EdgeInsets.all(16), children: [
        svcHeader('🍱','Cooking (Per Meal)','Fresh home-cooked meals at your convenience',const Color(0xFFE65100)),
        const SizedBox(height:16),
        svcLabel('MEAL TYPE'),
        svcChip('☀️','Breakfast','₹199',_meal=='breakfast',()=>setState(()=>_meal='breakfast')),
        svcChip('🍛','Lunch','₹299',_meal=='lunch',()=>setState(()=>_meal='lunch')),
        svcChip('🌙','Dinner','₹299',_meal=='dinner',()=>setState(()=>_meal='dinner')),
        svcChip('📦','Tiffin Packing','₹149',_meal=='tiffin',()=>setState(()=>_meal='tiffin')),
        svcLabel('NUMBER OF PERSONS'),
        svcInfo('Base price for 2 persons. +₹50 per additional person.'),
        svcCounter('Persons','',_persons,1,10,(v)=>setState(()=>_persons=v)),
        svcLabel('FOOD PREFERENCE'),
        Row(children: [
          Expanded(child: GestureDetector(onTap:()=>setState(()=>_veg=true),
            child: Container(padding:const EdgeInsets.all(12),
              decoration:BoxDecoration(color:_veg?AppColors.greenSoft:Colors.white,
                border:Border.all(color:_veg?AppColors.green:AppColors.line),
                borderRadius:BorderRadius.circular(10)),
              child:const Row(mainAxisAlignment:MainAxisAlignment.center,children:[
                Text('🥦',style:TextStyle(fontSize:20)),SizedBox(width:8),
                Text('Veg',style:TextStyle(fontWeight:FontWeight.w700)),
              ])))),
          const SizedBox(width:10),
          Expanded(child: GestureDetector(onTap:()=>setState(()=>_veg=false),
            child: Container(padding:const EdgeInsets.all(12),
              decoration:BoxDecoration(color:!_veg?AppColors.redSoft:Colors.white,
                border:Border.all(color:!_veg?AppColors.red:AppColors.line),
                borderRadius:BorderRadius.circular(10)),
              child:const Row(mainAxisAlignment:MainAxisAlignment.center,children:[
                Text('🍗',style:TextStyle(fontSize:20)),SizedBox(width:8),
                Text('Non-Veg',style:TextStyle(fontWeight:FontWeight.w700)),
              ])))),
        ]),
        const SizedBox(height:12),
        svcLabel('ADD-ONS'),
        svcChip('🍽️','Dishwashing After Cooking','+ ₹99',_dishes,()=>setState(()=>_dishes=!_dishes)),
        const SizedBox(height:80),
      ])),
      svcBottomBar(ctx,true,_total,'SVC018','Cooking (Per Meal)','🍱','Cooking',_summary),
    ]));
}