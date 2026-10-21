import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/api_service.dart';
import '../../services/firebase_service.dart';
import '../../services/session.dart';
import '../../utils/booking_format.dart';
import '../../utils/support.dart';
import '../../utils/theme.dart';
import '../../widgets/common.dart';
import '../login_screen.dart';

/// Account tab — same sections as the web profile: account card (name,
/// e-mail, customer ID), edit details, change password, support, website,
/// logout; plus delete account (customers.php?action=delete).
class ProfileScreen extends StatefulWidget {
  final Map<String, dynamic>? preview;
  final ValueListenable<int>? refresh;
  final VoidCallback? onAuthChanged;
  const ProfileScreen({super.key, this.preview, this.refresh, this.onAuthChanged});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  String _gender = '';
  // Gender is set once; after that only support can change it (the server
  // ignores a new value too).
  bool _genderLocked = false;
  String? _cityError;
  String _email = '';
  String _id = '';
  bool _loading = false;
  bool _saving = false;

  bool get _live => widget.preview == null;
  bool get _signedIn => !_live || Session.signedIn;
  bool get _emailAccount {
    if (!_live) return true;
    final u = Session.user;
    return u != null && u.providerData.any((p) => p.providerId == 'password');
  }

  @override
  void initState() {
    super.initState();
    if (!_live) {
      _fill(widget.preview!);
      return;
    }
    widget.refresh?.addListener(_reload);
    _load();
  }

  @override
  void dispose() {
    widget.refresh?.removeListener(_reload);
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _cityCtrl.dispose();
    super.dispose();
  }

  void _reload() {
    if (mounted) setState(() {});
    if (Session.signedIn && _id.isEmpty) _load();
  }

  void _fill(Map<String, dynamic> d) {
    if (asStr(d['name']).isNotEmpty) _nameCtrl.text = asStr(d['name']);
    if (asStr(d['phone']).isNotEmpty) _phoneCtrl.text = asStr(d['phone']);
    _addressCtrl.text = asStr(d['address']);
    _cityCtrl.text = asStr(d['city']);
    if (asStr(d['email']).isNotEmpty) _email = asStr(d['email']);
    if (asStr(d['id']).isNotEmpty) _id = asStr(d['id']);
    final g = asStr(d['gender']).toLowerCase();
    _gender = ['male', 'female', 'other'].contains(g) ? g : '';
    _genderLocked = _gender.isNotEmpty;
  }

  Future<void> _load() async {
    final user = Session.user;
    if (user == null) return;
    setState(() => _loading = true);
    _nameCtrl.text = user.displayName ?? '';
    _phoneCtrl.text = normalizeIndianMobile(user.phoneNumber ?? '');
    _email = user.email ?? '';
    _id = user.uid;
    try {
      final data = await ApiService.getCustomer();
      if (data != null) _fill(data);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, 'Could not load profile: ${e.message}', error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) {
      showSnack(context, 'Enter your name', error: true);
      return;
    }
    final phone = normalizeIndianMobile(_phoneCtrl.text);
    if (phone.isNotEmpty && !indianMobileRegex.hasMatch(phone)) {
      showSnack(context, 'Enter a valid 10-digit Indian mobile number', error: true);
      return;
    }
    final cityErr = cityError(_cityCtrl.text);
    setState(() => _cityError = cityErr);
    if (cityErr != null) {
      showSnack(context, cityErr, error: true);
      return;
    }
    final user = Session.user;
    if (user == null) return;
    setState(() => _saving = true);
    try {
      try {
        await user.updateDisplayName(_nameCtrl.text.trim());
      } catch (_) {}
      final saved = await ApiService.registerCustomer(
        name: _nameCtrl.text.trim(),
        phone: phone,
        email: user.email ?? '',
        address: _addressCtrl.text.trim(),
        city: _cityCtrl.text.trim(),
        gender: _genderLocked ? null : _gender,
        authMethod: user.providerData.any((p) => p.providerId == 'google.com')
            ? 'google'
            : 'email',
      );
      if (mounted) {
        setState(() {
          final g = asStr(saved['gender']).toLowerCase();
          if (['male', 'female', 'other'].contains(g)) {
            _gender = g;
            _genderLocked = true;
          }
        });
        showSnack(context, 'Profile saved', success: true);
      }
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message.isNotEmpty ? e.message : 'Save failed', error: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _signIn() async {
    final ok = await Navigator.push<bool>(context,
        MaterialPageRoute(builder: (_) => const LoginScreen(returnOnSuccess: true)));
    if (ok == true) {
      widget.onAuthChanged?.call();
      _load();
    }
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You can log in again any time with the same account.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Log out')),
        ],
      ),
    );
    if (ok != true) return;
    await FirebaseService.signOut(); // also clears local prefs
    if (!mounted) return;
    setState(() {
      _id = '';
      _email = '';
      _nameCtrl.clear();
      _phoneCtrl.clear();
      _addressCtrl.clear();
      _cityCtrl.clear();
      _gender = '';
      _genderLocked = false;
      _cityError = null;
    });
    widget.onAuthChanged?.call();
    showSnack(context, 'Logged out');
  }

  Future<void> _changePassword() async {
    final oldCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    String? err;
    bool busy = false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Change password'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: oldCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Current password'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: newCtrl,
              obscureText: true,
              decoration: InputDecoration(
                  labelText: 'New password', helperText: 'At least 8 characters', errorText: err),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      if (newCtrl.text.length < 8) {
                        setS(() => err = 'New password must be at least 8 characters');
                        return;
                      }
                      final user = Session.user;
                      if (user == null || (user.email ?? '').isEmpty) return;
                      setS(() { busy = true; err = null; });
                      try {
                        await user.reauthenticateWithCredential(EmailAuthProvider.credential(
                            email: user.email!, password: oldCtrl.text));
                        await user.updatePassword(newCtrl.text);
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) showSnack(context, 'Password updated', success: true);
                      } on FirebaseAuthException catch (e) {
                        setS(() {
                          busy = false;
                          err = (e.code == 'wrong-password' || e.code == 'invalid-credential')
                              ? 'Current password is incorrect'
                              : (e.message ?? 'Could not update password');
                        });
                      }
                    },
              child: const Text('Update password'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteAccount() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.delete_forever_rounded, color: AppColors.red),
        title: const Text('Delete account?'),
        content: const Text(
            'Your name, phone, e-mail and address are removed. Past bookings are kept '
            'without your details for accounting. A booking that is still searching '
            'for a provider is cancelled. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep account')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ApiService.deleteAccount();
      try {
        await Session.user?.delete();
      } catch (_) {
        // needs a recent login — the server profile is already anonymised
      }
      await FirebaseService.signOut();
      if (!mounted) return;
      setState(() => _id = '');
      widget.onAuthChanged?.call();
      showSnack(context, 'Your account has been deleted', success: true);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  Future<void> _openWebsite() async {
    try {
      await launchUrl(Uri.parse(AppConstants.website), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: !_signedIn
          ? EmptyState(
              icon: Icons.person_outline_rounded,
              title: 'You are not logged in',
              message: 'Login to manage bookings and profile',
              actionLabel: 'Login / Register',
              onAction: _signIn,
            )
          : _loading
              ? const Center(child: CircularProgressIndicator())
              : _body(context),
    );
  }

  Widget _body(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final photo = _live ? Session.user?.photoURL : null;
    final name = _nameCtrl.text.trim();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: AppColors.teal,
                foregroundColor: Colors.white,
                backgroundImage: photo != null ? NetworkImage(photo) : null,
                child: photo == null
                    ? Text((name.isNotEmpty ? name : 'U').characters.first.toUpperCase(),
                        style: t.headlineSmall?.copyWith(color: Colors.white))
                    : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name.isNotEmpty ? name : 'Customer', style: t.titleLarge),
                  if (_email.isNotEmpty)
                    Text(_email, style: t.bodyMedium?.copyWith(color: AppColors.muted)),
                  if (_id.isNotEmpty)
                    InkWell(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: _id));
                        showSnack(context, 'Customer ID copied');
                      },
                      child: Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text('ID: $_id',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.bodySmall?.copyWith(color: AppColors.muted)),
                      ),
                    ),
                ]),
              ),
            ]),
          ),
        ),
        const SectionHeader('Edit details', padding: EdgeInsets.fromLTRB(4, 24, 4, 8)),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: AutofillGroup(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                // Explicit autofill hints so Android autofill never drops the
                // login e-mail into a field without a hint (e.g. City).
                TextField(
                  controller: _nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  keyboardType: TextInputType.name,
                  autofillHints: const [AutofillHints.name],
                  decoration: const InputDecoration(
                      labelText: 'Full name', prefixIcon: Icon(Icons.person_outline_rounded)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  autofillHints: const [AutofillHints.telephoneNumberNational],
                  maxLength: 10,
                  decoration: const InputDecoration(
                      labelText: 'Mobile number',
                      counterText: '',
                      prefixIcon: Icon(Icons.phone_outlined)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _addressCtrl,
                  minLines: 1,
                  maxLines: 3,
                  keyboardType: TextInputType.streetAddress,
                  textCapitalization: TextCapitalization.words,
                  autofillHints: const [AutofillHints.streetAddressLine1],
                  decoration: const InputDecoration(
                      labelText: 'Default address', prefixIcon: Icon(Icons.home_outlined)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _cityCtrl,
                  keyboardType: TextInputType.text,
                  textCapitalization: TextCapitalization.words,
                  autofillHints: const [AutofillHints.addressCity],
                  maxLength: 60,
                  onChanged: (_) {
                    if (_cityError != null) setState(() => _cityError = null);
                  },
                  decoration: InputDecoration(
                      labelText: 'City',
                      hintText: 'e.g. Visakhapatnam',
                      counterText: '',
                      errorText: _cityError,
                      errorMaxLines: 2,
                      prefixIcon: const Icon(Icons.location_city_outlined)),
                ),
                const SizedBox(height: 16),
                Text('Gender', style: t.labelLarge?.copyWith(color: AppColors.muted)),
                const SizedBox(height: 8),
                // Locked: still shows the saved gender, but taps are ignored.
                IgnorePointer(
                  ignoring: _genderLocked,
                  child: Opacity(
                    opacity: _genderLocked ? 0.6 : 1,
                    child: SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'male', label: Text('Male')),
                        ButtonSegment(value: 'female', label: Text('Female')),
                        ButtonSegment(value: 'other', label: Text('Other')),
                      ],
                      selected: _gender.isEmpty ? <String>{} : {_gender},
                      emptySelectionAllowed: true,
                      showSelectedIcon: _genderLocked,
                      selectedIcon: const Icon(Icons.lock_outline_rounded, size: 16),
                      onSelectionChanged: (s) {
                        if (_genderLocked) return;
                        setState(() => _gender = s.isEmpty ? '' : s.first);
                      },
                    ),
                  ),
                ),
                if (_genderLocked)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(children: [
                      const Icon(Icons.lock_outline_rounded, size: 14, color: AppColors.muted),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text("Gender can't be changed. Contact support if it's wrong.",
                            style: t.bodySmall?.copyWith(color: AppColors.muted)),
                      ),
                    ]),
                  ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 22, height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                      : const Text('Save changes'),
                ),
              ]),
            ),
          ),
        ),
        const SectionHeader('More', padding: EdgeInsets.fromLTRB(4, 24, 4, 8)),
        Card(
          child: Column(children: [
            if (_emailAccount) ...[
              ListTile(
                leading: const Icon(Icons.lock_outline_rounded),
                title: const Text('Change password'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: _changePassword,
              ),
              const Divider(indent: 56),
            ],
            ListTile(
              leading: const Icon(Icons.chat_outlined),
              title: const Text('WhatsApp support'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => openSupport(context, about: _id.isNotEmpty ? 'Customer ID $_id.' : ''),
            ),
            const Divider(indent: 56),
            ListTile(
              leading: const Icon(Icons.language_rounded),
              title: const Text('Visit website'),
              trailing: const Icon(Icons.open_in_new_rounded, size: 20),
              onTap: _openWebsite,
            ),
            const Divider(indent: 56),
            ListTile(
              leading: const Icon(Icons.logout_rounded, color: AppColors.red),
              title: Text('Logout', style: t.bodyLarge?.copyWith(color: AppColors.red)),
              onTap: _logout,
            ),
          ]),
        ),
        const SizedBox(height: 12),
        Center(
          child: TextButton.icon(
            onPressed: _deleteAccount,
            style: TextButton.styleFrom(foregroundColor: AppColors.muted),
            icon: const Icon(Icons.delete_outline_rounded, size: 20),
            label: const Text('Delete account'),
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text('HamaraService · ${AppConstants.contactEmail}',
              style: t.bodySmall?.copyWith(color: AppColors.muted)),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
