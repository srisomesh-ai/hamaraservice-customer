import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../utils/theme.dart';
import '../booking/booking_flow_screen.dart';

// ─────────────────────────────────────────────────────────────
// SHARED WIDGETS used by ALL service screens
// ─────────────────────────────────────────────────────────────

/// Header banner for every service screen
Widget svcHeader(String emoji, String name, String subtitle, Color bgColor) {
  return Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [bgColor.withOpacity(0.9), AppColors.teal],
        begin: Alignment.topLeft, end: Alignment.bottomRight),
      borderRadius: BorderRadius.circular(16)),
    child: Row(children: [
      Text(emoji, style: const TextStyle(fontSize: 36)),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
        Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.white70)),
      ])),
      const Row(children: [
        Icon(Icons.star_rounded, color: AppColors.yellow, size: 14),
        SizedBox(width: 4),
        Text('4.8', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
      ]),
    ]));
}

/// Section label
Widget svcLabel(String text) => Padding(
  padding: const EdgeInsets.only(bottom: 10),
  child: Text(text, style: const TextStyle(
    fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.muted, letterSpacing: 0.8)));

/// Info box
Widget svcInfo(String text) => Container(
  margin: const EdgeInsets.only(bottom: 10),
  padding: const EdgeInsets.all(10),
  decoration: BoxDecoration(color: AppColors.tealSoft, borderRadius: BorderRadius.circular(10)),
  child: Row(children: [
    const Icon(Icons.info_outline, color: AppColors.teal, size: 16),
    const SizedBox(width: 8),
    Expanded(child: Text(text, style: const TextStyle(fontSize: 12, color: AppColors.teal))),
  ]));

/// Tap-to-select option chip
Widget svcChip(String emoji, String name, String priceLabel, bool selected, VoidCallback onTap) {
  return GestureDetector(
    onTap: () { HapticFeedback.selectionClick(); onTap(); },
    child: Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: selected ? AppColors.tealSoft : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: selected ? AppColors.teal : AppColors.line, width: selected ? 2 : 1)),
      child: Row(children: [
        Text(emoji, style: const TextStyle(fontSize: 26)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
            color: selected ? AppColors.teal : AppColors.ink)),
          Text(priceLabel, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
        ])),
        Container(width: 24, height: 24,
          decoration: BoxDecoration(
            color: selected ? AppColors.teal : Colors.transparent,
            border: Border.all(color: selected ? AppColors.teal : AppColors.line, width: 2),
            borderRadius: BorderRadius.circular(6)),
          child: selected ? const Icon(Icons.check, color: Colors.white, size: 14) : null),
      ])));
}

/// Option grid picker (e.g. BHK sizes, unit counts)
Widget svcOptionGrid({
  required String title,
  required List<Map<String, dynamic>> options, // [{k, l, p}]
  required String selected,
  required ValueChanged<String> onSelect,
  int crossCount = 3,
}) {
  return Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: AppColors.bg,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.line)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.muted)),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, children: options.map((o) {
        final sel = o['k'] == selected;
        return GestureDetector(
          onTap: () { HapticFeedback.selectionClick(); onSelect(o['k'] as String); },
          child: Container(
            width: 95,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            decoration: BoxDecoration(
              color: sel ? AppColors.brand : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: sel ? AppColors.brand : AppColors.line)),
            child: Column(children: [
              Text(o['l'] as String, textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                  color: sel ? Colors.white : AppColors.ink)),
              const SizedBox(height: 2),
              Text('₹${o['p']}', style: TextStyle(fontSize: 11,
                color: sel ? Colors.white70 : AppColors.muted)),
            ])));
      }).toList()),
    ]));
}

/// Counter widget (+ / -)
Widget svcCounter(String title, String subtitle, int value,
    int min, int max, ValueChanged<int> onChange) {
  return Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.line)),
    child: Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.ink)),
        if (subtitle.isNotEmpty)
          Text(subtitle, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
      ])),
      GestureDetector(
        onTap: () { if (value > min) { HapticFeedback.selectionClick(); onChange(value - 1); } },
        child: Container(width: 34, height: 34,
          decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(8)),
          child: const Icon(Icons.remove, size: 16))),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Text('$value', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
      GestureDetector(
        onTap: () { if (value < max) { HapticFeedback.selectionClick(); onChange(value + 1); } },
        child: Container(width: 34, height: 34,
          decoration: BoxDecoration(color: AppColors.teal, borderRadius: BorderRadius.circular(8)),
          child: const Icon(Icons.add, size: 16, color: Colors.white))),
    ]));
}

/// Bottom bar — shows total and Book Now button
Widget svcBottomBar(BuildContext ctx, bool hasSelection, int total,
    String svcId, String svcName, String icon, String cat, List<String> summary) {
  return Container(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
    decoration: BoxDecoration(
      color: hasSelection ? AppColors.teal : Colors.white,
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 12, offset: const Offset(0, -4))]),
    child: hasSelection
      ? Column(mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('ESTIMATED TOTAL', style: TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.w700)),
            Text('₹$total', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
          ]),
          const SizedBox(height: 10),
          SizedBox(width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                HapticFeedback.mediumImpact();
                Navigator.push(ctx, MaterialPageRoute(builder: (_) => BookingFlowScreen(
                  service: {'id': svcId, 'icon': icon, 'name': svcName, 'cat': cat, 'color': 0xFFE3F2FD},
                  basePrice: total, summary: summary)));
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brand,
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              child: const Text('Book Now →',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)))),
        ])
      : const Center(child: Text('Select at least one option to book',
          style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600))));
}
