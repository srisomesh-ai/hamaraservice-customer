import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../utils/theme.dart';
import '../services/firebase_service.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _pwdCtrl   = TextEditingController();
  final _nameCtrl  = TextEditingController();
  bool _loading    = false;
  bool _isRegister = false;
  bool _showPwd    = false;
  String _error    = '';

  Future<void> _signInGoogle() async {
    setState(() { _loading = true; _error = ''; });
    try {
      final result = await FirebaseService.signInWithGoogle();
      if (result == null) { setState(() { _loading = false; }); return; }
      if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen()));
    } catch (e) {
      setState(() { _loading = false; _error = 'Google sign in failed. Try again.'; });
    }
  }

  Future<void> _signInEmail() async {
    final email = _emailCtrl.text.trim();
    final pwd   = _pwdCtrl.text;
    if (email.isEmpty || pwd.isEmpty) { setState(() => _error = 'Enter email and password'); return; }
    setState(() { _loading = true; _error = ''; });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: pwd);
      if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen()));
    } on FirebaseAuthException catch (e) {
      final msgs = {
        'user-not-found': 'No account with this email. Please register.',
        'wrong-password': 'Incorrect password. Try again.',
        'invalid-email':  'Invalid email format.',
        'too-many-requests': 'Too many attempts. Please wait.',
        'invalid-credential': 'Incorrect email or password.',
      };
      setState(() { _loading = false; _error = msgs[e.code] ?? 'Sign in failed. Try again.'; });
    }
  }

  Future<void> _register() async {
    final email = _emailCtrl.text.trim();
    final pwd   = _pwdCtrl.text;
    final name  = _nameCtrl.text.trim();
    if (name.isEmpty) { setState(() => _error = 'Enter your name'); return; }
    if (email.isEmpty || pwd.isEmpty) { setState(() => _error = 'Enter email and password'); return; }
    if (pwd.length < 8) { setState(() => _error = 'Password must be at least 8 characters'); return; }
    setState(() { _loading = true; _error = ''; });
    try {
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(email: email, password: pwd);
      await cred.user?.updateDisplayName(name);
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
  void dispose() { _emailCtrl.dispose(); _pwdCtrl.dispose(); _nameCtrl.dispose(); super.dispose(); }

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
                const SizedBox(height: 60),
                Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(
                    color: AppColors.brand,
                    borderRadius: BorderRadius.circular(20),
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
                const SizedBox(height: 36),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
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

                      // Google button
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: OutlinedButton(
                          onPressed: _loading ? null : _signInGoogle,
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppColors.line, width: 1.5),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Image.network('https://www.google.com/favicon.ico', width: 20, height: 20,
                                errorBuilder: (_, __, ___) => const Icon(Icons.g_mobiledata, size: 22, color: AppColors.teal)),
                              const SizedBox(width: 10),
                              const Text('Continue with Google', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.ink)),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),
                      Row(children: [
                        const Expanded(child: Divider(color: AppColors.line)),
                        const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('or', style: TextStyle(color: AppColors.muted, fontSize: 13))),
                        const Expanded(child: Divider(color: AppColors.line)),
                      ]),
                      const SizedBox(height: 16),

                      // Name field (register only)
                      if (_isRegister) ...[
                        const Text('Full Name', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.ink2)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _nameCtrl,
                          decoration: InputDecoration(hintText: 'Your full name', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                        ),
                        const SizedBox(height: 12),
                      ],

                      // Email
                      const Text('Email', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.ink2)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(hintText: 'you@email.com', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                      ),
                      const SizedBox(height: 12),

                      // Password
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

                      // Forgot password
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

                      // Error
                      if (_error.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: const Color(0xFFFFF5F5), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFFC8181))),
                          child: Row(children: [
                            const Icon(Icons.error_outline, color: Color(0xFFE53E3E), size: 16),
                            const SizedBox(width: 8),
                            Expanded(child: Text(_error, style: const TextStyle(fontSize: 12, color: Color(0xFFE53E3E)))),
                          ]),
                        ),
                      ],

                      const SizedBox(height: 20),

                      // Main button
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _loading ? null : (_isRegister ? _register : _signInEmail),
                          child: _loading
                              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, valueColor: AlwaysStoppedAnimation(Colors.white)))
                              : Text(_isRegister ? 'Create Account' : 'Sign In', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Toggle register/login
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
