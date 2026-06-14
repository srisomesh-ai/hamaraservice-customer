import 'package:flutter/material.dart';
import '../../utils/theme.dart';
import 'service_widgets.dart';
import '../../services/service_price_service.dart';

class BikeWashScreen extends StatefulWidget {
  const BikeWashScreen({super.key});
  @override State<BikeWashScreen> createState() => _BikeWashState();
}
class _BikeWashState extends State<BikeWashScreen> {
  String _type = 'bike';
  int _count = 1;
  bool _chain = false, _polish = false;
  int _p(String key) => ServicePriceService().getPrice('SVC009', key);
  int get _total => (_p(_type) * _count) + (_chain?_p('addon_chain'):0) + (_polish?_p('addon_polish'):0);
  List<String> get _summary => [
    'Bike Wash > $_count ${_tl(_type)}',
    if (_chain) 'Bike Wash > Chain Clean & Lube +₹99',
    if (_polish) 'Bike Wash > Polish & Shine +₹149',
  ];
  String _tl(String k) => {'bike':'Motorcycle','scooter':'Scooter','sport':'Sports Bike','electric':'Electric Bike'}[k]!;
  @override
  Widget build(BuildContext ctx) => Scaffold(
    backgroundColor: AppColors.bg,
    appBar: AppBar(title: const Text('Bike Wash'), backgroundColor: AppColors.teal),
    body: Column(children: [
      Expanded(child: ListView(padding: const EdgeInsets.all(16), children: [
        svcHeader('🏍️','Bike Wash','Full exterior wash, chain clean & tyre polish',const Color(0xFF4A148C)),
        const SizedBox(height:16),
        svcLabel('VEHICLE TYPE'),
        svcOptionGrid(title:'TYPE',options:[
          {'k':'bike','l':'Bike','p':199},{'k':'scooter','l':'Scooter','p':199},
          {'k':'sport','l':'Sport Bike','p':299},{'k':'electric','l':'E-Bike','p':249},
        ],selected:_type,onSelect:(v)=>setState(()=>_type=v)),
        svcLabel('NUMBER OF VEHICLES'),
        svcCounter('Bikes/Scooters','',_count,1,5,(v)=>setState(()=>_count=v)),
        svcLabel('ADD-ONS'),
        svcChip('⛓️','Chain Clean & Lube','+ ₹99',_chain,()=>setState(()=>_chain=!_chain)),
        svcChip('✨','Polish & Shine','+ ₹149',_polish,()=>setState(()=>_polish=!_polish)),
        const SizedBox(height:80),
      ])),
      svcBottomBar(ctx,true,_total,'SVC009','Bike Wash','🏍️','Vehicle Care',_summary),
    ]));
}