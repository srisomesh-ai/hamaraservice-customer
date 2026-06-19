import 'package:flutter/material.dart';
import '../../utils/theme.dart';
import '../home_screen.dart';

class BookingConfirmedScreen extends StatelessWidget {
  final String bookingId;
  final Map<String, dynamic> service;
  final DateTime date;
  final String timeSlot;
  final String address;
  final int price;

  const BookingConfirmedScreen({
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
              // Success animation
              Container(
                width: 100, height: 100,
                decoration: BoxDecoration(
                  color: AppColors.greenSoft,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: AppColors.green.withOpacity(0.3), blurRadius: 24, spreadRadius: 4)],
                ),
                child: const Icon(Icons.check_rounded, color: AppColors.green, size: 56),
              ),
              const SizedBox(height: 24),
              const Text('Booking Confirmed! 🎉',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.ink),
                textAlign: TextAlign.center),
              const SizedBox(height: 8),
              const Text('Your provider will be assigned shortly.\nYou\'ll receive a notification when confirmed.',
                style: TextStyle(fontSize: 14, color: AppColors.muted, height: 1.5),
                textAlign: TextAlign.center),
              const SizedBox(height: 32),

              // Booking details card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12)],
                ),
                child: Column(
                  children: [
                    Row(children: [
                      Container(
                        width: 48, height: 48,
                        decoration: BoxDecoration(
                          color: Color(service['color'] != null ? service['color'] as int : 0xFF1B6B7A),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(child: Text(service['icon'] as String, style: const TextStyle(fontSize: 26))),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(service['name'] as String,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.ink)),
                          Text('Booking ID: ${bookingId.substring(0, 8).toUpperCase()}',
                            style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                        ],
                      )),
                      Text('₹$price',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.teal)),
                    ]),
                    const Divider(height: 24, color: AppColors.line),
                    _detailRow(Icons.calendar_today_rounded,
                      '${date.day}/${date.month}/${date.year} at $timeSlot'),
                    const SizedBox(height: 10),
                    _detailRow(Icons.location_on_rounded, address),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Info banner
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.tealSoft,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.teal.withOpacity(0.2)),
                ),
                child: const Row(children: [
                  Icon(Icons.info_outline_rounded, color: AppColors.teal, size: 20),
                  SizedBox(width: 10),
                  Expanded(child: Text(
                    'Payment will be collected after service completion.',
                    style: TextStyle(fontSize: 13, color: AppColors.teal),
                  )),
                ]),
              ),

              const Spacer(),

              // Buttons
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
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const HomeScreen()),
                    (route) => false,
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 52),
                    side: const BorderSide(color: AppColors.teal),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('View My Bookings',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.teal)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.teal, size: 16),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13, color: AppColors.ink2))),
      ],
    );
  }
}
