import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import '../../services/api_service.dart';
import '../../utils/theme.dart';
import 'booking_flow_screen.dart';

class ServiceDetailScreen extends StatefulWidget {
  final Map<String, dynamic> service;
  const ServiceDetailScreen({super.key, required this.service});

  @override
  State<ServiceDetailScreen> createState() => _ServiceDetailScreenState();
}

class _ServiceDetailScreenState extends State<ServiceDetailScreen> {
  int _price = 0;
  bool _loadingPrice = true;

  @override
  void initState() {
    super.initState();
    _loadPrice();
  }

  Future<void> _loadPrice() async {
    try {
      final svcId = widget.service['id'] as String;
      final snap = await FirebaseDatabase.instance.ref('hs_service_prices/$svcId').get();
      if (snap.exists) {
        final data = Map<String, dynamic>.from(snap.value as Map);
        // Try common price paths
        int price = 0;
        if (data['visit'] is Map) {
          final v = Map<String, dynamic>.from(data['visit'] as Map);
          if (v['visit'] != null) price = int.tryParse(v['visit'].toString()) ?? 0;
          else if (v['price'] != null) price = int.tryParse(v['price'].toString()) ?? 0;
        } else if (data['base'] != null) {
          price = int.tryParse(data['base'].toString()) ?? 0;
        }
        setState(() { _price = price; _loadingPrice = false; });
      } else {
        setState(() { _loadingPrice = false; });
      }
    } catch (e) {
      setState(() { _loadingPrice = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final svc = widget.service;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            backgroundColor: AppColors.teal,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: [Color(0xFF0D3D47), AppColors.teal],
                  ),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 40),
                      Container(
                        width: 80, height: 80,
                        decoration: BoxDecoration(
                          color: Color(svc['color'] as int),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Center(
                          child: Text(svc['icon'] as String, style: const TextStyle(fontSize: 42)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(svc['name'] as String,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
                      Text(svc['cat'] as String,
                        style: const TextStyle(fontSize: 13, color: Colors.white70)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Price card
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)],
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Starting from', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                              const SizedBox(height: 4),
                              _loadingPrice
                                ? const SizedBox(width: 80, height: 28, child: LinearProgressIndicator())
                                : Text(
                                    _price > 0 ? '₹$_price' : 'Price varies',
                                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.teal),
                                  ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.greenSoft,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.star_rounded, color: AppColors.yellow, size: 16),
                              SizedBox(width: 4),
                              Text('4.8 · 2,840 reviews',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.green)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // What's included
                  const Text("What's Included", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink)),
                  const SizedBox(height: 12),
                  ..._getIncludes(svc['id'] as String).map((item) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        Container(
                          width: 24, height: 24,
                          decoration: BoxDecoration(color: AppColors.greenSoft, shape: BoxShape.circle),
                          child: const Icon(Icons.check, color: AppColors.green, size: 14),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Text(item, style: const TextStyle(fontSize: 13, color: AppColors.ink2))),
                      ],
                    ),
                  )),

                  const SizedBox(height: 20),

                  // Why HamaraService
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.tealSoft,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Why HamaraService?', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.teal)),
                        const SizedBox(height: 12),
                        _whyRow(Icons.verified_user_rounded, 'Verified professionals'),
                        _whyRow(Icons.access_time_rounded, 'On-time service'),
                        _whyRow(Icons.thumb_up_rounded, 'Satisfaction guaranteed'),
                        _whyRow(Icons.support_agent_rounded, '24/7 customer support'),
                      ],
                    ),
                  ),

                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 12, offset: const Offset(0, -4))],
        ),
        child: ElevatedButton(
          onPressed: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => BookingFlowScreen(service: widget.service, basePrice: _price))),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: const Text('Book Now →', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }

  Widget _whyRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Icon(icon, size: 16, color: AppColors.teal),
        const SizedBox(width: 8),
        Text(text, style: const TextStyle(fontSize: 13, color: AppColors.teal)),
      ]),
    );
  }

  List<String> _getIncludes(String svcId) {
    final Map<String, List<String>> includes = {
      'SVC001': ['Sweeping & mopping floors', 'Dusting furniture & surfaces', 'Dishwashing', 'Folding clothes'],
      'SVC002': ['Deep scrubbing of all rooms', 'Bathroom & kitchen deep clean', 'Window cleaning', 'Furniture cleaning'],
      'SVC003': ['Toilet & basin scrubbing', 'Floor & wall cleaning', 'Tap & fixture descaling', 'Mirror cleaning'],
      'SVC004': ['Chimney & stove cleaning', 'Cabinet cleaning inside/out', 'Tile degreasing', 'Sink descaling'],
      'SVC005': ['Sofa shampooing', 'Carpet steam cleaning', 'Mattress cleaning', 'Stain removal'],
      'SVC006': ['Machine wash', 'Ironing & folding', 'Dry cleaning', 'Hand wash delicates'],
      'SVC007': ['AC filter cleaning', 'Cooling check', 'Gas refill if needed', 'Full service report'],
      'SVC008': ['Diagnosis of issue', 'Repair or replacement', 'Testing after repair', 'Warranty on work'],
      'SVC009': ['Wiring & switches', 'Fan & light fitting', 'Short circuit repair', 'Safety inspection'],
      'SVC010': ['Pipe repair & fitting', 'Tap & valve repair', 'Drainage unclogging', 'Waterproofing'],
    };
    return includes[svcId] ?? [
      'Professional service by verified expert',
      'Quality materials & equipment',
      'Satisfaction guaranteed',
      'Post-service cleanup',
    ];
  }
}