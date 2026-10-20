import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../utils/support.dart';
import '../utils/theme.dart';
import '../widgets/common.dart';

/// Help tab: WhatsApp support (site.php config, same message as the web's
/// HS_support), e-mail, website and how booking works.
class SupportScreen extends StatefulWidget {
  final Map<String, dynamic>? preview;
  const SupportScreen({super.key, this.preview});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  Map<String, dynamic> _cfg = {};

  @override
  void initState() {
    super.initState();
    if (widget.preview != null) {
      _cfg = widget.preview!;
    } else {
      ApiService.getSiteConfig().then((c) {
        if (mounted) setState(() => _cfg = c);
      });
    }
  }

  String get _email {
    final e = (_cfg['support_email'] ?? '').toString().trim();
    return e.isNotEmpty ? e : AppConstants.contactEmail;
  }

  String get _wa => (_cfg['support_whatsapp'] ?? '').toString().replaceAll(RegExp(r'\D'), '');

  Future<void> _open(Uri uri) async {
    bool ok = false;
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!ok && mounted) showSnack(context, 'Could not open ${uri.toString()}', error: true);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Help & support')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: AppColors.tealSoft,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const CircleAvatar(
                  radius: 24,
                  backgroundColor: AppColors.teal,
                  foregroundColor: Colors.white,
                  child: Icon(Icons.support_agent_rounded),
                ),
                const SizedBox(height: 14),
                Text('We\'re here to help', style: t.titleLarge),
                const SizedBox(height: 4),
                Text(
                  'Chat with HamaraService support about a booking, a payment or your account.',
                  style: t.bodyMedium?.copyWith(color: AppColors.ink2),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => openSupport(context),
                    icon: const Icon(Icons.chat_rounded),
                    label: Text(_wa.isNotEmpty ? 'WhatsApp support' : 'Contact support'),
                  ),
                ),
              ]),
            ),
          ),
          const SectionHeader('Contact', padding: EdgeInsets.fromLTRB(4, 24, 4, 8)),
          Card(
            child: Column(children: [
              if (_wa.isNotEmpty) ...[
                ListTile(
                  leading: const Icon(Icons.chat_outlined),
                  title: const Text('WhatsApp'),
                  subtitle: Text('+$_wa'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => openSupport(context),
                ),
                const Divider(indent: 56),
              ],
              ListTile(
                leading: const Icon(Icons.mail_outline_rounded),
                title: const Text('E-mail'),
                subtitle: Text(_email),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _open(Uri(
                    scheme: 'mailto',
                    path: _email,
                    query: 'subject=${Uri.encodeComponent('Support request')}')),
              ),
              const Divider(indent: 56),
              ListTile(
                leading: const Icon(Icons.language_rounded),
                title: const Text('Visit website'),
                subtitle: const Text('hamaraservice.com'),
                trailing: const Icon(Icons.open_in_new_rounded, size: 20),
                onTap: () => _open(Uri.parse(AppConstants.website)),
              ),
            ]),
          ),
          const SectionHeader('How it works', padding: EdgeInsets.fromLTRB(4, 24, 4, 8)),
          const Card(child: HowItWorks()),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// Four booking steps (same text as the service pages).
class HowItWorks extends StatelessWidget {
  const HowItWorks({super.key});

  static const steps = [
    ('Book online', 'Select your slot and confirm. Nothing is charged now.'),
    ('A nearby provider quotes a price', 'Accept, negotiate or decline in the app.'),
    ('Provider arrives', 'You get their name and phone. Share the start OTP when they arrive.'),
    ('Work done — you pay', 'Pay online (UPI, card) or in cash.'),
  ];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(children: [
        for (var i = 0; i < steps.length; i++)
          ListTile(
            leading: CircleAvatar(
              radius: 16,
              backgroundColor: AppColors.teal,
              foregroundColor: Colors.white,
              child: Text('${i + 1}', style: t.labelLarge?.copyWith(color: Colors.white)),
            ),
            title: Text(steps[i].$1, style: t.titleSmall),
            subtitle: Text(steps[i].$2),
          ),
      ]),
    );
  }
}
