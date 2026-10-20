import 'dart:async';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../services/session.dart';
import '../../utils/booking_format.dart';
import '../../utils/theme.dart';
import '../../widgets/common.dart';
import '../login_screen.dart';

/// Bookings tab: booking history (bookings.php?action=history) split into
/// Active (open + completed-but-unpaid), Completed and Cancelled. Tapping a
/// booking opens the booking status screen.
class BookingsTab extends StatefulWidget {
  final List<Map<String, dynamic>>? preview;
  final ValueListenable<int>? refresh;
  final ValueChanged<String> onOpenBooking;
  final VoidCallback onBrowse;
  final VoidCallback onAuthChanged;
  const BookingsTab({
    super.key,
    this.preview,
    this.refresh,
    required this.onOpenBooking,
    required this.onBrowse,
    required this.onAuthChanged,
  });

  @override
  State<BookingsTab> createState() => _BookingsTabState();
}

class _BookingsTabState extends State<BookingsTab> {
  List<Map<String, dynamic>> _all = [];
  bool _loading = true;
  String _error = '';
  Timer? _timer;

  bool get _live => widget.preview == null;
  bool get _signedIn => !_live || Session.signedIn;

  @override
  void initState() {
    super.initState();
    if (!_live) {
      _all = widget.preview!;
      _loading = false;
      return;
    }
    widget.refresh?.addListener(_load);
    _load();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    widget.refresh?.removeListener(_load);
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!_live) return;
    if (!Session.signedIn) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (!silent && _all.isEmpty && mounted) setState(() => _loading = true);
    try {
      final list = await ApiService.getBookingHistory();
      if (mounted) {
        setState(() {
          _all = list;
          _loading = false;
          _error = '';
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.message; });
    }
  }

  static bool _isOpen(Map<String, dynamic> b) {
    final s = asStr(b['status']);
    if (s == BookingStatus.cancelled) return false;
    if (s == BookingStatus.completed) return !isPaid(b);
    return true;
  }

  Future<void> _signIn() async {
    final ok = await Navigator.push<bool>(context,
        MaterialPageRoute(builder: (_) => const LoginScreen(returnOnSuccess: true)));
    if (ok == true) {
      widget.onAuthChanged();
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final lists = [
      _all.where(_isOpen).toList(),
      _all.where((b) => asStr(b['status']) == BookingStatus.completed && isPaid(b)).toList(),
      _all.where((b) => asStr(b['status']) == BookingStatus.cancelled).toList(),
    ];
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My bookings'),
          bottom: _signedIn
              ? TabBar(tabs: [
                  Tab(text: 'Active${lists[0].isNotEmpty ? ' (${lists[0].length})' : ''}'),
                  const Tab(text: 'Completed'),
                  const Tab(text: 'Cancelled'),
                ])
              : null,
        ),
        body: !_signedIn
            ? EmptyState(
                icon: Icons.lock_outline_rounded,
                title: 'Sign in to see your bookings',
                message: 'Login or register to book services and track them here.',
                actionLabel: 'Login / Register',
                onAction: _signIn,
              )
            : _loading
                ? const SkeletonList()
                : TabBarView(children: [
                    _list(lists[0],
                        const EmptyState(
                          icon: Icons.event_available_outlined,
                          title: 'No active bookings',
                          message: 'Book a service from Home to get started.',
                        ),
                        browse: true),
                    _list(lists[1],
                        const EmptyState(
                          icon: Icons.task_alt_rounded,
                          title: 'No completed bookings',
                          message: 'Your completed jobs will appear here.',
                        )),
                    _list(lists[2],
                        const EmptyState(
                          icon: Icons.event_busy_outlined,
                          title: 'No cancelled bookings',
                          message: 'Cancelled jobs will appear here.',
                        )),
                  ]),
      ),
    );
  }

  Widget _list(List<Map<String, dynamic>> items, EmptyState empty, {bool browse = false}) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          if (_error.isNotEmpty) ...[
            InfoBanner(_error, tone: Tone.danger, icon: Icons.cloud_off_rounded),
            const SizedBox(height: 12),
          ],
          if (items.isEmpty)
            SizedBox(
              height: 420,
              child: browse
                  ? EmptyState(
                      icon: empty.icon,
                      title: empty.title,
                      message: empty.message,
                      actionLabel: 'Browse services',
                      onAction: widget.onBrowse,
                    )
                  : empty,
            ),
          for (final b in items) ...[
            BookingCard(b, onTap: () => widget.onOpenBooking(asStr(b['id']))),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

/// One booking in a list: service image, name, slot, price / provider and
/// a status chip.
class BookingCard extends StatelessWidget {
  final Map<String, dynamic> b;
  final VoidCallback onTap;
  const BookingCard(this.b, {super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final price = bookingPrice(b);
    final provider = asStr(b['other_party']);
    final st = asStr(b['status']);
    final paid = isPaid(b);
    String priceText = '';
    if (price > 0) {
      priceText = st == BookingStatus.completed
          ? (paid
              ? '₹$price paid${asStr(b['payment_method']).isNotEmpty ? ' · ${asStr(b['payment_method'])}' : ''}'
              : '₹$price due')
          : '₹$price';
    }
    final reason = asStr(b['cancel_reason']);
    final rating = asInt(b['rating']);
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ServiceImage(asStr(b['svc_id']), size: 56),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Text(
                        asStr(b['svc_name']).isEmpty ? 'Service' : asStr(b['svc_name']),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: t.titleSmall),
                  ),
                  const SizedBox(width: 8),
                  StatusChip(b),
                ]),
                const SizedBox(height: 4),
                Text(slotLabel(b),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodySmall?.copyWith(color: AppColors.muted)),
                if (priceText.isNotEmpty || provider.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(children: [
                    if (priceText.isNotEmpty)
                      Text(priceText,
                          style: t.labelLarge?.copyWith(
                              color: AppColors.teal2, fontWeight: FontWeight.w700)),
                    if (priceText.isNotEmpty && provider.isNotEmpty)
                      Text('  ·  ', style: t.bodySmall?.copyWith(color: AppColors.muted)),
                    if (provider.isNotEmpty)
                      Expanded(
                        child: Text(provider,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.bodySmall?.copyWith(color: AppColors.ink2)),
                      ),
                  ]),
                ],
                if (st == BookingStatus.cancelled && reason.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('Reason: $reason',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodySmall?.copyWith(color: AppColors.muted)),
                ],
                if (st == BookingStatus.completed && paid) ...[
                  const SizedBox(height: 4),
                  Row(children: [
                    Icon(rating > 0 ? Icons.star_rounded : Icons.star_outline_rounded,
                        size: 16, color: const Color(0xFFF5A623)),
                    const SizedBox(width: 4),
                    Text(rating > 0 ? 'You rated $rating/5' : 'Tap to rate this service',
                        style: t.bodySmall?.copyWith(color: AppColors.ink2)),
                  ]),
                ],
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
