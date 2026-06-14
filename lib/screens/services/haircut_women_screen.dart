import 'package:flutter/material.dart';
import '../../utils/theme.dart';
import 'service_widgets.dart';

class HaircutWomenScreen extends StatefulWidget {
  const HaircutWomenScreen({super.key});
  @override State<HaircutWomenScreen> createState() => _HaircutWomenState();
}
class _HaircutWomenState extends State<HaircutWomenScreen> {
  String _service = 'cut';
  bool _conditioning = false, _oilMassage = false;
  final _svcPx = {'cut':349,'blowdry':249,'wash':199,'trim':199,'treatment':599,'coloring':799};
  int get _total => _svcPx[_service]! + (_conditioning?199:0) + (_oilMassage?149:0);
  List<String> get _summary => [
    'Haircut (Women) > ${_sl(_service)}',
    if (_conditioning) 'Hair > Deep Conditioning +₹199',
    if (_oilMassage) 'Hair > Oil Massage +₹149',
  ];
  String _sl(String k) => {'cut':'Wash, Cut & Blow Dry','blowdry':'Blow Dry & Styling','wash':'Hair Wash & Dry','trim':'Hair Trim Only','treatment':'Hair Treatment','coloring':'Hair Coloring'}[k]!;
  @override
  Widget build(BuildContext ctx) => Scaffold(
    backgroundColor: AppColors.bg,
    appBar: AppBar(title: const Text('Haircut (Women)'), backgroundColor: AppColors.teal),
    body: Column(children: [
      Expanded(child: ListView(padding: const EdgeInsets.all(16), children: [
        svcHeader('💇','Haircut (Women)','Wash, cut, blow-dry & styling by certified stylist',const Color(0xFFAD1457)),
        const SizedBox(height:16),
        svcLabel('SERVICE'),
        svcChip('✂️','Wash, Cut & Blow Dry','₹349',_service=='cut',()=>setState(()=>_service='cut')),
        svcChip('💨','Blow Dry & Styling','₹249',_service=='blowdry',()=>setState(()=>_service='blowdry')),
        svcChip('🚿','Hair Wash & Dry Only','₹199',_service=='wash',()=>setState(()=>_service='wash')),
        svcChip('✂️','Hair Trim (no wash)','₹199',_service=='trim',()=>setState(()=>_service='trim')),
        svcChip('💆','Hair Treatment','₹599',_service=='treatment',()=>setState(()=>_service='treatment')),
        svcChip('🎨','Hair Coloring','₹799+',_service=='coloring',()=>setState(()=>_service='coloring')),
        svcLabel('ADD-ONS'),
        svcChip('🧴','Deep Conditioning','+ ₹199',_conditioning,()=>setState(()=>_conditioning=!_conditioning)),
        svcChip('🤲','Oil Massage (15 min)','+ ₹149',_oilMassage,()=>setState(()=>_oilMassage=!_oilMassage)),
        const SizedBox(height:80),
      ])),
      svcBottomBar(ctx,true,_total,'SVC014','Haircut (Women)','💇','Beauty & Grooming',_summary),
    ]));
}