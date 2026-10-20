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

// ── Provider price ranges (services.php?action=price_ranges) ──

/// "₹300 – ₹900" when approved providers set a range for the service
/// (provider_count > 0 and min > 0), otherwise ''. [r] is one entry of the
/// price_ranges map: {min, max, provider_count, admin_prices?}.
String priceRangeText(dynamic r) {
  if (r is! Map) return '';
  final mn = asInt(r['min']);
  final mx = asInt(r['max']);
  if (asInt(r['provider_count']) <= 0 || mn <= 0) return '';
  return mx > mn ? '₹$mn – ₹$mx' : '₹$mn';
}

/// "3 providers" / "1 provider".
String providerCountLabel(int n) => '$n provider${n == 1 ? '' : 's'}';

// ── Server times ──
// The API returns times as IST wall-clock strings "YYYY-MM-DD HH:MM:SS".

const Duration _istOffset = Duration(hours: 5, minutes: 30);

/// Parses a server time (IST) into an absolute DateTime (UTC), or null.
DateTime? parseServerTime(dynamic v) {
  final s = asStr(v).trim();
  if (s.isEmpty || s.startsWith('0000')) return null;
  return DateTime.tryParse('${s.replaceFirst(' ', 'T')}+05:30')?.toUtc();
}

/// "10:42 AM" (today) or "18 Oct, 10:42 AM", shown in IST.
String fmtServerTime(dynamic v) {
  final t = parseServerTime(v);
  if (t == null) return asStr(v);
  final ist = t.add(_istOffset);
  final now = DateTime.now().toUtc().add(_istOffset);
  final h = ist.hour % 12 == 0 ? 12 : ist.hour % 12;
  final time =
      '$h:${ist.minute.toString().padLeft(2, '0')} ${ist.hour < 12 ? 'AM' : 'PM'}';
  if (ist.year == now.year && ist.month == now.month && ist.day == now.day) {
    return time;
  }
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  return '${ist.day} ${months[ist.month - 1]}, $time';
}

/// "1 h 25 min" between two server times ([to] defaults to now), or ''.
String fmtWorkDuration(dynamic from, [dynamic to]) {
  final a = parseServerTime(from);
  final b = to == null ? DateTime.now().toUtc() : parseServerTime(to);
  if (a == null || b == null) return '';
  final secs = b.difference(a).inSeconds;
  if (secs < 0) return '';
  final h = secs ~/ 3600;
  final m = ((secs % 3600) / 60).round();
  return '${h > 0 ? '$h h ' : ''}$m min';
}

/// Cash is allowed unless the server says cash_allowed = 0 (older API
/// versions do not send the field).
bool cashAllowed(Map<String, dynamic> b) =>
    b['cash_allowed'] == null || asInt(b['cash_allowed']) == 1;
