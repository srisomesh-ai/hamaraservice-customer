import 'package:flutter/material.dart';
import 'theme.dart';

// Defensive parsing helpers — the API returns DECIMAL columns as strings and
// integer money columns as int or string.

int asInt(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is num) return v.round();
  final s = v.toString().trim();
  return int.tryParse(s) ?? double.tryParse(s)?.round() ?? 0;
}

double? asDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString().trim());
}

String asStr(dynamic v) => v == null ? '' : v.toString();

/// Backend booking statuses (bookings.php status machine).
class BookingStatus {
  static const searching = 'searching';
  static const priceQuoted = 'price_quoted';
  static const negotiating = 'negotiating';
  static const negotiationFinal = 'negotiation_final';
  static const confirmed = 'confirmed';
  static const active = 'active';
  static const completed = 'completed';
  static const cancelled = 'cancelled';

  /// Customer may cancel in these states.
  static const cancellable = [
    searching, priceQuoted, negotiating, negotiationFinal, confirmed
  ];
}

bool isPaid(Map<String, dynamic> b) => asStr(b['payment_status']) == 'paid';

/// Price to show for a booking: agreed amount first, then offers, then estimate.
int bookingPrice(Map<String, dynamic> b) {
  for (final k in ['amount', 'confirmed_price', 'final_price', 'quoted_price']) {
    final v = asInt(b[k]);
    if (v > 0) return v;
  }
  return asInt(b['est_price']);
}

String statusLabel(Map<String, dynamic> b) {
  final s = asStr(b['status']);
  switch (s) {
    case BookingStatus.searching:
      return 'Finding provider';
    case BookingStatus.priceQuoted:
      return 'Price quoted';
    case BookingStatus.negotiating:
      return 'Negotiating';
    case BookingStatus.negotiationFinal:
      return 'Final offer';
    case BookingStatus.confirmed:
      return 'Confirmed';
    case BookingStatus.active:
      return 'In progress';
    case BookingStatus.completed:
      return isPaid(b) ? 'Completed' : 'Payment due';
    case BookingStatus.cancelled:
      return 'Cancelled';
    default:
      return s.isEmpty ? 'Unknown' : s;
  }
}

Color statusColor(Map<String, dynamic> b) {
  switch (asStr(b['status'])) {
    case BookingStatus.searching:
      return AppColors.yellow;
    case BookingStatus.priceQuoted:
    case BookingStatus.negotiating:
    case BookingStatus.negotiationFinal:
      return AppColors.brand;
    case BookingStatus.confirmed:
      return AppColors.teal;
    case BookingStatus.active:
      return AppColors.brand;
    case BookingStatus.completed:
      return isPaid(b) ? AppColors.green : AppColors.yellow;
    case BookingStatus.cancelled:
      return AppColors.red;
    default:
      return AppColors.muted;
  }
}

/// "18 Oct 2026 · 09:00 AM" from slot_date (YYYY-MM-DD) + slot_time.
String slotLabel(Map<String, dynamic> b) {
  final d = asStr(b['slot_date']);
  final t = asStr(b['slot_time']);
  String date = d;
  final parsed = DateTime.tryParse(d);
  if (parsed != null) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    date = '${parsed.day} ${months[parsed.month - 1]} ${parsed.year}';
  }
  if (date.isEmpty) return t;
  if (t.isEmpty) return date;
  return '$date · $t';
}

String shortBookingId(String id) {
  final clean = id.replaceAll('-', '');
  if (id.startsWith('BK-')) return id;
  return clean.length > 8 ? clean.substring(0, 8).toUpperCase() : clean.toUpperCase();
}

/// Normalises an Indian mobile number to 10 digits (strips +91 / 0 prefix).
String normalizeIndianMobile(String input) {
  var digits = input.replaceAll(RegExp(r'\D'), '');
  if (digits.length == 12 && digits.startsWith('91')) digits = digits.substring(2);
  if (digits.length == 11 && digits.startsWith('0')) digits = digits.substring(1);
  return digits;
}

final RegExp indianMobileRegex = RegExp(r'^[6-9]\d{9}$');

bool isValidIndianMobile(String input) =>
    indianMobileRegex.hasMatch(normalizeIndianMobile(input));
