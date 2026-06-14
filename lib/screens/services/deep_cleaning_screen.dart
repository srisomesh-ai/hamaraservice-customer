import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../utils/theme.dart';
import 'service_widgets.dart';
import '../../services/service_price_service.dart';

class DeepCleaningScreen extends StatefulWidget {
  const DeepCleaningScreen({super.key});
  @override State<DeepCleaningScreen> createState() => _DeepCleaningState();
}
class _DeepCleaningState extends State<DeepCleaningScreen> {
  String _bhk = '2bhk';
  bool _kitchen = false;
  bool _bathroom = false;
  bool _windows = false;
  bool _sofa = false;

  int _p(String key) => ServicePriceService().getPrice('SVC002', key);
  int get _total {
    int t = _p(_bhk);
    if (_kitchen) t += _p('addon_kitchen');
    if (_bathroom) t += _p('addon_bathroom');
    if (_windows) t += _p('addon_windows');
    if (_sofa) t += _p('addon_sofa');
    return t;
  }
  List<String> get _summary => [
    'Deep Cleaning > ${_bl(_bhk)}',
    if (_kitchen) 'Deep Cleaning > Kitchen Deep Clean +₹499',
    if (_bathroom) 'Deep Cleaning > Extra Bathroom +₹299',
    if (_windows) 'Deep Cleaning > Windows & Glass +₹399',
    if (_sofa) 'Deep Cleaning > Sofa Cleaning +₹599',
  ];
  String _bl(String k) => {'studio':'Studio','1bhk':'1 BHK','2bhk':'2 BHK','3bhk':'3 BHK','4bhk':'4 BHK','villa':'Villa'}[k]!;

  @override
  Widget build(BuildContext ctx) => Scaffold(
    backgroundColor: AppColors.bg,
    appBar: AppBar(title: const Text('Deep House Cleaning'), backgroundColor: AppColors.teal),
    body: Column(children: [
      Expanded(child: ListView(padding: const EdgeInsets.all(16), children: [
        svcHeader('🫧','Deep House Cleaning','Full home deep clean — rooms, fans, windows',AppColors.teal),
        const SizedBox(height:16),
        svcLabel('SELECT HOME SIZE'),
        svcOptionGrid(title:'HOME SIZE',options:[
          {'k':'studio','l':'Studio','p':899},{'k':'1bhk','l':'1 BHK','p':1499},
          {'k':'2bhk','l':'2 BHK','p':2199},{'k':'3bhk','l':'3 BHK','p':2999},
          {'k':'4bhk','l':'4 BHK','p':3999},{'k':'villa','l':'Villa','p':5499},
        ],selected:_bhk,onSelect:(v)=>setState(()=>_bhk=v)),
        svcInfo('Includes all rooms, fans, switchboards & floors.'),
        svcLabel('ADD-ONS (Optional)'),
        svcChip('🍳','Kitchen Deep Clean','+ ₹\${_p("addon_kitchen")}',_kitchen,()=>setState(()=>_kitchen=!_kitchen)),
        svcChip('🚿','Extra Bathroom Deep Clean','+ ₹\${_p("addon_bathroom")}',_bathroom,()=>setState(()=>_bathroom=!_bathroom)),
        svcChip('🪟','Windows & Glass Cleaning','+ ₹\${_p("addon_windows")}',_windows,()=>setState(()=>_windows=!_windows)),
        svcChip('🛋️','Sofa / Upholstery Cleaning','+ ₹\${_p("addon_sofa")}',_sofa,()=>setState(()=>_sofa=!_sofa)),
        const SizedBox(height:80),
      ])),
      svcBottomBar(ctx,true,_total,'SVC002','Deep House Cleaning','🫧','Home Cleaning',_summary),
    ]));
}