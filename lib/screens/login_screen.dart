import 'package:flutter/material.dart';
import '../utils/theme.dart';
import '../services/firebase_service.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _loading = false;
  String _error = '';

  Future<void> _signInWithGoogle() async {
    setState(() { _loading = true; _error = ''; });
    try {
      final result = await FirebaseService.signInWithGoogle();
      if (result == null) {
        setState(() { _loading = false; _error = 'Sign in cancelled'; });
        return;
      }
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    } catch (e) {
      setState(() { _loading = false; _error = 'Sign in failed. Please try again.'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0D3D47), AppColors.bg],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const SizedBox(height: 80),
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    color: AppColors.brand,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.brand.withOpacity(0.4),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.home_rounded, color: Colors.white, size: 48),
                ),
                const SizedBox(height: 24),
                RichText(
                  text: const TextSpan(
                    children: [
                      TextSpan(
                        text: 'Hamara',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      TextSpan(
                        text: 'Service',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          color: AppColors.brand,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Home services at your doorstep',
                  style: TextStyle(fontSize: 14, color: Colors.white70),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Welcome! 👋',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Sign in to book home services',
                        style: TextStyle(fontSize: 14, color: AppColors.muted),
                      ),
                      const SizedBox(height: 28),
                      if (_error.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF5F5),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFFC8181)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline, color: Color(0xFFE53E3E), size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _error,
                                  style: const TextStyle(fontSize: 13, color: Color(0xFFE53E3E)),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: OutlinedButton(
                          onPressed: _loading ? null : _signInWithGoogle,
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppColors.line, width: 1.5),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: _loading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    valueColor: AlwaysStoppedAnimation(AppColors.teal),
                                  ),
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Image.network(
                                      'https://www.google.com/favicon.ico',
                                      width: 22,
                                      height: 22,
                                      errorBuilder: (_, __, ___) =>
                                          const Icon(Icons.g_mobiledata, size: 24, color: AppColors.teal),
                                    ),
                                    const SizedBox(width: 12),
                                    const Text(
                                      'Continue with Google',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.ink,
                                      ),
                                    ),
                                  ],
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
                  style: TextStyle(fontSize: 12, color: Colors.white60),
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
