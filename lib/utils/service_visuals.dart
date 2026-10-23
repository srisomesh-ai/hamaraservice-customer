import 'package:flutter/material.dart';
import '../services/hs_catalog.dart';
import 'booking_format.dart';

/// Images, category order and icons for the service catalog — same
/// categories and order as the web customer app (app/catalog.js).
class ServiceVisuals {
  static const Map<String, String> images = {
    'SVC001': 'assets/images/house-maid.jpg',
    'SVC002': 'assets/images/deep-cleaning.jpg',
    'SVC003': 'assets/images/bathroom-cleaning.jpg',
    'SVC004': 'assets/images/kitchen-cleaning.jpg',
    'SVC005': 'assets/images/sofa-carpet-cleaning.jpg',
    'SVC006': 'assets/images/laundry-ironing.jpg',
    'SVC007': 'assets/images/ac-service.jpg',
    'SVC010': 'assets/images/water-purifier.jpg',
    'SVC011': 'assets/images/plumber.jpg',
    'SVC012': 'assets/images/electrician.jpg',
    'SVC013': 'assets/images/carpenter.jpg',
    'SVC014': 'assets/images/painter.jpg',
    'SVC015': 'assets/images/cctv.jpg',
    'SVC016': 'assets/images/solar-panel.jpg',
    'SVC017': 'assets/images/car-wash.jpg',
    'SVC019': 'assets/images/mechanic.jpg',
    'SVC021': 'assets/images/pest-control.jpg',
    'SVC022': 'assets/images/cook.jpg',
    'SVC023': 'assets/images/haircut-men.jpg',
    'SVC024': 'assets/images/haircut-women.jpg',
    'SVC025': 'assets/images/massage.jpg',
    'SVC026': 'assets/images/fitness-trainer.jpg',
    'SVC027': 'assets/images/doctor-visit.jpg',
    'SVC028': 'assets/images/nurse-visit.jpg',
    'SVC029': 'assets/images/lab-test.jpg',
    'SVC030': 'assets/images/babysitter.jpg',
    'SVC031': 'assets/images/elderly-care.jpg',
    'SVC032': 'assets/images/gardener.jpg',
    'SVC033': 'assets/images/driver.jpg',
    'SVC034': 'assets/images/security-guard.jpg',
  };

  /// Category order of the web app (first appearance in catalog.js).
  static const List<String> categoryOrder = [
    'Home Cleaning',
    'Home Services',
    'Vehicle Care',
    'Pest Control',
    'Cooking',
    'Security',
    'Events & Media',
    'Outdoor',
    'Beauty & Wellness',
    'Health Services',
    'Care Services',
  ];

  static const Map<String, IconData> categoryIcons = {
    'Home Cleaning': Icons.cleaning_services_outlined,
    'Home Services': Icons.handyman_outlined,
    'Vehicle Care': Icons.directions_car_outlined,
    'Pest Control': Icons.pest_control_outlined,
    'Cooking': Icons.soup_kitchen_outlined,
    'Security': Icons.security_outlined,
    'Events & Media': Icons.mic_external_on_outlined,
    'Outdoor': Icons.yard_outlined,
    'Beauty & Wellness': Icons.spa_outlined,
    'Health Services': Icons.medical_services_outlined,
    'Care Services': Icons.volunteer_activism_outlined,
  };

  /// Services in web order: grouped by category, catalog order inside.
  static List<HSService> get ordered {
    final list = <HSService>[];
    for (final c in categoryOrder) {
      list.addAll(HSCatalog.services.where((s) => s.cat == c));
    }
    list.addAll(HSCatalog.services.where((s) => !categoryOrder.contains(s.cat)));
    return list;
  }

  static String? image(String svcId) => images[svcId];
}

/// Price line of a service tile — same rule as the web (tileHtml):
/// approved providers' range "₹min – ₹max" (+ "N providers"), otherwise
/// "from ₹X" where X = providers' min or the catalog base price (99 if unset).
class TilePrice {
  final String main; // "₹300 – ₹900" or "₹149"
  final bool from; // prefix with "from"
  final int providers; // 0 when no range
  const TilePrice(this.main, this.from, this.providers);

  factory TilePrice.of(HSService s, dynamic range) {
    final rt = priceRangeText(range);
    if (rt.isNotEmpty) return TilePrice(rt, false, asInt((range as Map)['provider_count']));
    final mn = range is Map ? asInt(range['min']) : 0;
    final pr = mn > 0 ? mn : (s.basePrice > 0 ? s.basePrice : 99);
    return TilePrice('₹$pr', true, 0);
  }

  /// One-line label used in compact places: "₹300 – ₹900 · 3 pros".
  String get line => from
      ? 'from $main'
      : '$main · $providers pro${providers == 1 ? '' : 's'}';
}
