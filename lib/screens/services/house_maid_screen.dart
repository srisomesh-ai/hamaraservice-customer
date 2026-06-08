import 'package:flutter/material.dart';
import '../../utils/theme.dart';
import '../booking/booking_flow_screen.dart';

class HouseMaidScreen extends StatefulWidget {
  const HouseMaidScreen({super.key});
  @override
  State<HouseMaidScreen> createState() => _HouseMaidScreenState();
}

class _HouseMaidScreenState extends State<HouseMaidScreen> {
  bool _sweep = false;
  bool _dust = false;
  bool _dishes = false;
  bool _clothes = false;
  bool _laundry = false;

  String _sweepBhk = '1bhk';
  String _dustBhk = '1bhk';
  String _dishOcc = 'daily';
  int _adultPairs = 10;
  int _kidsPairs = 10;

  final Map<String, int> _sweepPx = {'1bhk':149,'2bhk':249,'3bhk':349,'4bhk':449,'villa':599,'studio':99};
  final Map<String, int> _dustPx  = {'1bhk':199,'2bhk':329,'3bhk':449,'4bhk':579,'villa':749,'studio':149};
  final Map<String, int> _dishPx  = {'daily':149,'people':249,'event':499,'marriage':999};

  int get _total {
    int t = 0;
    if (_sweep && !_dust) t += _sweepPx[_sweepBhk]!;
    if (_dust) t += _dustPx[_dustBhk]!;
    if (_dishes) t += _dishPx[_dishOcc]!;
    if (_clothes) t += 99;
    if (_laundry) {
      final p = _adultPairs + _kidsPairs;
      t += p <= 10 ? 400 : 400 + ((p - 10) * 30);
    }
    return t;
  }

  bool get _any => _sweep || _dust || _dishes || _clothes || _laundry;

  List<String> get _summary {
    final s = <String>[];
    if (_sweep && !_dust) s.add('House Maid > Sweeping & Mopping > ${_bl(_sweepBhk)}');
    if (_dust) s.add('House Maid > Dusting > ${_bl(_dustBhk)}');
    if (_dishes) s.add('House Maid > Dishwashing > ${_dl(_dishOcc)}');
    if (_clothes) s.add('House Maid > Folding Clothes');
    if (_laundry) s.add('House Maid > Laundry (Washing)');
    return s;
  }

  String _bl(String k) => {'1bhk':'1 BHK','2bhk':'2 BHK','3bhk':'3 BHK','4bhk':'4 BHK','villa':'Villa','studio':'Studio'}[k]!;
  String _dl(String k) => {'daily':'Daily','people':'Small gathering','event':'Party / Event','marriage':'Marriage'}[k]!;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('House Maid'),
        backgroundColor: AppColors.teal,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _header(),
                const SizedBox(height: 16),
                _label('SELECT TASKS'),
                const SizedBox(height: 10),
                _chip('🧹', 'Sweeping & Mopping', 'From ₹149', _sweep, (v) => setState(() => _sweep = v)),
                if (_sweep && !_dust) _bhkPicker(_sweepBhk, _sweepPx, '🧹 Home Size', (v) => setState(() => _sweepBhk = v)),
                _chip('🪣', 'Dusting (incl. Sweeping)', 'From ₹199', _dust, (v) => setState(() => _dust = v)),
                if (_dust) ...[
                  _infoBox('Sweeping & mopping included automatically with dusting.'),
                  _bhkPicker(_dustBhk, _dustPx, '🪣 Home Size', (v) => setState(() => _dustBhk = v)),
                ],
                _chip('🍽️', 'Dishwashing', 'From ₹149', _dishes, (v) => setState(() => _dishes = v)),
                if (_dishes) _dishPicker(),
                _chip('👗', 'Folding Clothes', '₹99', _clothes, (v) => setState(() => _clothes = v)),
                _chip('🫧', 'Laundry (Washing)', 'From ₹400', _laundry, (v) => setState(() => _laundry = v)),
                if (_laundry) _laundryPicker(),
                const SizedBox(height: 80),
              ],
            ),
          ),
          _bottomBar(),
        ],
      ),
    );
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0D3D47), AppColors.teal],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(children: [
        const Text('🧹', style: TextStyle(fontSize: 36)),
        const SizedBox(width: 12),
        const Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('House Maid', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
            Text('Select tasks — price updates instantly', style: TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        )),
        const Row(children: [
          Icon(Icons.star_rounded, color: AppColors.yellow, size: 14),
          SizedBox(width: 4),
          Text('4.8', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
        ]),
      ]),
    );
  }

  Widget _label(String text) => Text(text,
    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.muted, letterSpacing: 0.8));

  Widget _infoBox(String text) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(color: AppColors.tealSoft, borderRadius: BorderRadius.circular(10)),
    child: Row(children: [
      const Icon(Icons.info_outline, color: AppColors.teal, size: 16),
      const SizedBox(width: 8),
      Expanded(child: Text(text, style: const TextStyle(fontSize: 12, color: AppColors.teal))),
    ]),
  );

  Widget _chip(String emoji, String name, String price, bool selected, ValueChanged<bool> onTap) {
    return GestureDetector(
      onTap: () => onTap(!selected),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? AppColors.tealSoft : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? AppColors.teal : AppColors.line, width: selected ? 2 : 1),
        ),
        child: Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 26)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: selected ? AppColors.teal : AppColors.ink)),
            Text(price, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          ])),
          Container(
            width: 24, height: 24,
            decoration: BoxDecoration(
              color: selected ? AppColors.teal : Colors.transparent,
              border: Border.all(color: selected ? AppColors.teal : AppColors.line, width: 2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: selected ? const Icon(Icons.check, color: Colors.white, size: 14) : null,
          ),
        ]),
      ),
    );
  }

  Widget _bhkPicker(String current, Map<String, int> prices, String title, ValueChanged<String> onSel) {
    const keys = ['1bhk','2bhk','3bhk','4bhk','villa','studio'];
    const lbl = {'1bhk':'1 BHK','2bhk':'2 BHK','3bhk':'3 BHK','4bhk':'4 BHK','villa':'Villa','studio':'Studio'};
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.muted)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: keys.map((k) {
          final sel = k == current;
          return GestureDetector(
            onTap: () => onSel(k),
            child: Container(
              width: 85,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              decoration: BoxDecoration(
                color: sel ? AppColors.brand : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: sel ? AppColors.brand : AppColors.line),
              ),
              child: Column(children: [
                Text(lbl[k]!, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: sel ? Colors.white : AppColors.ink)),
                const SizedBox(height: 2),
                Text('₹${prices[k]}', style: TextStyle(fontSize: 11, color: sel ? Colors.white70 : AppColors.muted)),
              ]),
            ),
          );
        }).toList()),
      ]),
    );
  }

  Widget _dishPicker() {
    final opts = [
      {'k':'daily','l':'Daily (home)','p':149},
      {'k':'people','l':'Small gathering','p':249},
      {'k':'event','l':'Party / Event','p':499},
      {'k':'marriage','l':'Marriage / Big fn','p':999},
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('OCCASION', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.muted)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: opts.map((o) {
          final sel = o['k'] == _dishOcc;
          return GestureDetector(
            onTap: () => setState(() => _dishOcc = o['k'] as String),
            child: Container(
              width: 140,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: sel ? AppColors.brand : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: sel ? AppColors.brand : AppColors.line),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(o['l'] as String, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: sel ? Colors.white : AppColors.ink)),
                const SizedBox(height: 4),
                Text('₹${o['p']}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: sel ? Colors.white70 : AppColors.teal)),
              ]),
            ),
          );
        }).toList()),
      ]),
    );
  }

  Widget _laundryPicker() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.line)),
      child: Column(children: [
        _ctr('👔 Adults clothes', _adultPairs, (v) => setState(() => _adultPairs = v)),
        const Divider(height: 20),
        _ctr('👕 Kids clothes', _kidsPairs, (v) => setState(() => _kidsPairs = v)),
        const SizedBox(height: 8),
        Text('Min. ₹400 for up to 10 pairs. ₹30 per extra pair.', style: const TextStyle(fontSize: 11, color: AppColors.muted)),
      ]),
    );
  }

  Widget _ctr(String title, int value, ValueChanged<int> onChange) {
    return Row(children: [
      Expanded(child: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ink))),
      GestureDetector(
        onTap: () { if (value > 0) onChange(value - 1); },
        child: Container(width: 32, height: 32, decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.remove, size: 16)),
      ),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('$value', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
      GestureDetector(
        onTap: () => onChange(value + 1),
        child: Container(width: 32, height: 32, decoration: BoxDecoration(color: AppColors.teal, borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.add, size: 16, color: Colors.white)),
      ),
    ]);
  }

  Widget _bottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      decoration: BoxDecoration(
        color: _any ? AppColors.teal : Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 12, offset: const Offset(0, -4))],
      ),
      child: _any
          ? Row(children: [
              Expanded(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('ESTIMATED TOTAL', style: TextStyle(fontSize: 10, color: Colors.white70, fontWeight: FontWeight.w700)),
                Text('₹$_total', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white)),
              ])),
              ElevatedButton(
                onPressed: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => BookingFlowScreen(service: {'id':'SVC001','icon':'🧹','name':'House Maid','cat':'Home Cleaning','color':0xFFE3F2FD}, basePrice: _total, summary: _summary),
                )),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.brand, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                child: const Text('Book Now →', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ])
          : const Center(child: Text('Select at least one task to book', style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600))),
    );
  }
}
