import 'package:flutter/material.dart';
import '../../utils/theme.dart';
import 'service_widgets.dart';

class CarWashScreen extends StatefulWidget {
  const CarWashScreen({super.key});
  @override State<CarWashScreen> createState() => _CarWashState();
}
class _CarWashState extends State<CarWashScreen> {
  String _pkg = 'basic';
  int _cars = 1;
  bool _engine = false, _polish = false, _interior = false;
  final _pkgPx = {'basic':299,'standard':499,'premium':799,'suv':999};
  int get _total => (_pkgPx[_pkg]! * _cars) + (_engine?499:0) + (_polish?399:0) + (_interior?299:0);
  List<String> get _summary => [
    'Car Wash > $_cars ${_pl(_pkg)} Wash${_cars>1?"es":""}',
    if (_engine) 'Car Wash > Engine Bay Cleaning +₹499',
    if (_polish) 'Car Wash > Polish & Wax +₹399',
    if (_interior) 'Car Wash > Interior Deep Clean +₹299',
  ];
  String _pl(String k) => {'basic':'Basic','standard':'Standard','premium':'Premium','suv':'SUV/7-Seater'}[k]!;
  @override
  Widget build(BuildContext ctx) => Scaffold(
    backgroundColor: AppColors.bg,
    appBar: AppBar(title: const Text('Car Wash'), backgroundColor: AppColors.teal),
    body: Column(children: [
      Expanded(child: ListView(padding: const EdgeInsets.all(16), children: [
        svcHeader('🚗','Car Wash','Exterior wash, vacuum & dashboard wipe',const Color(0xFF1B5E20)),
        const SizedBox(height:16),
        svcLabel('WASH PACKAGE'),
        svcOptionGrid(title:'PACKAGE',options:[
          {'k':'basic','l':'Basic','p':299},{'k':'standard','l':'Standard','p':499},
          {'k':'premium','l':'Premium','p':799},{'k':'suv','l':'SUV/MUV','p':999},
        ],selected:_pkg,onSelect:(v)=>setState(()=>_pkg=v)),
        svcInfo('Basic: Exterior wash · Standard: + Vacuum · Premium: + Dashboard · SUV: Large vehicle pricing'),
        svcLabel('NUMBER OF CARS'),
        svcCounter('Cars','Price multiplied per car',_cars,1,4,(v)=>setState(()=>_cars=v)),
        svcLabel('ADD-ONS'),
        svcChip('🔧','Engine Bay Cleaning','+ ₹499',_engine,()=>setState(()=>_engine=!_engine)),
        svcChip('✨','Polish & Wax','+ ₹399',_polish,()=>setState(()=>_polish=!_polish)),
        svcChip('🧹','Interior Deep Clean','+ ₹299',_interior,()=>setState(()=>_interior=!_interior)),
        const SizedBox(height:80),
      ])),
      svcBottomBar(ctx,true,_total,'SVC008','Car Wash','🚗','Vehicle Care',_summary),
    ]));
}