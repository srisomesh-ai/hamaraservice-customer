import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import '../../services/api_service.dart';
import '../../utils/theme.dart';
import '../home_screen.dart';

class ReviewScreen extends StatefulWidget {
  final String bookingId;
  final Map<String, dynamic> booking;
  const ReviewScreen({super.key, required this.bookingId, required this.booking});
  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  int _rating = 0;
  final _commentCtrl = TextEditingController();
  bool _submitting = false;
  bool _submitted = false;

  final List<String> _quickReviews = [
    'Excellent work!', 'Very professional', 'On time', 'Clean & tidy',
    'Friendly', 'Would recommend', 'Great service',
  ];
  final Set<String> _selectedQuick = {};

  @override
  void dispose() { _commentCtrl.dispose(); super.dispose(); }

  Future<void> _submitReview() async {
    if (_rating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a rating'),
          backgroundColor: AppColors.red));
      return;
    }
    setState(() => _submitting = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final provId = widget.booking['providerId'] ?? '';
      final comment = _commentCtrl.text.trim().isNotEmpty
          ? _commentCtrl.text.trim()
          : _selectedQuick.join(', ');

      // Submit review to MySQL — auto updates provider rating
      await ApiService.submitReview(
        bookingId:  widget.bookingId,
        providerId: provId,
        rating:     _rating,
        comment:    _comment,
      );

      setState(() { _submitting = false; _submitted = true; });
    } catch (e) {
      setState(() => _submitting = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_submitted) return _buildSuccessScreen();

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Rate Your Experience'),
        backgroundColor: AppColors.teal,
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Service summary
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)],
              ),
              child: Row(children: [
                Container(
                  width: 50, height: 50,
                  decoration: BoxDecoration(
                    color: AppColors.tealSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(child: Text(widget.booking['icon'] ?? '🔧',
                    style: const TextStyle(fontSize: 26))),
                ),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(widget.booking['service'] ?? 'Service',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.ink)),
                  Text('Provider: ${widget.booking['providerName'] ?? ''}',
                    style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                ])),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.greenSoft, borderRadius: BorderRadius.circular(20)),
                  child: const Text('Completed', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.green)),
                ),
              ]),
            ),

            const SizedBox(height: 24),

            const Text('How was your experience?',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.ink)),
            const SizedBox(height: 6),
            const Text('Your feedback helps improve our service quality',
              style: TextStyle(fontSize: 13, color: AppColors.muted)),

            const SizedBox(height: 20),

            // Star rating
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (i) => GestureDetector(
                onTap: () => setState(() => _rating = i + 1),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(
                    i < _rating ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: i < _rating ? AppColors.yellow : AppColors.line,
                    size: 48,
                  ),
                ),
              )),
            ),

            if (_rating > 0) ...[
              const SizedBox(height: 8),
              Text(_ratingLabel(_rating),
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                  color: _ratingColor(_rating))),
            ],

            const SizedBox(height: 24),

            // Quick review chips
            const Align(alignment: Alignment.centerLeft,
              child: Text('Quick Review', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink2))),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8, runSpacing: 8,
              children: _quickReviews.map((q) {
                final sel = _selectedQuick.contains(q);
                return GestureDetector(
                  onTap: () => setState(() {
                    if (sel) _selectedQuick.remove(q);
                    else _selectedQuick.add(q);
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: sel ? AppColors.tealSoft : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: sel ? AppColors.teal : AppColors.line),
                    ),
                    child: Text(q, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                      color: sel ? AppColors.teal : AppColors.ink2)),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 20),

            // Comment
            const Align(alignment: Alignment.centerLeft,
              child: Text('Additional Comments (optional)',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink2))),
            const SizedBox(height: 8),
            TextField(
              controller: _commentCtrl,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'Tell us more about your experience...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),

            const SizedBox(height: 24),

            // Submit
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submitReview,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: _submitting
                    ? const SizedBox(width: 22, height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation(Colors.white)))
                    : const Text('Submit Review',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ),

            const SizedBox(height: 12),

            // Skip
            TextButton(
              onPressed: () => Navigator.pushAndRemoveUntil(context,
                MaterialPageRoute(builder: (_) => const HomeScreen()), (r) => false),
              child: const Text('Skip Review',
                style: TextStyle(color: AppColors.muted, fontSize: 13)),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccessScreen() {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 100, height: 100,
                  decoration: BoxDecoration(color: AppColors.greenSoft, shape: BoxShape.circle),
                  child: const Icon(Icons.favorite_rounded, color: AppColors.green, size: 56),
                ),
                const SizedBox(height: 24),
                const Text('Thank You!', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.ink)),
                const SizedBox(height: 8),
                const Text('Your review helps us improve\nand rewards our providers.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: AppColors.muted, height: 1.5)),
                const SizedBox(height: 32),
                Row(mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (i) => Icon(
                    i < _rating ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: i < _rating ? AppColors.yellow : AppColors.line,
                    size: 36,
                  ))),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pushAndRemoveUntil(context,
                      MaterialPageRoute(builder: (_) => const HomeScreen()), (r) => false),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 52),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Back to Home',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _ratingLabel(int r) {
    switch (r) {
      case 1: return 'Poor';
      case 2: return 'Fair';
      case 3: return 'Good';
      case 4: return 'Very Good';
      case 5: return 'Excellent!';
      default: return '';
    }
  }

  Color _ratingColor(int r) {
    if (r <= 2) return AppColors.red;
    if (r == 3) return AppColors.yellow;
    return AppColors.green;
  }
}