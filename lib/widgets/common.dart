import 'package:flutter/material.dart';
import '../services/hs_catalog.dart';
import '../utils/booking_format.dart';
import '../utils/service_visuals.dart';
import '../utils/theme.dart';

/// Square service illustration on a soft tinted background; falls back to
/// the category icon when the service has no image.
class ServiceImage extends StatelessWidget {
  final String svcId;
  final double size;
  final double radius;
  final EdgeInsets padding;
  const ServiceImage(this.svcId,
      {super.key, this.size = 48, this.radius = 12, this.padding = const EdgeInsets.all(4)});

  @override
  Widget build(BuildContext context) {
    final img = ServiceVisuals.image(svcId);
    final cat = HSCatalog.getById(svcId)?.cat ?? '';
    // Half the tile; tiles that fill their cell pass size: double.infinity.
    final fallback = LayoutBuilder(
        builder: (_, c) => Icon(ServiceVisuals.categoryIcons[cat] ?? Icons.home_repair_service_outlined,
            color: AppColors.teal,
            size: (size.isFinite ? size : c.biggest.shortestSide.isFinite ? c.biggest.shortestSide : 48) * 0.5));
    return Container(
      width: size,
      height: size,
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.tealSoft,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: img == null
          ? Center(child: fallback)
          : Image.asset(img,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Center(child: fallback)),
    );
  }
}

/// Section title used on every screen ("Home Cleaning", "Payment", …).
class SectionHeader extends StatelessWidget {
  final String title;
  final String? trailing;
  final EdgeInsets padding;
  const SectionHeader(this.title,
      {super.key, this.trailing, this.padding = const EdgeInsets.fromLTRB(16, 20, 16, 8)});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: padding,
      child: Row(children: [
        Expanded(child: Text(title, style: t.titleMedium)),
        if (trailing != null)
          Text(trailing!, style: t.labelMedium?.copyWith(color: AppColors.muted)),
      ]),
    );
  }
}

/// Centered empty / error state with an optional action.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 88,
            height: 88,
            decoration: const BoxDecoration(color: AppColors.tealSoft, shape: BoxShape.circle),
            child: Icon(icon, size: 40, color: AppColors.teal),
          ),
          const SizedBox(height: 20),
          Text(title, textAlign: TextAlign.center, style: t.titleMedium),
          const SizedBox(height: 6),
          Text(message,
              textAlign: TextAlign.center,
              style: t.bodyMedium?.copyWith(color: AppColors.muted)),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 20),
            FilledButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ]),
      ),
    );
  }
}

/// Colored pill showing a booking status.
class StatusChip extends StatelessWidget {
  final Map<String, dynamic> booking;
  const StatusChip(this.booking, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = statusColor(booking);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withOpacity(0.12),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(statusLabel(booking),
          style: Theme.of(context)
              .textTheme
              .labelMedium
              ?.copyWith(color: c, fontWeight: FontWeight.w700)),
    );
  }
}

enum Tone { info, success, warning, danger, neutral }

/// Tinted message banner (Material "alert" style).
class InfoBanner extends StatelessWidget {
  final String text;
  final IconData? icon;
  final Tone tone;
  final Widget? action;
  const InfoBanner(this.text,
      {super.key, this.icon, this.tone = Tone.info, this.action});

  static (Color, Color) colors(Tone t) {
    switch (t) {
      case Tone.success:
        return (AppColors.greenSoft, AppColors.green);
      case Tone.warning:
        return (AppColors.yellowSoft, AppColors.yellow);
      case Tone.danger:
        return (AppColors.redSoft, AppColors.red);
      case Tone.neutral:
        return (const Color(0xFFF0F3F4), AppColors.ink2);
      case Tone.info:
        return (AppColors.tealSoft, AppColors.teal2);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = colors(tone);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon ?? Icons.info_outline_rounded, color: fg, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(text,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: fg, height: 1.4, fontWeight: FontWeight.w500)),
            if (action != null) ...[const SizedBox(height: 8), action!],
          ]),
        ),
      ]),
    );
  }
}

/// Simple shimmer-free skeleton block for loading lists.
class SkeletonBox extends StatelessWidget {
  final double height;
  final double? width;
  final double radius;
  const SkeletonBox({super.key, required this.height, this.width, this.radius = 12});

  @override
  Widget build(BuildContext context) => Container(
        height: height,
        width: width,
        decoration: BoxDecoration(
          color: const Color(0xFFE9EEEF),
          borderRadius: BorderRadius.circular(radius),
        ),
      );
}

/// Loading placeholder for list screens: a few skeleton cards.
class SkeletonList extends StatelessWidget {
  final int count;
  const SkeletonList({super.key, this.count = 4});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: count,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, __) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            const SkeletonBox(height: 48, width: 48),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const SkeletonBox(height: 14, width: 140, radius: 6),
                const SizedBox(height: 10),
                SkeletonBox(height: 12, width: MediaQuery.of(context).size.width * 0.4, radius: 6),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Label/value row for detail cards.
class DetailRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final String? label;
  const DetailRow(this.icon, this.text, {super.key, this.label});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 20, color: AppColors.muted),
        const SizedBox(width: 12),
        Expanded(
          child: label == null
              ? Text(text, style: t.bodyMedium)
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label!, style: t.labelMedium?.copyWith(color: AppColors.muted)),
                  const SizedBox(height: 2),
                  Text(text, style: t.bodyMedium),
                ]),
        ),
      ]),
    );
  }
}
