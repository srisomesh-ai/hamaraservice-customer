import 'package:flutter/material.dart';
import '../../utils/theme.dart';
import 'service_widgets.dart';
import '../../services/service_price_service.dart';

class KitchenCleaningScreen extends StatefulWidget {
  const KitchenCleaningScreen({super.key});
  @override State<KitchenCleaningScreen> createState() => _KitchenCleaningState();
}
class _KitchenCleaningState extends State<KitchenCleaningScreen> {
  String _size = 'medium';
  bool _chimney = false, _fridge = false, _microwave = false, _cabinets = false;
  int _p(String key) => ServicePriceService().getPrice('SVC004', key);
  int get _total => _p(_size) + (_chimney?_p('addon_chimney'):0) + (_fridge?_p('addon_fridge'):0) + (_microwave?_p('addon_microwave'):0) + (_cabinets?_p('addon_cabinets'):0);
  List<String> get _summary => [
    'Kitchen Cleaning > ${_sl(_size)}',
    if (_chimney) 'Kitchen > Chimney Cleaning +₹349',
    if (_fridge) 'Kitchen > Fridge Deep Clean +₹199',
    if (_microwave) 'Kitchen > Microwave Clean +₹149',
    if (_cabinets) 'Kitchen > Cabinets & Shelves +₹299',
  ];
  String _sl(String k) => {'small':'Small Kitchen','medium':'Medium Kitchen','large':'Large Kitchen','commercial':'Commercial'}[k]!;
  @override
  Widget build(BuildContext ctx) => Scaffold(
    backgroundColor: AppColors.bg,
    appBar: AppBar(title: const Text('Kitchen Cleaning'), backgroundColor: AppColors.teal),
    body: Column(children: [
      Expanded(child: ListView(padding: const EdgeInsets.all(16), children: [
        svcHeader('🍳','Kitchen Cleaning','Chimney, stove, tiles, sink & counter deep clean',AppColors.teal),
        const SizedBox(height:16),
        svcLabel('KITCHEN SIZE'),
        svcOptionGrid(title:'KITCHEN SIZE',options:[
          {'k':'small','l':'Small','p':499},{'k':'medium','l':'Medium','p':699},
          {'k':'large','l':'Large','p':999},{'k':'commercial','l':'Commercial','p':1499},
        ],selected:_size,onSelect:(v)=>setState(()=>_size=v)),
        svcInfo('Includes stove, counter, tiles, sink & floor.'),
        svcLabel('ADD-ONS'),
        svcChip('🌀','Chimney Deep Clean','+ ₹349',_chimney,()=>setState(()=>_chimney=!_chimney)),
        svcChip('🧊','Fridge Deep Clean','+ ₹199',_fridge,()=>setState(()=>_fridge=!_fridge)),
        svcChip('📻','Microwave Clean','+ ₹149',_microwave,()=>setState(()=>_microwave=!_microwave)),
        svcChip('🗄️','Cabinets & Shelves','+ ₹299',_cabinets,()=>setState(()=>_cabinets=!_cabinets)),
        const SizedBox(height:80),
      ])),
      svcBottomBar(ctx,true,_total,'SVC004','Kitchen Cleaning','🍳','Home Cleaning',_summary),
    ]));
}