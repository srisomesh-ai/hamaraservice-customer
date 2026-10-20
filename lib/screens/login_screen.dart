import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../services/api_service.dart';
import '../services/firebase_service.dart';
import '../utils/booking_format.dart';
import '../utils/theme.dart';
import 'home_screen.dart';

/// Login / register — same account as the website (Firebase e-mail +
/// password, or Google). Wording and error messages follow the web app
/// (customers.php?action=web_login).
class LoginScreen extends StatefulWidget {
  /// true: pop(true) after a successful sign-in (e.g. opened from a
  /// service page or a tab) instead of restarting at Home.
  final bool returnOnSuccess;
  final bool startInRegister;
  const LoginScreen({super.key, this.returnOnSuccess = false, this.startInRegister = false});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _pwdCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  bool _loading = false;
  late bool _isRegister = widget.startInRegister;
  bool _showPwd = false;
  String _error = '';

  void _done() {
    if (!mounted) return;
    if (widget.returnOnSuccess && Navigator.canPop(context)) {
      Navigator.pop(context, true);
    } else {
      Navigator.pushAndRemoveUntil(context,
          MaterialPageRoute(builder: (_) => const HomeScreen()), (r) => false);
    }
  }

  Future<void> _syncProfile({String? authMethod}) async {
    try {
      await ApiService.ensureCustomerProfile(authMethod: authMethod);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, 'Signed in, but profile sync failed: ${e.message}', error: true);
    }
  }

  void _swap() => setState(() {
        _isRegister = !_isRegister;
        _error = '';
      });

  // ── Google ──
  Future<void> _signInGoogle() async {
    setState(() { _loading = true; _error = ''; });
    try {
      final result = await FirebaseService.signInWithGoogle();
      if (result == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      await _syncProfile(authMethod: 'google');
      _done();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Google sign-in failed. Please try again or use email/password.';
      });
    }
  }

  // ── Email login ──
  Future<void> _login() async {
    final email = _emailCtrl.text.trim().toLowerCase();
    final pwd = _pwdCtrl.text;
    if (email.isEmpty || pwd.isEmpty) {
      setState(() => _error = 'Enter email and password');
      return;
    }
    setState(() { _loading = true; _error = ''; });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: pwd);
      await _syncProfile(authMethod: 'email');
      _done();
    } on FirebaseAuthException catch (e) {
      const credentialCodes = {
        'user-not-found', 'wrong-password', 'invalid-credential', 'INVALID_LOGIN_CREDENTIALS',
      };
      if (credentialCodes.contains(e.code)) {
        await _explainLoginFailure(email, pwd);
        return;
      }
      final msgs = {
        'invalid-email': 'Invalid email format.',
        'user-disabled': 'This account has been disabled. Please contact support.',
        'too-many-requests': 'Too many attempts. Please try again later.',
        'network-request-failed': 'Network error',
      };
      if (mounted) setState(() { _loading = false; _error = msgs[e.code] ?? 'Sign in failed. Try again.'; });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = 'Sign in failed. Try again.'; });
    }
  }

  /// Firebase hides whether the e-mail exists. Ask the website login for
  /// the exact reason (same messages as the web app). It also moves an
  /// older web-only account onto Firebase — then signing in works.
  Future<void> _explainLoginFailure(String email, String pwd) async {
    try {
      await ApiService.webLogin(email, pwd);
      // Web login worked → the account now exists in Firebase; retry.
      await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: pwd);
      await _syncProfile(authMethod: 'email');
      _done();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (e.message.startsWith('NOT_REGISTERED')) {
          _isRegister = true;
          _error = 'No account found for this email — create your account below';
        } else if (e.statusCode == null || e.statusCode! >= 500) {
          _error = 'Incorrect email or password. New here? Create an account.';
        } else {
          _error = e.message;
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Incorrect email or password. New here? Create an account.';
        });
      }
    }
  }

  // ── Register ──
  Future<void> _register() async {
    final email = _emailCtrl.text.trim().toLowerCase();
    final pwd = _pwdCtrl.text;
    final name = _nameCtrl.text.trim();
    final phone = normalizeIndianMobile(_phoneCtrl.text);
    if (name.isEmpty) { setState(() => _error = 'Enter your name'); return; }
    if (!indianMobileRegex.hasMatch(phone)) {
      setState(() => _error = 'Enter a valid 10-digit Indian mobile number');
      return;
    }
    if (email.isEmpty || pwd.isEmpty) { setState(() => _error = 'Enter email and password'); return; }
    if (pwd.length < 8) { setState(() => _error = 'Password must be at least 8 characters'); return; }
    setState(() { _loading = true; _error = ''; });

    try {
      final cred = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: pwd);
      await cred.user?.updateDisplayName(name);
    } on FirebaseAuthException catch (e) {
      final msgs = {
        'email-already-in-use': 'This email is already registered — please login.',
        'invalid-email': 'Invalid email format.',
        'weak-password': 'Password too weak.',
        'network-request-failed': 'Network error',
      };
      if (mounted) {
        setState(() {
          _loading = false;
          _error = msgs[e.code] ?? 'Registration failed. Try again.';
          if (e.code == 'email-already-in-use') _isRegister = false;
        });
      }
      return;
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = 'Registration failed. Try again.'; });
      return;
    }

    try {
      String? fcm;
      try {
        fcm = await FirebaseMessaging.instance.getToken();
      } catch (_) {}
      await ApiService.registerCustomer(
        name: name, phone: phone, email: email, fcmToken: fcm, authMethod: 'email');
    } on ApiException catch (e) {
      if (mounted) {
        showSnack(context, 'Account created, but saving your profile failed: ${e.message}',
            error: true);
      }
    }
    _done();
  }

  Future<void> _forgotPassword() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Enter your email first');
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      setState(() => _error = '');
      if (mounted) showSnack(context, 'Password reset email sent', success: true);
    } catch (_) {
      setState(() => _error = 'Could not send reset email. Check your email address.');
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _pwdCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: Navigator.canPop(context) ? const CloseButton() : null,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        top: false,
        child: AutofillGroup(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            children: [
              Center(
                child: Image.asset('assets/images/rlogo.png',
                    height: 64,
                    errorBuilder: (_, __, ___) => Text('HamaraService', style: t.headlineSmall)),
              ),
              const SizedBox(height: 24),
              Text(_isRegister ? 'Create your account 🎉' : 'Welcome back 👋',
                  style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(_isRegister ? 'Register to start booking services' : 'Login to book your service',
                  style: t.bodyLarge?.copyWith(color: AppColors.muted)),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: const [
                _Badge(Icons.verified_rounded, 'Verified Pros'),
                _Badge(Icons.payments_outlined, 'Pay After Service'),
                _Badge(Icons.star_rounded, '4.8 Rated'),
              ]),
              const SizedBox(height: 24),
              if (_isRegister) ...[
                TextField(
                  controller: _nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  autofillHints: const [AutofillHints.name],
                  decoration: const InputDecoration(
                      labelText: 'Full name', prefixIcon: Icon(Icons.person_outline_rounded)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  maxLength: 10,
                  autofillHints: const [AutofillHints.telephoneNumberNational],
                  decoration: const InputDecoration(
                      labelText: 'Mobile number',
                      hintText: '10-digit mobile',
                      counterText: '',
                      prefixIcon: Icon(Icons.phone_outlined)),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(
                    labelText: 'Email', prefixIcon: Icon(Icons.mail_outline_rounded)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pwdCtrl,
                obscureText: !_showPwd,
                autofillHints: [_isRegister ? AutofillHints.newPassword : AutofillHints.password],
                onSubmitted: (_) => _loading ? null : (_isRegister ? _register() : _login()),
                decoration: InputDecoration(
                  labelText: 'Password',
                  helperText: _isRegister ? 'At least 8 characters' : null,
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    tooltip: _showPwd ? 'Hide password' : 'Show password',
                    icon: Icon(_showPwd ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                    onPressed: () => setState(() => _showPwd = !_showPwd),
                  ),
                ),
              ),
              if (!_isRegister)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(onPressed: _forgotPassword, child: const Text('Forgot password?')),
                ),
              if (_error.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: AppColors.redSoft, borderRadius: BorderRadius.circular(12)),
                  child: Row(children: [
                    const Icon(Icons.error_outline_rounded, color: AppColors.red, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text(_error,
                            style: t.bodyMedium?.copyWith(color: AppColors.red))),
                  ]),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _loading ? null : (_isRegister ? _register : _login),
                child: _loading
                    ? const SizedBox(
                        width: 22, height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                    : Text(_isRegister ? 'Create Account' : 'Login'),
              ),
              const SizedBox(height: 16),
              Row(children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('or', style: t.bodyMedium?.copyWith(color: AppColors.muted)),
                ),
                const Expanded(child: Divider()),
              ]),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _loading ? null : _signInGoogle,
                icon: const Icon(Icons.g_mobiledata_rounded, size: 28),
                label: const Text('Continue with Google'),
              ),
              const SizedBox(height: 16),
              Center(
                child: TextButton(
                  onPressed: _swap,
                  child: Text(_isRegister
                      ? 'Already have an account? Login'
                      : 'New here? Create account'),
                ),
              ),
              const SizedBox(height: 8),
              Text('By continuing you agree to our Terms & Privacy Policy',
                  textAlign: TextAlign.center,
                  style: t.bodySmall?.copyWith(color: AppColors.muted)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Badge(this.icon, this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.tealSoft,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: AppColors.teal2),
        const SizedBox(width: 6),
        Text(text,
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: AppColors.teal2, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}
