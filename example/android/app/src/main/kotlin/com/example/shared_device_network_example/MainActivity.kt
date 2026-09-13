package com.example.shared_device_network_example

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannels()
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val notificationManager = getSystemService(NotificationManager::class.java)

            // Primary channel matching kNotificationChannelId in Dart
            val serviceChannel = NotificationChannel(
                "shared_device_bg_service_channel",
                "Shared Device Background Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shared Device Network background server active notification"
                setShowBadge(false)
            }

            // Fallback default channel used by flutter_background_service
            val defaultChannel = NotificationChannel(
                "FOREGROUND_DEFAULT",
                "Background Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Executing process in background"
                setShowBadge(false)
            }

            notificationManager?.createNotificationChannel(serviceChannel)
            notificationManager?.createNotificationChannel(defaultChannel)
        }
    }
}
