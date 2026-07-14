import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import '../services/api_service.dart';
import '../../utils/theme.dart';
import '../../services/firebase_service.dart';
import '../login_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _nameCtrl    = TextEditingController();
  final _phoneCtrl   = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _cityCtrl    = TextEditingController();
  String _gender = 'male';
  bool _loading = false;
  bool _saving  = false;
  User? _user;

  @override
  void initState() {
    super.initState();
    _user = FirebaseAuth.instance.currentUser;
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() => _loading = true);
    final uid = _user?.uid;
    if (uid == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      // Pre-fill from Firebase Auth
      _nameCtrl.text  = _user?.displayName ?? '';
      _phoneCtrl.text = _user?.phoneNumber ?? '';

      // Load extra profile data from Realtime DB
      final snap = await FirebaseDatabase.instance.ref('customers/$uid').get();
      if (snap.exists) {
        final data = Map<String, dynamic>.from(snap.value as Map);
        _nameCtrl.text    = data['name']    ?? _nameCtrl.text;
        _phoneCtrl.text   = data['phone']   ?? _phoneCtrl.text;
        _addressCtrl.text = data['address'] ?? '';
        _cityCtrl.text    = data['city']    ?? '';
        _gender           = data['gender']  ?? 'male';
      }
    } catch (e) {
      // ignore
    }
    setState(() => _loading = false);
  }

  Future<void> _saveProfile() async {
    if (_nameCtrl.text.trim().isEmpty) {
      _showSnack('Please enter your name', AppColors.red);
      return;
    }
    setState(() => _saving = true);
    try {
      final uid = _user?.uid;
      if (uid == null) return;

      // Update Firebase Auth display name
      await _user?.updateDisplayName(_nameCtrl.text.trim());

      // Save to Realtime DB
      await FirebaseDatabase.instance.ref('customers/$uid').update({
        'name':      _nameCtrl.text.trim(),
        'phone':     _phoneCtrl.text.trim(),
        'address':   _addressCtrl.text.trim(),
        'city':      _cityCtrl.text.trim(),
        'gender':    _gender,
        'email':     _user?.email ?? '',
        'updatedAt': DateTime.now().toIso8601String(),
      });

      _showSnack('Profile saved successfully!', AppColors.green);
    } catch (e) {
      _showSnack('Failed to save. Please try again.', AppColors.red);
    }
    setState(() => _saving = false);
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color, behavior: SnackBarBehavior.floating));
  }

  @override
  void dispose() {
    _nameCtrl.dispose(); _phoneCtrl.dispose();
    _addressCtrl.dispose(); _cityCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: AppColors.teal));

    // Not logged in — show login prompt
    if (_user == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(color: AppColors.tealSoft, shape: BoxShape.circle),
                child: const Icon(Icons.person_rounded, color: AppColors.teal, size: 44),
              ),
              const SizedBox(height: 20),
              const Text('Sign in to view your profile',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.ink)),
              const SizedBox(height: 8),
              const Text('Login or register to manage your bookings and profile',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppColors.muted, height: 1.5)),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    await Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const LoginScreen()));
                    // Refresh after returning from login
                    setState(() {
                      _user = FirebaseAuth.instance.currentUser;
                    });
                    if (_user != null) _loadProfile();
                  },
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 52),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                  child: const Text('Sign In / Register',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const SizedBox(height: 8),
          // Avatar
          Stack(
            alignment: Alignment.bottomRight,
            children: [
              CircleAvatar(
                radius: 50,
                backgroundColor: AppColors.teal,
                backgroundImage: _user?.photoURL != null ? NetworkImage(_user!.photoURL!) : null,
                child: _user?.photoURL == null
                    ? Text((_nameCtrl.text.isNotEmpty ? _nameCtrl.text : 'U')[0].toUpperCase(),
                        style: const TextStyle(fontSize: 36, color: Colors.white, fontWeight: FontWeight.w700))
                    : null,
              ),
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(color: AppColors.brand, shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2)),
                child: const Icon(Icons.edit, color: Colors.white, size: 16),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(_user?.email ?? '', style: const TextStyle(fontSize: 13, color: AppColors.muted)),
          const SizedBox(height: 24),

          // Form card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Personal Information',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.ink)),
                const SizedBox(height: 16),

                _field('Full Name', _nameCtrl, hint: 'Your full name', icon: Icons.person_rounded),
                const SizedBox(height: 12),
                _field('Mobile Number', _phoneCtrl, hint: '10-digit mobile', icon: Icons.phone_rounded,
                  keyboard: TextInputType.phone),
                const SizedBox(height: 12),

                // Email (readonly)
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('EMAIL', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.muted, letterSpacing: 0.5)),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(
                      color: AppColors.bg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.line),
                    ),
                    child: Row(children: [
                      const Icon(Icons.email_rounded, color: AppColors.muted, size: 18),
                      const SizedBox(width: 10),
                      Text(_user?.email ?? '—', style: const TextStyle(fontSize: 14, color: AppColors.muted)),
                    ]),
                  ),
                ]),
                const SizedBox(height: 12),

                // Gender
                const Text('GENDER', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.muted, letterSpacing: 0.5)),
                const SizedBox(height: 6),
                Row(children: [
                  _genderBtn('male', '👨 Male'),
                  const SizedBox(width: 10),
                  _genderBtn('female', '👩 Female'),
                  const SizedBox(width: 10),
                  _genderBtn('other', '🧑 Other'),
                ]),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Address card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Address',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.ink)),
                const SizedBox(height: 16),
                _field('Address', _addressCtrl, hint: 'House no, Street, Area', icon: Icons.home_rounded, maxLines: 2),
                const SizedBox(height: 12),
                _field('City', _cityCtrl, hint: 'Your city', icon: Icons.location_city_rounded),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Save button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _saveProfile,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _saving
                  ? const SizedBox(width: 22, height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, valueColor: AlwaysStoppedAnimation(Colors.white)))
                  : const Text('💾 Save Changes', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ),

          const SizedBox(height: 12),

          // Sign out
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () async {
                await FirebaseService.signOut();
                if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
              },
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                side: const BorderSide(color: AppColors.red),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('Sign Out', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.red)),
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl,
      {String hint = '', IconData? icon, TextInputType keyboard = TextInputType.text, int maxLines = 1}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.muted, letterSpacing: 0.5)),
      const SizedBox(height: 6),
      TextField(
        controller: ctrl,
        keyboardType: keyboard,
        maxLines: maxLines,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: icon != null ? Icon(icon, color: AppColors.muted, size: 18) : null,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      ),
    ]);
  }

  Widget _genderBtn(String value, String label) {
    final sel = _gender == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _gender = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: sel ? AppColors.tealSoft : AppColors.bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: sel ? AppColors.teal : AppColors.line, width: sel ? 2 : 1),
          ),
          child: Text(label, textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: sel ? AppColors.teal : AppColors.ink2)),
        ),
      ),
    );
  }
}
