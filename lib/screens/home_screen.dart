import 'package:flutter/material.dart';
import '../utils/theme.dart';
import '../services/firebase_service.dart';
import 'login_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseService.currentUser;
    return Scaffold(
      appBar: AppBar(
        title: RichText(
          text: const TextSpan(children: [
            TextSpan(text: 'Hamara', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
            TextSpan(text: 'Service', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.brand)),
          ]),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await FirebaseService.signOut();
              if (context.mounted) {
                Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
              }
            },
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.home_repair_service_rounded, size: 64, color: AppColors.teal),
            const SizedBox(height: 16),
            const Text('Welcome to HamaraService!',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.ink)),
            const SizedBox(height: 8),
            Text('Phone: ${user?.phoneNumber ?? "Guest"}',
              style: const TextStyle(fontSize: 14, color: AppColors.muted)),
            const SizedBox(height: 32),
            const Text('More screens coming soon...', style: TextStyle(color: AppColors.muted)),
          ],
        ),
      ),
    );
  }
}
