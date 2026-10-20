import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import 'theme.dart';

// ─────────────────────────────────────────────────────────────
// Support — WhatsApp chat with HamaraService support (number from
// site.php?action=config), e-mail when no WhatsApp number is set.
// Same message format as the website's HS_support().
// ─────────────────────────────────────────────────────────────

const String _fallbackSupportEmail = 'info@hamaraservice.com';

/// Opens support. [about] text is added to the message, e.g.
/// "Booking BK-123." or "Customer ID abc.".
Future<void> openSupport(BuildContext ctx, {String about = ''}) async {
  final messenger = ScaffoldMessenger.maybeOf(ctx);
  var text = about.trim();
  if (text.isEmpty) {
    final me = await ApiService.getCachedUser();
    final id = (me?['id'] ?? '').toString();
    if (id.isNotEmpty) text = 'Customer ID $id.';
  }
  final msg = 'Hi HamaraService support, I am a customer.'
      '${text.isNotEmpty ? ' $text' : ''} I need help with: ';
  final cfg = await ApiService.getSiteConfig();
  final wa = (cfg['support_whatsapp'] ?? '')
      .toString()
      .replaceAll(RegExp(r'\D'), '');
  final email = (cfg['support_email'] ?? '').toString().trim();

  final Uri uri = wa.isNotEmpty
      ? Uri.parse('https://wa.me/$wa?text=${Uri.encodeComponent(msg)}')
      : Uri(
          scheme: 'mailto',
          path: email.isNotEmpty ? email : _fallbackSupportEmail,
          query: 'subject=${Uri.encodeComponent('Support request')}'
              '&body=${Uri.encodeComponent(msg)}',
        );
  bool ok = false;
  try {
    ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    ok = false;
  }
  if (!ok) {
    messenger?.showSnackBar(SnackBar(
      content: Text(wa.isNotEmpty
          ? 'Could not open WhatsApp. Message us on +$wa.'
          : 'Could not open e-mail. Write to ${email.isNotEmpty ? email : _fallbackSupportEmail}.'),
      backgroundColor: AppColors.red,
    ));
  }
}
