import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

// Global sound manager — call from anywhere
class SoundManager {
  static final AudioPlayer _player = AudioPlayer();

  static Future<void> play(AppSound sound) async {
    HapticFeedback.mediumImpact();
    try {
      await _player.stop();
      await _player.play(AssetSource(_path(sound)));
    } catch (_) {}
  }

  static Future<void> stop() async {
    try { await _player.stop(); } catch (_) {}
  }

  static String _path(AppSound s) {
    switch (s) {
      case AppSound.orderPlaced:    return 'sounds/order_placed.mp3';
      case AppSound.orderAccepted:  return 'sounds/order_accepted.mp3';
      case AppSound.cancelled:      return 'sounds/cancelled.mp3';
      case AppSound.payment:        return 'sounds/payment.mp3';
      case AppSound.rating:         return 'sounds/rating.mp3';
      case AppSound.success:        return 'sounds/success.mp3';
      case AppSound.alert:          return 'sounds/alert.mp3';
    }
  }
}

enum AppSound {
  orderPlaced,
  orderAccepted,
  cancelled,
  payment,
  rating,
  success,
  alert,
}
