import 'package:pinput/pinput.dart';
import '../utils/theme.dart';
import '../services/firebase_seimport '../services/firebase_service.dart';rvice.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneCtrl = TextEditingController();
  final _otpCtrl   = TextEditingController();
  String _verificationId = '';
  bool _otpSent   = false;
  bool _loading   = false;
  String _error   = '';

  Future<void> _sendOtp() async {
    final phone = _phoneCtrl.text.trim();
    if (phone.length != 10) {
      setState(() => _error = 'Enter valid 10-digit mobile number');
      return;
    }
    setState(() { _loading = true; _error = ''; });
    await FirebaseService.verifyPhone(
      phone: '+91$phone',
      onCodeSent: (id) {
        setState(() { _verificationId = id; _otpSent = true; _loading = false; });
      },
      onError: (e) {
        setState(() { _error = e; _loading = false; });
      },
    );
  }

  Future<void> _verifyOtp() async {
    if (_otpCtrl.text.length != 6) {
      setState(() => _error = 'Enter 6-digit OTP');
      return;
    }
    setState(() { _loading = true; _error = ''; });
    try {
      await FirebaseService.signInWithPhone(_verificationId, _otpCtrl.text);
      if (mounted) {
        Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    } catch (e) {
      setState(() { _error = 'Invalid OTP. Please try again.'; _loading = false; });
    }
  }

  @override
  void dispose() {
    _phoneCtrl.dispose(); _otpCtrl.dispose(); super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: InputDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.center,
            colors: [Color(0xFF0D3D47), AppColors.bg],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 48),
                // Logo
                Row(children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.brand,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.home_rounded, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 10),
                  RichText(text: const TextSpan(children: [
                    TextSpan(text: 'Hamara', style: TextStyle(fontFamily: 'Sora', fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
                    TextSpan(text: 'Service', style: TextStyle(fontFamily: 'Sora', fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.brand)),
                  ])),
                ]),
                const SizedBox(height: 48),
                // Card
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
                        _otpSent ? 'Enter OTP' : 'Welcome! 👋',
                        style: const TextStyle(fontFamily: 'Sora', fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.ink),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _otpSent
                            ? 'OTP sent to +91 ${_phoneCtrl.text}'
                            : 'Login with your mobile number',
                        style: const TextStyle(fontFamily: 'Sora', fontSize: 14, color: AppColors.muted),
                      ),
                      const SizedBox(height: 28),

                      if (!_otpSent) ...[
                        // Phone field
                        const Text('Mobile Number', style: TextStyle(fontFamily: 'Sora', fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ink2)),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _phoneCtrl,
                          keyboardType: TextInputType.phone,
                          maxLength: 10,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: InputDecoration(
                            counterText: '',
                            prefixText: '+91  ',
                            prefixStyle: const TextStyle(fontFamily: 'Sora', fontWeight: FontWeight.w600, color: AppColors.ink),
                            hintText: '9876543210',
                          ),
                        ),
                      ] else ...[
                        // OTP field
                        Center(
                          child: Pinput(
                            controller: _otpCtrl,
                            length: 6,
                            defaultPinTheme: PinTheme(
                              width: 48, height: 52,
                              textStyle: const TextStyle(fontFamily: 'Sora', fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.ink),
                              decoration: BoxDecoration(
                                color: AppColors.tealSoft,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppColors.line),
                              ),
                            ),
                            focusedPinTheme: PinTheme(
                              width: 48, height: 52,
                              textStyle: const TextStyle(fontFamily: 'Sora', fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.teal),
                              decoration: BoxDecoration(
                                color: AppColors.tealSoft,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppColors.teal, width: 2),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Center(
                          child: TextButton(
                            onPressed: () => setState(() { _otpSent = false; _otpCtrl.clear(); }),
                            child: const Text('Change number', style: TextStyle(fontFamily: 'Sora', color: AppColors.teal, fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ],

                      if (_error.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF5F5),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFFC8181)),
                          ),
                          child: Row(children: [
                            const Icon(Icons.error_outline, color: Color(0xFFE53E3E), size: 18),
                            const SizedBox(width: 8),
                            Expanded(child: Text(_error, style: const TextStyle(fontFamily: 'Sora', fontSize: 13, color: Color(0xFFE53E3E)))),
                          ]),
                        ),
                      ],

                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _loading ? null : (_otpSent ? _verifyOtp : _sendOtp),
                        child: _loading
                            ? const SizedBox(width: 22, height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2.5, valueColor: AlwaysStoppedAnimation(Colors.white)))
                            : Text(_otpSent ? 'Verify OTP ✓' : 'Send OTP →'),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),
                Center(
  child: Text(
    'By continuing you agree to our Terms & Privacy Policy',
    textAlign: TextAlign.center,
    style: TextStyle(fontSize: 12, color: AppColors.muted),
  ),
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
