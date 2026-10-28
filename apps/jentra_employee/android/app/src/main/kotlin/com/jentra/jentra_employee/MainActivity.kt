package com.jentra.jentra_employee

import android.os.Bundle
import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.os.Build
import android.provider.MediaStore
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var photoResult: MethodChannel.Result? = null
    private val photoRequest = 7071

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.jentra.employee/profile-photo")
            .setMethodCallHandler { call, result ->
                if (call.method != "choosePhoto") {
                    result.notImplemented()
                } else if (photoResult != null) {
                    result.error("PHOTO_PICKER_BUSY", "A photo selector is already open.", null)
                } else {
                    photoResult = result
                    try {
                        val intent = if (Build.VERSION.SDK_INT >= 33) {
                            Intent(MediaStore.ACTION_PICK_IMAGES).apply { type = "image/*" }
                        } else {
                            Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE)
                                type = "image/*"
                                putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("image/jpeg", "image/png"))
                            }
                        }
                        @Suppress("DEPRECATION")
                        startActivityForResult(intent, photoRequest)
                    } catch (_: Exception) {
                        photoResult = null
                        result.error("PHOTO_PICKER_FAILED", "The device photo selector could not open.", null)
                    }
                }
            }
    }

    @Deprecated("Activity-result bridge for the native system photo selector")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != photoRequest) return
        val result = photoResult ?: return
        photoResult = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        // Read only the URI selected by the employee, bounded before Dart decoding.
        Thread {
            try {
                val bytes = contentResolver.openInputStream(uri)?.use { input ->
                    val output = java.io.ByteArrayOutputStream()
                    val buffer = ByteArray(8192)
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        if (output.size() + count > 8 * 1024 * 1024) {
                            throw IllegalArgumentException("PHOTO_TOO_LARGE")
                        }
                        output.write(buffer, 0, count)
                    }
                    output.toByteArray()
                } ?: throw IllegalStateException("Unreadable photo")
                runOnUiThread { result.success(bytes) }
            } catch (e: Exception) {
                val code = if (e.message == "PHOTO_TOO_LARGE") "PHOTO_TOO_LARGE" else "PHOTO_PICKER_FAILED"
                runOnUiThread { result.error(code, "Choose a readable JPG or PNG photo smaller than 8 MB.", null) }
            }
        }.start()
    }

    override fun onDestroy() {
        photoResult?.error("PHOTO_PICKER_FAILED", "Photo selection was interrupted.", null)
        photoResult = null
        super.onDestroy()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        // Protect employee information from screenshots and app-switcher previews.
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            getSystemService(NotificationManager::class.java).createNotificationChannel(
                NotificationChannel("jentra_employee_updates", "Jentra Employee updates",
                    NotificationManager.IMPORTANCE_DEFAULT)
            )
        }
    }
}
