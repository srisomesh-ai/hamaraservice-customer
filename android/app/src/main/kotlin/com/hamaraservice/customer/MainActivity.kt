package com.hamaraservice.customer

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity

class MainActivity: FlutterActivity() {
    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannel()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)

            // High priority channel — screen-on and screen-off notifications
            val channel = NotificationChannel(
                "hamaraservice_high_priority",
                "HamaraService Alerts",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Booking and payment notifications"
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 400, 200, 400, 200, 400)
                enableLights(true)
                setShowBadge(true)
                lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
                setBypassDnd(true)  // Show even in Do Not Disturb
            }
            manager.createNotificationChannel(channel)
        }
    }
}
