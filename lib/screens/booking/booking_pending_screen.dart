import 'package:flutter/material.dart';
import '../../utils/theme.dart';
import '../home_screen.dart';

class BookingPendingScreen extends StatelessWidget {
  final String bookingId;
  final Map<String, dynamic> service;
  final DateTime date;
  final String timeSlot;
  final String address;
  final int price;

  const BookingPendingScreen({
    super.key,
    required this.bookingId,
    required this.service,
    required this.date,
    required this.timeSlot,
    required this.address,
    required this.price,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),

              // Icon
              Container(
                width: 100, height: 100,
                decoration: BoxDecoration(
                  color: AppColors.yellow.withOpacity(0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.yellow.withOpacity(0.4), width: 2),
                ),
                child: const Icon(Icons.pending_actions_rounded, size: 50, color: AppColors.yellow),
              ),

              const SizedBox(height: 24),

              const Text('Booking Pending',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.ink)),
              const SizedBox(height: 8),
              const Text(
                'No providers available right now.\nYour booking is saved and visible to all nearby providers.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: AppColors.muted, height: 1.5),
              ),

              const SizedBox(height: 32),

              // Booking details card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12)],
                ),
                child: Column(children: [
                  Row(children: [
                    Container(
                      width: 48, height: 48,
                      decoration: BoxDecoration(
                        color: Color(service['color'] != null ? service['color'] as int : 0xFF1B6B7A),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(child: Text(service['icon'] as String,
                        style: const TextStyle(fontSize: 26))),
                    ),
                    const SizedBox(width: 14),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(service['name'] as String,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.ink)),
                      Text('Booking ID: ${bookingId.substring(0, 8).toUpperCase()}',
                        style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                    ])),
                    Text('₹$price',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.teal)),
                  ]),
                  const Divider(height: 24, color: AppColors.line),
                  _row(Icons.calendar_today_rounded,
                    '${date.day}/${date.month}/${date.year} at $timeSlot'),
                  const SizedBox(height: 8),
                  _row(Icons.location_on_rounded, address),
                ]),
              ),

              const SizedBox(height: 24),

              // Info box
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.yellow.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.yellow.withOpacity(0.3)),
                ),
                child: const Column(children: [
                  Row(children: [
                    Icon(Icons.notifications_active_rounded, color: AppColors.yellow, size: 18),
                    SizedBox(width: 10),
                    Expanded(child: Text('You\'ll get notified when a provider accepts',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.yellow))),
                  ]),
                  SizedBox(height: 8),
                  Row(children: [
                    Icon(Icons.visibility_rounded, color: AppColors.yellow, size: 18),
                    SizedBox(width: 10),
                    Expanded(child: Text('Your booking is visible to all nearby providers',
                      style: TextStyle(fontSize: 13, color: AppColors.yellow))),
                  ]),
                  SizedBox(height: 8),
                  Row(children: [
                    Icon(Icons.timer_rounded, color: AppColors.yellow, size: 18),
                    SizedBox(width: 10),
                    Expanded(child: Text('Most bookings get accepted within a few hours',
                      style: TextStyle(fontSize: 13, color: AppColors.yellow))),
                  ]),
                ]),
              ),

              const Spacer(),

              // Back to home
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const HomeScreen()),
                    (route) => false,
                  ),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 52),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Back to Home', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),

              const SizedBox(height: 16),

              TextButton(
                onPressed: () => Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const HomeScreen()),
                  (route) => false,
                ),
                child: const Text('View My Bookings',
                  style: TextStyle(color: AppColors.teal, fontWeight: FontWeight.w600, fontSize: 14)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(IconData icon, String text) {
    return Row(children: [
      Icon(icon, size: 16, color: AppColors.teal),
      const SizedBox(width: 8),
      Expanded(child: Text(text, style: const TextStyle(fontSize: 13, color: AppColors.ink2))),
    ]);
  }
}
