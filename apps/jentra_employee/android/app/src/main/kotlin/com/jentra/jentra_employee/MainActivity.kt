package com.jentra.jentra_employee

import android.os.Bundle
import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.net.Uri
import android.os.SystemClock
import android.os.Build
import android.provider.MediaStore
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var photoResult: MethodChannel.Result? = null
    private val photoRequest = 7071
    private val documentRequest = 7072
    private var documentResult: MethodChannel.Result? = null
    private var documentDestination: Triple<String, Uri, Long>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.jentra.employee/profile-photo")
            .setMethodCallHandler { call, result ->
                if (call.method != "choosePhoto") {
                    result.notImplemented()
                } else if (photoResult != null || documentResult != null) {
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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.jentra.employee/document-export")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "chooseDestination" -> {
                        val mime = call.argument<String>("mimeType")
                        val name = when (mime) {
                            "application/pdf" -> "Jentra-document.pdf"
                            "image/jpeg" -> "Jentra-document.jpg"
                            "image/png" -> "Jentra-document.png"
                            "text/plain" -> "Jentra-document.txt"
                            else -> null
                        }
                        if (name == null || photoResult != null || documentResult != null) {
                            result.error("DOCUMENT_EXPORT_FAILED", "Document saving is unavailable.", null)
                        } else {
                            documentDestination = null
                            documentResult = result
                            try {
                                val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                                    addCategory(Intent.CATEGORY_OPENABLE)
                                    type = mime
                                    putExtra(Intent.EXTRA_TITLE, name)
                                }
                                @Suppress("DEPRECATION")
                                startActivityForResult(intent, documentRequest)
                            } catch (_: Exception) {
                                documentResult = null
                                result.error("DOCUMENT_EXPORT_FAILED", "The save chooser could not open.", null)
                            }
                        }
                    }
                    "writeDocument" -> {
                        val destination = documentDestination
                        val handle = call.argument<String>("handle")
                        val bytes = call.argument<ByteArray>("bytes")
                        // The handle is generated only after the employee chooses a URI.
                        // Dart sends bytes only after fresh server authorization on return.
                        if (destination == null || handle != destination.first ||
                            SystemClock.elapsedRealtime() > destination.third ||
                            bytes == null || bytes.isEmpty() || bytes.size > 10 * 1024 * 1024) {
                            result.error("DOCUMENT_EXPORT_FAILED", "The save request expired.", null)
                        } else {
                            documentDestination = null
                            Thread {
                                try {
                                    contentResolver.openOutputStream(destination.second, "wt")?.use {
                                        it.write(bytes)
                                        it.flush()
                                    } ?: throw IllegalStateException("Destination unavailable")
                                    runOnUiThread { result.success(null) }
                                } catch (_: Exception) {
                                    runOnUiThread { result.error("DOCUMENT_EXPORT_FAILED", "The document could not be saved.", null) }
                                } finally { bytes.fill(0) }
                            }.start()
                        }
                    }
                    "discardDestination" -> {
                        if (call.argument<String>("handle") == documentDestination?.first) documentDestination = null
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    @Deprecated("Activity-result bridge for the native system photo selector")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == documentRequest) {
            val result = documentResult ?: return
            documentResult = null
            val uri = data?.data
            if (resultCode != Activity.RESULT_OK || uri == null || uri.scheme != "content") {
                result.success(null)
                return
            }
            val handle = java.util.UUID.randomUUID().toString()
            documentDestination = Triple(handle, uri, SystemClock.elapsedRealtime() + 5 * 60 * 1000)
            result.success(handle)
            return
        }
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
        documentResult?.error("DOCUMENT_EXPORT_FAILED", "Document saving was interrupted.", null)
        documentResult = null
        documentDestination = null
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
