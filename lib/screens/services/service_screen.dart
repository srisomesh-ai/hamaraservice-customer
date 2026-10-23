import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/api_service.dart';
import '../../services/session.dart';
import '../../utils/booking_format.dart';
import '../../utils/service_visuals.dart';
import '../../utils/theme.dart';
import '../../services/hs_catalog.dart';
import '../../services/job_questions.dart';
import '../../widgets/common.dart';
import '../booking/booking_flow_screen.dart';
import '../login_screen.dart';
import '../support_screen.dart';

// ══════════════════════════════════════════════════════════════
// Service page — same options, prices and rules as the website service
// pages (svc-*.html): task cards with a size/occasion sub-group, or a
// visit-fee card; job questions; estimate + Book Now.
// ══════════════════════════════════════════════════════════════
class ServiceScreen extends StatefulWidget {
  final String svcId;
  final Map<String, dynamic> svcData;

  /// Test-only: reference prices {groupKey: {optionKey: price}} and the
  /// provider range; when set the screen does not call the API.
  final Map<String, dynamic>? previewPrices;
  final Map<String, dynamic>? previewRange;
  const ServiceScreen({
    super.key,
    required this.svcId,
    required this.svcData,
    this.previewPrices,
    this.previewRange,
  });
  @override
  State<ServiceScreen> createState() => _ServiceScreenState();
}

class _ServiceScreenState extends State<ServiceScreen> {
  HSService? _svc;
  Map<String, int> _prices = {};
  Map<String, dynamic>? _range; // approved providers' {min, max, provider_count}
  final Set<String> _selectedTasks = {}; // 'task_sweep', 'task_dust' ...
  final Map<String, String> _selectedBhk = {}; // groupKey → optionKey
  final Map<String, Set<String>> _answers = {}; // job question key → chosen options
  bool _loading = true;

  bool get _live => widget.previewPrices == null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _setPrices(Map<String, dynamic> grouped) {
    final flat = <String, int>{};
    grouped.forEach((groupKey, groupVal) {
      if (groupVal is Map) {
        groupVal.forEach((optKey, price) {
          final v = asInt(price); // may arrive as int, double or string
          if (v > 0) flat['${groupKey}_$optKey'] = v;
        });
      }
    });
    _prices = flat;
  }

  Future<void> _load() async {
    _svc = HSCatalog.getById(widget.svcId);
    if (_svc == null) {
      setState(() => _loading = false);
      return;
    }
    if (!_live) {
      _setPrices(widget.previewPrices!);
      _range = widget.previewRange;
    } else {
      _loadRange(); // independent of the reference prices
      try {
        _setPrices(await ApiService.getServicePrices(widget.svcId));
      } on ApiException catch (e) {
        if (mounted) showSnack(context, 'Could not load prices: ${e.message}', error: true);
      }
    }
    // Standalone single-select groups (incl. visit-only services) start
    // with their first option selected so the estimate is never empty.
    for (final g in _svc!.groups) {
      if (g.style == 'bhk' && g.showOn == null && g.items.isNotEmpty) {
        _selectedBhk[g.key] = g.items.first.key;
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadRange() async {
    try {
      final ranges = await ApiService.getServicePriceRanges();
      final r = ranges[widget.svcId];
      if (r is Map && mounted) {
        setState(() => _range = Map<String, dynamic>.from(r));
      }
    } on ApiException catch (e) {
      debugPrint('Price range failed: ${e.message}');
    }
  }

  int _p(String groupKey, String optKey) {
    // Direct price first, then admin min price as starting price
    final direct = _prices['${groupKey}_$optKey'] ?? 0;
    if (direct > 0) return direct;
    return _prices['${groupKey}_${optKey}_min'] ?? 0;
  }

  bool get _isVisitOnly =>
      _svc != null &&
      _svc!.groups.length == 1 &&
      _svc!.groups.first.style == 'bhk' &&
      _svc!.groups.first.showOn == null;

  /// Estimated total of everything selected. Task options are priced from
  /// their own group unless a size/occasion sub-group (showOn) prices them.
  int get _total {
    if (_svc == null) return 0;
    int t = 0;
    for (final g in _svc!.groups) {
      if (g.style == 'info') continue;
      if (g.style == 'task') {
        for (final o in g.items) {
          if (!_selectedTasks.contains('task_${o.key}')) continue;
          final hasSubGroup =
              _svc!.groups.any((sg) => sg.style == 'bhk' && sg.showOn == o.key);
          if (!hasSubGroup) t += _p(g.key, o.key);
        }
        continue;
      }
      if (g.style == 'bhk') {
        final show = g.showOn == null || _selectedTasks.contains('task_${g.showOn}');
        if (!show) continue;
        final sel = _selectedBhk[g.key] ?? '';
        if (sel.isNotEmpty) t += _p(g.key, sel);
      }
    }
    return t;
  }

  List<String> get _summary {
    if (_svc == null) return const [];
    final List<String> lines = [];
    for (final g in _svc!.groups) {
      if (g.style == 'task') {
        for (final o in g.items) {
          if (_selectedTasks.contains('task_${o.key}')) lines.add('${_svc!.name} > ${o.name}');
        }
      }
      if (g.style == 'bhk') {
        final show = g.showOn == null || _selectedTasks.contains('task_${g.showOn}');
        if (!show) continue;
        final sel = _selectedBhk[g.key] ?? '';
        final opt = g.items.where((o) => o.key == sel).firstOrNull;
        if (opt != null) lines.add('${g.title}: ${opt.name}');
      }
    }
    if (lines.isEmpty) lines.add(_svc!.name);
    // Job details for the provider: "No. of cameras: 5–8"
    for (final q in JobQuestions.forService(widget.svcId)) {
      final a = _answers[q.key];
      if (a != null && a.isNotEmpty) {
        lines.add('${q.label}: ${q.options.where(a.contains).join(', ')}');
      }
    }
    return lines;
  }

  JobQuestion? get _missingQuestion => JobQuestions.forService(widget.svcId)
      .where((q) => q.required && !(_answers[q.key]?.isNotEmpty ?? false))
      .firstOrNull;

  bool get _questionsDone => _missingQuestion == null;

  void _answer(JobQuestion q, String opt) {
    HapticFeedback.selectionClick();
    setState(() {
      final set = _answers.putIfAbsent(q.key, () => <String>{});
      if (q.multi) {
        set.contains(opt) ? set.remove(opt) : set.add(opt);
      } else {
        set
          ..clear()
          ..add(opt);
      }
    });
  }

  bool get _needsTask {
    if (_svc == null || _isVisitOnly) return false;
    // Tasks are mandatory only when they are the sole choice (e.g. House
    // Maid); otherwise they are optional add-ons to a standalone group.
    final hasStandalone = _svc!.groups.any((g) => g.style == 'bhk' && g.showOn == null);
    final hasTasks = _svc!.groups.any((g) => g.style == 'task');
    return hasTasks && !hasStandalone && _selectedTasks.isEmpty;
  }

  void _toggleTask(String taskKey) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedTasks.contains(taskKey)) {
        _selectedTasks.remove(taskKey);
        for (final g in _svc!.groups) {
          if ('task_${g.showOn}' == taskKey) _selectedBhk.remove(g.key);
        }
      } else {
        _selectedTasks.add(taskKey);
        for (final g in _svc!.groups) {
          if ('task_${g.showOn}' == taskKey && g.items.isNotEmpty) {
            _selectedBhk[g.key] = g.items.first.key;
          }
        }
      }
    });
  }

  void _selectBhk(String groupKey, String optKey) {
    HapticFeedback.selectionClick();
    setState(() => _selectedBhk[groupKey] = optKey);
  }

  Future<void> _book() async {
    HapticFeedback.mediumImpact();
    // Same checks and messages as the web (goAddress / createBooking).
    if (_needsTask) {
      showSnack(context, 'Select at least one task', error: true);
      return;
    }
    final miss = _missingQuestion;
    if (miss != null) {
      showSnack(context, 'Please answer: ${miss.q}', error: true);
      return;
    }
    if (!Session.signedIn) {
      final ok = await Navigator.push<bool>(context,
          MaterialPageRoute(builder: (_) => const LoginScreen(returnOnSuccess: true)));
      if (ok != true || !mounted) return;
      showSnack(context, 'Logged in — set your address', success: true);
    }
    if (!mounted) return;
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => BookingFlowScreen(
                service: {
                  ...widget.svcData,
                  'id': widget.svcId,
                  'name': _svc!.name,
                  'icon': _svc!.icon,
                  'cat': _svc!.cat
                },
                basePrice: _total,
                summary: _summary)));
  }

  // ── UI ─────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(asStr(widget.svcData['name']))),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_svc == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Service')),
        body: const EmptyState(
            icon: Icons.search_off_rounded,
            title: 'Service not found',
            message: 'This service is not available right now.'),
      );
    }
    final qs = JobQuestions.forService(widget.svcId);
    return Scaffold(
      body: CustomScrollView(slivers: [
        _header(context),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              _trustRow(context),
              if (priceRangeText(_range).isNotEmpty) ...[
                const SizedBox(height: 16),
                _rangeCard(context),
              ],
              const SizedBox(height: 8),
              if (_isVisitOnly) ...[
                const SizedBox(height: 8),
                _visitCard(context),
                const SizedBox(height: 12),
                const InfoBanner(
                  'How pricing works: nothing is charged when you book. The visit fee shown is an '
                  'estimate — after inspection the provider quotes the final price, which you accept '
                  'in the app before work starts. You pay after the service.',
                  icon: Icons.lightbulb_outline_rounded,
                  tone: Tone.warning,
                ),
              ] else
                ..._groups(context),
              if (qs.isNotEmpty) ...[
                const SizedBox(height: 16),
                _jobQuestions(context, qs),
              ],
              if (_isVisitOnly) ...[
                const SectionHeader('How it works', padding: EdgeInsets.fromLTRB(4, 24, 4, 8)),
                const Card(child: HowItWorks()),
              ],
            ]),
          ),
        ),
      ]),
      bottomNavigationBar: _bottomBar(context),
    );
  }

  Widget _header(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final img = ServiceVisuals.image(widget.svcId);
    return SliverAppBar(
      pinned: true,
      expandedHeight: 232,
      backgroundColor: AppColors.tealSoft,
      surfaceTintColor: AppColors.tealSoft,
      title: LayoutBuilder(builder: (ctx, c) {
        // Title only once the header has collapsed.
        final settings = ctx.dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>();
        final collapsed = settings == null ||
            settings.currentExtent <= settings.minExtent + 8;
        return AnimatedOpacity(
          opacity: collapsed ? 1 : 0,
          duration: const Duration(milliseconds: 150),
          child: Text(_svc!.name),
        );
      }),
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.parallax,
        background: Stack(fit: StackFit.expand, children: [
          if (img != null)
            Positioned(
              right: 8,
              bottom: 0,
              top: 56,
              child: Image.asset(img, fit: BoxFit.contain),
            )
          else
            Positioned(
              right: 28,
              bottom: 28,
              child: Icon(ServiceVisuals.categoryIcons[_svc!.cat] ?? Icons.home_repair_service_outlined,
                  size: 120, color: AppColors.teal.withValues(alpha: 0.35)),
            ),
          Positioned(
            left: 16,
            bottom: 20,
            right: 176,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(_svc!.cat,
                    style: t.labelMedium?.copyWith(color: AppColors.teal2, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 10),
              Text(_svc!.name,
                  maxLines: 3,
                  style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink)),
              const SizedBox(height: 4),
              Text('Admin-approved professionals at your doorstep',
                  style: t.bodySmall?.copyWith(color: AppColors.ink2)),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _trustRow(BuildContext context) {
    final t = Theme.of(context).textTheme;
    Widget item(IconData i, String s) => Expanded(
          child: Column(children: [
            Icon(i, color: AppColors.teal, size: 22),
            const SizedBox(height: 6),
            Text(s,
                textAlign: TextAlign.center,
                style: t.labelSmall?.copyWith(color: AppColors.ink2, fontWeight: FontWeight.w600)),
          ]),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          item(Icons.verified_outlined, 'Approved providers'),
          item(Icons.handshake_outlined, 'Price agreed before work'),
          item(Icons.lock_outline_rounded, 'OTP to start & finish'),
          item(Icons.payments_outlined, 'Pay after service'),
        ]),
      ),
    );
  }

  Widget _rangeCard(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final count = asInt(_range?['provider_count']);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.greenSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.engineering_outlined, color: AppColors.green),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${providerCountLabel(count)} charge ${priceRangeText(_range)}',
                style: t.titleSmall?.copyWith(color: AppColors.green)),
            const SizedBox(height: 2),
            Text('Estimate below · the provider confirms the final price before the job starts.',
                style: t.bodySmall?.copyWith(color: AppColors.ink2)),
          ]),
        ),
      ]),
    );
  }

  List<Widget> _groups(BuildContext context) {
    final out = <Widget>[];
    for (final g in _svc!.groups) {
      if (g.showOn != null) continue; // shown under its task
      if (g.style == 'bhk') out.add(_bhkSection(context, g));
      if (g.style == 'info') {
        out.add(Padding(
          padding: const EdgeInsets.only(top: 12),
          child: InfoBanner(g.info ?? g.title,
              icon: Icons.lightbulb_outline_rounded, tone: Tone.warning),
        ));
      }
      if (g.style == 'task') out.add(_taskGroup(context, g));
    }
    return out;
  }

  Widget _groupTitle(BuildContext context, String title, String hint) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
      child: Row(children: [
        Expanded(child: Text(title, style: t.titleMedium)),
        Text(hint, style: t.labelMedium?.copyWith(color: AppColors.muted)),
      ]),
    );
  }

  Widget _taskGroup(BuildContext context, HSGroup g) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _groupTitle(context, g.title, 'Select all that apply'),
      for (final opt in g.items) ...[
        _taskCard(context, g, opt),
        const SizedBox(height: 8),
      ],
    ]);
  }

  Widget _taskCard(BuildContext context, HSGroup g, HSOption opt) {
    final t = Theme.of(context).textTheme;
    final taskKey = 'task_${opt.key}';
    final on = _selectedTasks.contains(taskKey);
    final sub = _svc!.groups.where((x) => x.showOn == opt.key).firstOrNull;
    final price = sub == null ? _p(g.key, opt.key) : 0;
    return Card(
      color: on ? AppColors.tealSoft : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: on ? AppColors.teal : AppColors.line, width: on ? 1.5 : 1),
      ),
      child: Column(children: [
        InkWell(
          onTap: () => _toggleTask(taskKey),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
            child: Row(children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: on ? Colors.white : AppColors.bg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(opt.ico.isNotEmpty ? opt.ico : '✓', style: const TextStyle(fontSize: 22)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(opt.name, style: t.titleSmall),
                  if (price > 0)
                    Text('₹$price', style: t.labelLarge?.copyWith(color: AppColors.brand2)),
                ]),
              ),
              Checkbox(value: on, onChanged: (_) => _toggleTask(taskKey)),
            ]),
          ),
        ),
        if (on && sub != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: sub.style == 'info'
                ? InfoBanner(sub.info ?? sub.title,
                    icon: Icons.lightbulb_outline_rounded, tone: Tone.warning)
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
                      child: Row(children: [
                        Expanded(child: Text(sub.title, style: t.labelLarge?.copyWith(color: AppColors.teal2))),
                        const SizedBox(width: 8),
                        Text('Select one', style: t.labelSmall?.copyWith(color: AppColors.muted)),
                      ]),
                    ),
                    _optionGrid(sub),
                  ]),
          ),
      ]),
    );
  }

  Widget _bhkSection(BuildContext context, HSGroup g) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _groupTitle(context, g.title, 'Select one'),
      _optionGrid(g),
    ]);
  }

  Widget _optionGrid(HSGroup g) {
    return LayoutBuilder(builder: (ctx, c) {
      final w = (c.maxWidth - 8) / 2;
      return Wrap(spacing: 8, runSpacing: 8, children: [
        for (final o in g.items) SizedBox(width: w, child: _optionCard(ctx, g.key, o)),
      ]);
    });
  }

  Widget _optionCard(BuildContext context, String groupKey, HSOption o) {
    final t = Theme.of(context).textTheme;
    final on = _selectedBhk[groupKey] == o.key;
    final price = _p(groupKey, o.key);
    return Material(
      color: on ? AppColors.brandSoft : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: on ? AppColors.brand : AppColors.line, width: on ? 1.5 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _selectBhk(groupKey, o.key),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Column(children: [
            Text(o.name,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: t.labelLarge?.copyWith(color: AppColors.ink)),
            const SizedBox(height: 4),
            Text(price > 0 ? '₹$price' : 'On quote',
                style: t.titleMedium?.copyWith(
                    color: AppColors.teal2, fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
    );
  }

  Widget _visitCard(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final g = _svc!.groups.first;
    final selKey = _selectedBhk[g.key] ?? (g.items.isNotEmpty ? g.items.first.key : '');
    final price = selKey.isNotEmpty ? _p(g.key, selKey) : 0;
    Widget include(String s) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            const Icon(Icons.check_circle_rounded, color: AppColors.green, size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text(s, style: t.bodyMedium)),
          ]),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Visit / Call-out fee', style: t.titleMedium),
          const SizedBox(height: 12),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Est. visit fee', style: t.labelMedium?.copyWith(color: AppColors.muted)),
                Text(price > 0 ? '₹$price' : 'On quote',
                    style: t.headlineMedium?.copyWith(
                        color: AppColors.teal2, fontWeight: FontWeight.w700)),
                Text('Work charges quoted on-site',
                    style: t.bodySmall?.copyWith(color: AppColors.muted)),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('Charged now', style: t.labelMedium?.copyWith(color: AppColors.muted)),
              Text('₹0', style: t.titleLarge?.copyWith(color: AppColors.green)),
              Text('pay after service', style: t.bodySmall?.copyWith(color: AppColors.muted)),
            ]),
          ]),
          const Padding(padding: EdgeInsets.symmetric(vertical: 14), child: Divider()),
          Text("What's included", style: t.labelLarge?.copyWith(color: AppColors.muted)),
          const SizedBox(height: 10),
          include('Professional travels to your location'),
          include('Full inspection and diagnosis'),
          include('Transparent cost estimate before work'),
          include('Minor fixes completed on the spot'),
        ]),
      ),
    );
  }

  Widget _jobQuestions(BuildContext context, List<JobQuestion> qs) {
    final t = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Tell the provider about the job', style: t.titleMedium),
          const SizedBox(height: 2),
          Text('Helps the provider quote the right price before visiting.',
              style: t.bodySmall?.copyWith(color: AppColors.muted)),
          for (final q in qs) ...[
            const SizedBox(height: 16),
            Text.rich(
              TextSpan(children: [
                TextSpan(text: q.q, style: t.titleSmall),
                TextSpan(
                  text: q.multi
                      ? '  (select all that apply)'
                      : (q.required ? ' *' : '  (optional)'),
                  style: t.labelMedium?.copyWith(
                      color: q.required && !(_answers[q.key]?.isNotEmpty ?? false)
                          ? AppColors.red
                          : AppColors.muted),
                ),
              ]),
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final o in q.options)
                q.multi
                    ? FilterChip(
                        label: Text(o),
                        selected: _answers[q.key]?.contains(o) ?? false,
                        onSelected: (_) => _answer(q, o),
                      )
                    : ChoiceChip(
                        label: Text(o),
                        selected: _answers[q.key]?.contains(o) ?? false,
                        onSelected: (_) => _answer(q, o),
                      ),
            ]),
          ],
        ]),
      ),
    );
  }

  Widget _bottomBar(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final total = _total;
    final chips = <String>[];
    for (final g in _svc?.groups ?? const <HSGroup>[]) {
      if (g.style != 'task') continue;
      for (final o in g.items) {
        if (!_selectedTasks.contains('task_${o.key}')) continue;
        final bhkG = _svc!.groups.where((bg) => bg.showOn == o.key).firstOrNull;
        final sel = bhkG == null ? null : bhkG.items.where((bo) => bo.key == _selectedBhk[bhkG.key]).firstOrNull;
        chips.add('${o.name}${sel != null ? ' · ${sel.name}' : ''}');
      }
    }
    final hint = chips.isNotEmpty
        ? chips.join(', ')
        : !_questionsDone
            ? 'Answer the job questions above'
            : _needsTask
                ? 'Select tasks above'
                : 'Work charges quoted on-site';
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(children: [
            Expanded(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Estimate', style: t.labelMedium?.copyWith(color: AppColors.muted)),
                Text(total > 0 ? '₹$total' : 'On quote',
                    style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                Text(hint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodySmall?.copyWith(
                        color: !_questionsDone ? AppColors.red : AppColors.muted)),
              ]),
            ),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: _book,
              style: FilledButton.styleFrom(
                backgroundColor: (_needsTask || !_questionsDone) ? AppColors.muted : AppColors.teal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(_isVisitOnly ? 'Book Visit' : 'Book Now'),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward_rounded, size: 20),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
