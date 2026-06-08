import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../utils/theme.dart';
import '../../services/firebase_service.dart';
import '../booking/booking_flow_screen.dart';

class HouseMaidScreen extends StatefulWidget {
  const HouseMaidScreen({super.key});
  @override
  State<HouseMaidScreen> createState() => _HouseMaidScreenState();
}

class _HouseMaidScreenState extends State<HouseMaidScreen> {
  // Selected tasks
  final Map<String, bool> _selected = {
    'sweep': false, 'dust': false, 'dishes': false,
    'clothes': false, 'laundry': false,
  };

  // BHK selections
  String _sweepBhk = '1bhk';
  String _dustBhk  = '1bhk';
  String _dishOcc  = 'daily';

  // Laundry counters
  int _adultPairs = 10;
  int _kidsPairs  = 10;

  // Folding counter
  int _foldCount  = 20;

  // Prices from Firebase (overrides defaults)
  final Map<String, int> _sweepPrices = {'1bhk':149,'2bhk':249,'3bhk':349,'4bhk':449,'villa':599,'studio':99};
  final Map<String, int> _dustPrices  = {'1bhk':199,'2bhk':329,'3bhk':449,'4bhk':579,'villa':749,'studio':149};
  final Map<String, int> _dishPrices  = {'daily':149,'people':249,'event':499,'marriage':999};
  int _laundryMinPrice = 400;
  int _foldingMinPrice = 149;
  int _clothesBasePrice = 99;

  int get _total {
    int t = 0;
    if (_selected['sweep']! && !_selected['dust']!) {
      t += _sweepPrices[_sweepBhk] ?? 149;
    }
    if (_selected['dust']!) {
      t += _dustPrices[_dustBhk] ?? 199;
    }
    if (_selected['dishes']!) {
      t += _dishPrices[_dishOcc] ?? 149;
    }
    if (_selected['clothes']!) {
      t += _clothesBasePrice;
    }
    if (_selected['laundry']!) {
      final pairs = _adultPairs + _kidsPairs;
      t += pairs <= 10 ? _laundryMinPrice : _laundryMinPrice + ((pairs - 10) * 30);
    }
    return t;
  }

  bool get _hasSelection => _selected.values.any((v) => v);

  Map<String, dynamic> get _service => {
    'id': 'SVC001', 'icon': '🧹', 'name': 'House Maid',
    'cat': 'Home Cleaning', 'color': 0xFFE3F2FD,
  };

  List<String> get _summary {
    final List<String> s = [];
    if (_selected['sweep']! && !_selected['dust']!) {
      s.add('House Maid > Sweeping & Mopping > ${_bhkLabel(_sweepBhk)}');
    }
    if (_selected['dust']!) {
      s.add('House Maid > Dusting (incl. Sweep) > ${_bhkLabel(_dustBhk)}');
    }
    if (_selected['dishes']!) {
      s.add('House Maid > Dishwashing > ${_dishLabel(_dishOcc)}');
    }
    if (_selected['clothes']!) s.add('House Maid > Folding Clothes');
    if (_selected['laundry']!) s.add('House Maid > Laundry (Washing)');
    return s;
  }

  String _bhkLabel(String k) {
    const m = {'1bhk':'1 BHK','2bhk':'2 BHK','3bhk':'3 BHK','4bhk':'4 BHK','villa':'Villa / Bungalow','studio':'Studio / 1 Room'};
    return m[k] ?? k;
  }

  String _dishLabel(String k) {
    const m = {'daily':'Daily (home)','people':'Small gathering','event':'Party / Event','marriage':'Marriage / Big function'};
    return m[k] ?? k;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('House Maid'),
        backgroundColor: AppColors.teal,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header card
            Container(
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
                    Text('Select tasks below — price updates instantly', style: TextStyle(fontSize: 12, color: Colors.white70)),
                  ],
                )),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(20)),
                  child: const Row(children: [
                    Icon(Icons.star_rounded, color: AppColors.yellow, size: 14),
                    SizedBox(width: 4),
                    Text('4.8', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: 20),

            // Tasks section
            const Text('SELECT TASKS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.muted, letterSpacing: 0.8)),
            const SizedBox(height: 10),

            // Sweeping & Mopping
            _taskChip('sweep', '🧹', 'Sweeping & Mopping', 'From ₹${_sweepPrices['1bhk']}'),
            if (_selected['sweep']! && !_selected['dust']!) _bhkSelector(_sweepBhk, _sweepPrices, (v) => setState(() => _sweepBhk = v), '🧹 Home Size (for Sweeping & Mopping)'),

            // Dusting
            _taskChip('dust', '🪣', 'Dusting (incl. Sweeping & Mopping)', 'From ₹${_dustPrices['1bhk']}'),
            if (_selected['dust']!) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppColors.tealSoft, borderRadius: BorderRadius.circular(10)),
                child: const Row(children: [
                  Icon(Icons.info_outline, color: AppColors.teal, size: 16),
                  SizedBox(width: 8),
                  Expanded(child: Text('Dusting loosens dust — sweeping & mopping is included automatically.', style: TextStyle(fontSize: 12, color: AppColors.teal))),
                ]),
              ),
              _bhkSelector(_dustBhk, _dustPrices, (v) => setState(() => _dustBhk = v), '🪣 Home Size (for Dusting)'),
            ],

            // Dishwashing
            _taskChip('dishes', '🍽️', 'Dishwashing', 'From ₹${_dishPrices['daily']}'),
            if (_selected['dishes']!) _dishSelector(),

            // Folding Clothes
            _taskChip('clothes', '👗', 'Folding Clothes', '₹$_clothesBasePrice'),

            // Laundry
            _taskChip('laundry', '🫧', 'Laundry (Washing)', 'From ₹$_laundryMinPrice'),
            if (_selected['laundry']!) _laundryCounter(),

            const SizedBox(height: 100),
          ],
        ),
      ),

      // Bottom price bar
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        decoration: BoxDecoration(
          color: _hasSelection ? AppColors.teal : Colors.white,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 12, offset: const Offset(0, -4))],
        ),
        child: Row(children: [
          if (_hasSelection) ...[
            Expanded(child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('ESTIMATED TOTAL', style: TextStyle(fontSize: 10, color: Colors.white70, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                Text('₹$_total', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white)),
              ],
            )),
            ElevatedButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => BookingFlowScreen(
                  service: _service,
                  basePrice: _total,
                  summary: _summary,
                ),
              )),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brand,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('Book Now →', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ] else
            const Center(child: Text('Select at least one task to book', style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600))),
        ]),
      ),
    );
  }

  Widget _taskChip(String key, String emoji, String name, String price) {
    final selected = _selected[key]!;
    return GestureDetector(
      onTap: () => setState(() => _selected[key] = !selected),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? AppColors.tealSoft : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? AppColors.teal : AppColors.line, width: selected ? 2 : 1),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)],
        ),
        child: Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 28)),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: selected ? AppColors.teal : AppColors.ink)),
              Text(price, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
            ],
          )),
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

  Widget _bhkSelector(String current, Map<String, int> prices, ValueChanged<String> onSelect, String title) {
    const keys = ['1bhk','2bhk','3bhk','4bhk','villa','studio'];
    const labels = {'1bhk':'1 BHK','2bhk':'2 BHK','3bhk':'3 BHK','4bhk':'4 BHK','villa':'Villa /\nBungalow','studio':'Studio /\n1 Room'};
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.muted, letterSpacing: 0.5)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: keys.map((k) {
              final sel = k == current;
              return GestureDetector(
                onTap: () => onSelect(k),
                child: Container(
                  width: 90,
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                  decoration: BoxDecoration(
                    color: sel ? AppColors.brand : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: sel ? AppColors.brand : AppColors.line),
                  ),
                  child: Column(
                    children: [
                      Text(labels[k]!, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: sel ? Colors.white : AppColors.ink)),
                      const SizedBox(height: 2),
                      Text('₹${prices[k]}', style: TextStyle(fontSize: 11, color: sel ? Colors.white70 : AppColors.muted)),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _dishSelector() {
    final opts = [
      {'key':'daily','label':'Daily (home)','price':149},
      {'key':'people','label':'Small gathering\n(10–20 people)','price':249},
      {'key':'event','label':'Party / Event\n(20–50 people)','price':499},
      {'key':'marriage','label':'Marriage / Big\nfunction (50+)','price':999},
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('🍽️ OCCASION', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.muted, letterSpacing: 0.5)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: opts.map((o) {
              final sel = o['key'] == _dishOcc;
              return GestureDetector(
                onTap: () => setState(() => _dishOcc = o['key'] as String),
                child: Container(
                  width: 140,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: sel ? AppColors.brand : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: sel ? AppColors.brand : AppColors.line),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(o['label'] as String, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: sel ? Colors.white : AppColors.ink)),
                      const SizedBox(height: 4),
                      Text('₹${o['price']}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: sel ? Colors.white70 : AppColors.teal)),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _laundryCounter() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.line)),
      child: Column(
        children: [
          _counter('👔 Adults clothes', 'pairs (shirts, trousers, sarees…)', _adultPairs, (v) => setState(() => _adultPairs = v)),
          const Divider(height: 20),
          _counter('👕 Kids clothes', 'pairs (shirts, frocks, shorts…)', _kidsPairs, (v) => setState(() => _kidsPairs = v)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.line)),
            child: Text(
              _adultPairs + _kidsPairs <= 10
                  ? 'Minimum charge: ₹$_laundryMinPrice (up to 10 adults + 10 kids pairs)'
                  : 'Price: ₹${_adultPairs + _kidsPairs <= 10 ? _laundryMinPrice : _laundryMinPrice + ((_adultPairs + _kidsPairs - 10) * 30)}',
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _counter(String title, String subtitle, int value, ValueChanged<int> onChange) {
    return Row(children: [
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink)),
          Text(subtitle, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
        ],
      )),
      Row(children: [
        GestureDetector(
          onTap: () { if (value > 0) onChange(value - 1); },
          child: Container(
            width: 32, height: 32,
            decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.remove, size: 16),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text('$value', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        ),
        GestureDetector(
          onTap: () => onChange(value + 1),
          child: Container(
            width: 32, height: 32,
            decoration: BoxDecoration(color: AppColors.teal, borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.add, size: 16, color: Colors.white),
          ),
        ),
      ]),
    ]);
  }
}
