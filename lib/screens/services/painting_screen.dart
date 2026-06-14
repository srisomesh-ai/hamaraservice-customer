import 'package:flutter/material.dart';
import '../../utils/theme.dart';
import 'service_widgets.dart';
import '../../services/service_price_service.dart';

class PaintingScreen extends StatefulWidget {
  const PaintingScreen({super.key});
  @override State<PaintingScreen> createState() => _PaintingState();
}
class _PaintingState extends State<PaintingScreen> {
  String _scope = 'room';
  String _finish = 'emulsion';
  int _rooms = 1;
  bool _ceiling = false, _putty = false, _primer = false;
  int _p(String key) => ServicePriceService().getPrice('SVC025', key);

  int get _roomsMultiplier => _scope == 'room' ? _rooms : 1;
  int get _total => (_p(_scope) * _roomsMultiplier) + (_finish=='emulsion'?0:_p('finish_${_finish}')) + (_ceiling?_p('addon_ceiling')*_roomsMultiplier:0) + (_putty?_p('addon_putty')*_roomsMultiplier:0) + (_primer?_p('addon_primer')*_roomsMultiplier:0);
  List<String> get _summary => [
    'Painting > ${_sl(_scope)}${_scope=="room"?" × $_rooms rooms":""}',
    'Painting > ${_fl(_finish)} finish',
    if (_ceiling) 'Painting > Ceiling Painting +₹${500*_roomsMultiplier}',
    if (_putty) 'Painting > Wall Putty +₹${800*_roomsMultiplier}',
    if (_primer) 'Painting > Extra Primer Coat +₹${400*_roomsMultiplier}',
  ];
  String _sl(String k) => {'room':'Per Room','2bhk':'2 BHK Full','3bhk':'3 BHK Full','full':'Full Villa','exterior':'Exterior'}[k]!;
  String _fl(String k) => {'emulsion':'Standard Emulsion','premium':'Premium Emulsion','texture':'Texture Paint','weather':'Weatherproof'}[k]!;
  @override
  Widget build(BuildContext ctx) => Scaffold(
    backgroundColor: AppColors.bg,
    appBar: AppBar(title: const Text('Room Painting'), backgroundColor: AppColors.teal),
    body: Column(children: [
      Expanded(child: ListView(padding: const EdgeInsets.all(16), children: [
        svcHeader('🎨','Room Painting','Primer + 2 coats, dust sheet included',const Color(0xFF4527A0)),
        const SizedBox(height:16),
        svcLabel('PAINTING SCOPE'),
        svcChip('🏠','Per Room','₹1499/room',_scope=='room',()=>setState(()=>_scope='room')),
        svcChip('🏡','2 BHK Full','₹3999',_scope=='2bhk',()=>setState(()=>_scope='2bhk')),
        svcChip('🏘️','3 BHK Full','₹5499',_scope=='3bhk',()=>setState(()=>_scope='3bhk')),
        svcChip('🏰','Full Villa','₹7999',_scope=='full',()=>setState(()=>_scope='full')),
        svcChip('🏢','Exterior Painting','₹4999',_scope=='exterior',()=>setState(()=>_scope='exterior')),
        if (_scope == 'room') ...[
          svcLabel('NUMBER OF ROOMS'),
          svcCounter('Rooms','',_rooms,1,10,(v)=>setState(()=>_rooms=v)),
        ],
        svcLabel('PAINT FINISH'),
        svcOptionGrid(title:'FINISH',options:[
          {'k':'emulsion','l':'Standard','p':0},{'k':'premium','l':'Premium','p':'+800'},
          {'k':'texture','l':'Texture','p':'+1500'},{'k':'weather','l':'Weatherproof','p':'+1200'},
        ],selected:_finish,onSelect:(v)=>setState(()=>_finish=v)),
        svcLabel('ADD-ONS'),
        svcChip('⬜','Ceiling Painting','+ ₹500/room',_ceiling,()=>setState(()=>_ceiling=!_ceiling)),
        svcChip('🪣','Wall Putty (Smooth Finish)','+ ₹800/room',_putty,()=>setState(()=>_putty=!_putty)),
        svcChip('🖌️','Extra Primer Coat','+ ₹400/room',_primer,()=>setState(()=>_primer=!_primer)),
        svcInfo('Price includes labour only. Paint material extra if needed.'),
        const SizedBox(height:80),
      ])),
      svcBottomBar(ctx,true,_total,'SVC025','Room Painting','🎨','Painting',_summary),
    ]));
}