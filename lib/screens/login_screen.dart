import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import '../services/api_service.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/theme.dart';
import '../services/firebase_service.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl   = TextEditingController();
  final _pwdCtrl     = TextEditingController();
  final _nameCtrl    = TextEditingController();
  final _phoneCtrl   = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _cityCtrl    = TextEditingController();
  final _localAuth   = LocalAuthentication();
  bool _loading      = false;
  bool _isRegister   = false;
  bool _showPwd      = false;
  bool _bioAvail     = false;
  bool _bioEnabled   = false;
  String _gender     = 'Male';
  String _error      = '';

  @override
  void initState() {
    super.initState();
    _checkBiometrics();
  }

  // ── Biometric Setup ───────────────────────────────────────────────────────
  Future<void> _checkBiometrics() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();
      if (!mounted) return;
      setState(() => _bioAvail = canCheck && isSupported);
      if (_bioAvail) {
        final prefs = await SharedPreferences.getInstance();
        setState(() => _bioEnabled = prefs.getBool('bio_enabled') ?? false);
        // Auto-trigger if enabled
        if (_bioEnabled) _biometricLogin();
      }
    } catch (_) {}
  }

  Future<void> _biometricLogin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedEmail = prefs.getString('saved_email') ?? '';
      final savedPwd   = prefs.getString('saved_pwd')   ?? '';
      if (savedEmail.isEmpty || savedPwd.isEmpty) {
        setState(() => _error = 'Please sign in once with email/password first to enable biometric login.');
        return;
      }
      final auth = await _localAuth.authenticate(
        localizedReason: 'Verify your identity to sign in',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
      if (!auth) return;
      setState(() { _loading = true; _error = ''; });
      await FirebaseAuth.instance.signInWithEmailAndPassword(email: savedEmail, password: savedPwd);
      if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen()));
    } on PlatformException catch (e) {
      setState(() { _loading = false; _error = 'Biometric failed: ${e.message}'; });
    } catch (e) {
      setState(() { _loading = false; _error = 'Login failed. Try email/password.'; });
    }
  }

  // ── Google Sign In ────────────────────────────────────────────────────────
  Future<void> _signInGoogle() async {
    setState(() { _loading = true; _error = ''; });
    try {
      final result = await FirebaseService.signInWithGoogle();
      if (result == null) { setState(() { _loading = false; }); return; }

      // Save to MySQL — upsert customer record
      final customer = await ApiService.registerCustomer(
        name:       result.user?.displayName ?? '',
        authMethod: 'google',
      );
      if (customer != null) await ApiService.saveCurrentUser(customer);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('saved_email', result.user?.email ?? '');
      await prefs.setString('auth_method', 'google');
      if (mounted) Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => const HomeScreen()));
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString().contains('sign_in_failed')
            ? 'Google Sign-In failed. Make sure SHA-1 is added in Firebase Console.'
            : 'Google sign-in failed. Please try email/password.';
      });
    }
  }

  // ── Email Sign In ─────────────────────────────────────────────────────────
  Future<void> _signInEmail() async {
    final email = _emailCtrl.text.trim();
    final pwd   = _pwdCtrl.text;
    if (email.isEmpty || pwd.isEmpty) { setState(() => _error = 'Enter email and password'); return; }
    setState(() { _loading = true; _error = ''; });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: pwd);
      // Save for biometric
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('saved_email', email);
      await prefs.setString('saved_pwd', pwd);
      await prefs.setString('auth_method', 'email');
      // Enable biometric if available
      if (_bioAvail) {
        await prefs.setBool('bio_enabled', true);
        setState(() => _bioEnabled = true);
      }
      if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen()));
    } on FirebaseAuthException catch (e) {
      final msgs = {
        'user-not-found':     'No account with this email. Please register.',
        'wrong-password':     'Incorrect password. Try again.',
        'invalid-email':      'Invalid email format.',
        'too-many-requests':  'Too many attempts. Please wait.',
        'invalid-credential': 'Incorrect email or password.',
      };
      setState(() { _loading = false; _error = msgs[e.code] ?? 'Sign in failed. Try again.'; });
    }
  }

  // ── Register ──────────────────────────────────────────────────────────────
  Future<void> _register() async {
    final email = _emailCtrl.text.trim();
    final pwd   = _pwdCtrl.text;
    final name  = _nameCtrl.text.trim();
    if (name.isEmpty) { setState(() => _error = 'Enter your full name'); return; }
    final phone = _phoneCtrl.text.trim();
    if (phone.isEmpty || phone.length < 10) { setState(() => _error = 'Enter a valid 10-digit mobile number'); return; }
    if (email.isEmpty || pwd.isEmpty) { setState(() => _error = 'Enter email and password'); return; }
    if (pwd.length < 8) { setState(() => _error = 'Password must be at least 8 characters'); return; }
    setState(() { _loading = true; _error = ''; });
    try {
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(email: email, password: pwd);
      await cred.user?.updateDisplayName(name);

      // Save full profile to MySQL
      final uid = cred.user!.uid;
      final customer = await ApiService.registerCustomer(
        name:       name,
        phone:      _phoneCtrl.text.trim(),
        gender:     _gender,
        address:    _addressCtrl.text.trim(),
        city:       _cityCtrl.text.trim(),
        authMethod: 'email',
      );
      if (customer != null) await ApiService.saveCurrentUser(customer);

      // Save for biometric
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('saved_email', email);
      await prefs.setString('saved_pwd', pwd);
      if (_bioAvail) {
        await prefs.setBool('bio_enabled', true);
        setState(() => _bioEnabled = true);
      }
      if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen()));
    } on FirebaseAuthException catch (e) {
      final msgs = {
        'email-already-in-use': 'Email already registered. Please sign in.',
        'invalid-email':        'Invalid email format.',
        'weak-password':        'Password too weak.',
      };
      setState(() { _loading = false; _error = msgs[e.code] ?? 'Registration failed. Try again.'; });
    }
  }

  // ── Forgot Password ───────────────────────────────────────────────────────
  Future<void> _forgotPassword() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) { setState(() => _error = 'Enter your email first'); return; }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      setState(() { _error = ''; });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password reset email sent!'), backgroundColor: AppColors.green),
        );
      }
    } catch (e) {
      setState(() => _error = 'Could not send reset email. Check your email address.');
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose(); _pwdCtrl.dispose(); _nameCtrl.dispose();
    _phoneCtrl.dispose(); _addressCtrl.dispose(); _cityCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0xFF0D3D47), AppColors.bg],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const SizedBox(height: 52),
                Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(
                    color: AppColors.brand, borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(color: AppColors.brand.withOpacity(0.4), blurRadius: 20, offset: const Offset(0, 8))],
                  ),
                  child: const Icon(Icons.home_rounded, color: Colors.white, size: 44),
                ),
                const SizedBox(height: 16),
                RichText(text: const TextSpan(children: [
                  TextSpan(text: 'Hamara', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Colors.white)),
                  TextSpan(text: 'Service', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.brand)),
                ])),
                const SizedBox(height: 4),
                const Text('Home services at your doorstep', style: TextStyle(fontSize: 13, color: Colors.white70)),
                const SizedBox(height: 32),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white, borderRadius: BorderRadius.circular(24),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 24, offset: const Offset(0, 8))],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isRegister ? 'Create Account' : 'Welcome Back!',
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.ink),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _isRegister ? 'Register to book services' : 'Sign in to your account',
                        style: const TextStyle(fontSize: 13, color: AppColors.muted),
                      ),
                      const SizedBox(height: 20),

                      // ── Google Button ──────────────────────────────────
                      SizedBox(
                        width: double.infinity, height: 48,
                        child: OutlinedButton(
                          onPressed: _loading ? null : _signInGoogle,
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppColors.line, width: 1.5),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 22, height: 22,
                                decoration: BoxDecoration(color: AppColors.tealSoft, borderRadius: BorderRadius.circular(4)),
                                child: const Icon(Icons.g_mobiledata_rounded, size: 18, color: AppColors.teal)),
                              const SizedBox(width: 10),
                              const Text('Continue with Google', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.ink)),
                            ],
                          ),
                        ),
                      ),

                      // ── Biometric Button ───────────────────────────────
                      if (_bioAvail && !_isRegister) ...[ 
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity, height: 48,
                          child: OutlinedButton(
                            onPressed: _loading ? null : _biometricLogin,
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: AppColors.teal.withOpacity(0.4), width: 1.5),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              backgroundColor: AppColors.tealSoft,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.fingerprint_rounded, color: AppColors.teal, size: 22),
                                const SizedBox(width: 10),
                                Text(
                                  _bioEnabled ? 'Sign in with Fingerprint' : 'Set Up Biometric Login',
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.teal),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],

                      const SizedBox(height: 16),
                      Row(children: [
                        const Expanded(child: Divider(color: AppColors.line)),
                        const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('or', style: TextStyle(color: AppColors.muted, fontSize: 13))),
                        const Expanded(child: Divider(color: AppColors.line)),
                      ]),
                      const SizedBox(height: 16),

                      // ── Name (register only) ───────────────────────────
                      if (_isRegister) ...[
                        // Full Name
                        const Text('Full Name *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.ink2)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _nameCtrl,
                          textCapitalization: TextCapitalization.words,
                          decoration: InputDecoration(
                            hintText: 'Your full name',
                            prefixIcon: const Icon(Icons.person_outline_rounded, color: AppColors.muted),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                        ),
                        const SizedBox(height: 12),

                        // Phone
                        const Text('Mobile Number *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.ink2)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _phoneCtrl,
                          keyboardType: TextInputType.phone,
                          maxLength: 10,
                          decoration: InputDecoration(
                            hintText: '10-digit mobile number',
                            counterText: '',
                            prefixIcon: const Icon(Icons.phone_outlined, color: AppColors.muted),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                        ),
                        const SizedBox(height: 12),

                        // Gender
                        const Text('Gender', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.ink2)),
                        const SizedBox(height: 8),
                        Row(children: ['Male', 'Female', 'Other'].map((g) => Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: GestureDetector(
                              onTap: () => setState(() => _gender = g),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: _gender == g ? AppColors.teal : AppColors.line,
                                    width: _gender == g ? 2 : 1.5),
                                  borderRadius: BorderRadius.circular(10),
                                  color: _gender == g ? AppColors.tealSoft : Colors.white),
                                child: Text(g,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w700,
                                    color: _gender == g ? AppColors.teal : AppColors.muted)),
                              ),
                            ),
                          ),
                        )).toList()),
                        const SizedBox(height: 12),

                        // Address
                        const Text('Address', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.ink2)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _addressCtrl,
                          decoration: InputDecoration(
                            hintText: 'House no, Street, Area',
                            prefixIcon: const Icon(Icons.home_outlined, color: AppColors.muted),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                        ),
                        const SizedBox(height: 12),

                        // City
                        const Text('City', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.ink2)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _cityCtrl,
                          decoration: InputDecoration(
                            hintText: 'Your city',
                            prefixIcon: const Icon(Icons.location_city_outlined, color: AppColors.muted),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                        ),
                        const SizedBox(height: 12),
                      ],

                      // ── Email ──────────────────────────────────────────
                      const Text('Email', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.ink2)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(hintText: 'you@email.com', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                      ),
                      const SizedBox(height: 12),

                      // ── Password ───────────────────────────────────────
                      const Text('Password', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.ink2)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _pwdCtrl,
                        obscureText: !_showPwd,
                        decoration: InputDecoration(
                          hintText: _isRegister ? 'Min 8 characters' : 'Your password',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          suffixIcon: IconButton(
                            icon: Icon(_showPwd ? Icons.visibility_off : Icons.visibility, color: AppColors.muted),
                            onPressed: () => setState(() => _showPwd = !_showPwd),
                          ),
                        ),
                      ),

                      if (!_isRegister) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _forgotPassword,
                            style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero),
                            child: const Text('Forgot password?', style: TextStyle(fontSize: 12, color: AppColors.teal, fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ],

                      // ── Error ──────────────────────────────────────────
                      if (_error.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF5F5), borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFFC8181))),
                          child: Row(children: [
                            const Icon(Icons.error_outline, color: Color(0xFFE53E3E), size: 16),
                            const SizedBox(width: 8),
                            Expanded(child: Text(_error, style: const TextStyle(fontSize: 12, color: Color(0xFFE53E3E)))),
                          ]),
                        ),
                      ],

                      const SizedBox(height: 20),

                      // ── Main Button ────────────────────────────────────
                      SizedBox(
                        width: double.infinity, height: 50,
                        child: ElevatedButton(
                          onPressed: _loading ? null : (_isRegister ? _register : _signInEmail),
                          child: _loading
                              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, valueColor: AlwaysStoppedAnimation(Colors.white)))
                              : Text(_isRegister ? 'Create Account' : 'Sign In', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                        ),
                      ),

                      const SizedBox(height: 16),
                      Center(
                        child: TextButton(
                          onPressed: () => setState(() { _isRegister = !_isRegister; _error = ''; }),
                          child: Text(
                            _isRegister ? 'Already have an account? Sign In' : "Don't have an account? Register",
                            style: const TextStyle(fontSize: 13, color: AppColors.teal, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'By continuing you agree to our Terms & Privacy Policy',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: Colors.white60),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
