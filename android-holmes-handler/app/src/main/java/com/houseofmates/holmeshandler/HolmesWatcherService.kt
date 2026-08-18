package com.houseofmates.holmeshandler

import android.app.Service
import android.content.Intent
import android.os.*
import android.util.Log
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Background service that watches common directories for new .holmes files.
 * When a .holmes file appears without a valid HOLMES header, it wraps the
 * raw bytes into a proper holmes container with the correct MIME type.
 *
 * This enables the "rename to .holmes" workflow:
 *   mix file explorer → rename photo.jpg → photo.holmes
 *   → within seconds, the file is wrapped with HOLMES header
 */
class HolmesWatcherService : Service() {

    companion object {
        const val TAG = "HolmesWatcher"
        const val MAGIC = "HOLMES"

        val WATCH_DIRS = arrayOf(
            "/storage/emulated/0/DCIM",
            "/storage/emulated/0/Download",
            "/storage/emulated/0/Pictures",
            "/storage/emulated/0/Movies",
            "/storage/emulated/0/Music",
        )
    }

    private val observers = mutableListOf<FileObserver>()
    private val handlerThread = HandlerThread("HolmesWatcher")
    private lateinit var handler: Handler

    override fun onCreate() {
        super.onCreate()
        handlerThread.start()
        handler = Handler(handlerThread.looper)

        // Create notification channel for foreground service
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = android.app.NotificationChannel(
                "holmes_watcher",
                "Holmes File Watcher",
                android.app.NotificationManager.IMPORTANCE_LOW
            )
            val nm = getSystemService(android.app.NotificationManager::class.java)
            nm.createNotificationChannel(channel)
        }

        val notification = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            android.app.Notification.Builder(this, "holmes_watcher")
                .setContentTitle("Holmes")
                .setContentText("Watching for .holmes files")
                .setSmallIcon(android.R.drawable.ic_menu_gallery)
                .build()
        } else {
            @Suppress("DEPRECATION")
            android.app.Notification.Builder(this)
                .setContentTitle("Holmes")
                .setContentText("Watching for .holmes files")
                .setSmallIcon(android.R.drawable.ic_menu_gallery)
                .build()
        }
        startForeground(1001, notification)

        for (dir in WATCH_DIRS) {
            val f = File(dir)
            if (f.exists() && f.isDirectory) {
                val observer = HolmesFileObserver(dir)
                observer.startWatching()
                observers.add(observer)
                Log.i(TAG, "Watching: $dir")
            } else {
                Log.w(TAG, "Directory not found: $dir")
            }
        }

        // Also scan existing .holmes files for ones missing headers
        handler.post { scanExisting() }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        for (o in observers) o.stopWatching()
        handlerThread.quitSafely()
        super.onDestroy()
    }

    private fun scanExisting() {
        for (dir in WATCH_DIRS) {
            File(dir).walkTopDown().filter {
                it.isFile && it.name.endsWith(".holmes", ignoreCase = true)
            }.forEach { file ->
                if (!hasValidHeader(file)) {
                    Log.i(TAG, "Found orphan .holmes: ${file.absolutePath}")
                    convertFile(file)
                }
            }
        }
    }

    private fun hasValidHeader(file: File): Boolean {
        if (file.length() < 6) return false
        return try {
            val magic = ByteArray(6)
            FileInputStream(file).use { it.read(magic) }
            String(magic) == MAGIC
        } catch (e: Exception) {
            false
        }
    }

    private fun convertFile(holmesFile: File) {
        try {
            if (holmesFile.length() == 0L) {
                Log.w(TAG, "Empty file, skipping: ${holmesFile.name}")
                return
            }
            if (holmesFile.length() < 6) {
                Log.w(TAG, "Too small, skipping: ${holmesFile.name}")
                return
            }

            // Check header — might have been converted already
            if (hasValidHeader(holmesFile)) {
                Log.d(TAG, "Already valid: ${holmesFile.name}")
                return
            }

            val originalBytes = holmesFile.readBytes()
            if (originalBytes.isEmpty()) return

            // Detect MIME type from magic bytes or content
            val mime = detectMime(originalBytes)
            Log.i(TAG, "Converting: ${holmesFile.name} (${originalBytes.size} bytes, mime=$mime)")

            val header = buildHeader(mime, originalBytes.size.toLong())
            val tmpFile = File(holmesFile.parent, ".${holmesFile.name}.tmp")

            FileOutputStream(tmpFile).use { out ->
                out.write(header)
                out.write(originalBytes)
            }

            if (tmpFile.renameTo(holmesFile)) {
                Log.i(TAG, "✓ ${holmesFile.name} (+${header.size} bytes header)")
            } else {
                // fallback: copy then delete
                holmesFile.delete()
                tmpFile.renameTo(holmesFile)
                Log.i(TAG, "✓ (fallback) ${holmesFile.name}")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to convert ${holmesFile.name}: ${e.message}", e)
        }
    }

    private fun detectMime(bytes: ByteArray): String {
        // Magic byte detection for common formats
        when {
            // PNG: 89 50 4E 47
            bytes.size >= 4 && bytes[0] == 0x89.toByte() && bytes[1] == 0x50.toByte()
                && bytes[2] == 0x4E.toByte() && bytes[3] == 0x47.toByte() -> return "image/png"
            // JPEG: FF D8 FF
            bytes.size >= 3 && bytes[0] == 0xFF.toByte() && bytes[1] == 0xD8.toByte()
                && bytes[2] == 0xFF.toByte() -> return "image/jpeg"
            // GIF: 47 49 46
            bytes.size >= 3 && String(bytes, 0, 3) == "GIF" -> return "image/gif"
            // WebP: 52 49 46 46 ... 57 45 42 50
            bytes.size >= 12 && String(bytes, 0, 4) == "RIFF"
                && String(bytes, 8, 4) == "WEBP" -> return "image/webp"
            // BMP: 42 4D
            bytes.size >= 2 && bytes[0] == 0x42.toByte()
                && bytes[1] == 0x4D.toByte() -> return "image/bmp"
            // MP4: ... ftyp
            bytes.size >= 8 && String(bytes, 4, 4) == "ftyp" -> return "video/mp4"
            // WebM: 1A 45 DF A3
            bytes.size >= 4 && bytes[0] == 0x1A.toByte() && bytes[1] == 0x45.toByte()
                && bytes[2] == 0xDF.toByte() && bytes[3] == 0xA3.toByte() -> return "video/webm"
            // MKV: 1A 45 DF A3 ... but different container — use matroska
            // MP3: FF FB or ID3
            bytes.size >= 3 && bytes[0] == 0xFF.toByte() && (bytes[1].toInt() and 0xE0) == 0xE0 -> return "audio/mpeg"
            bytes.size >= 3 && String(bytes, 0, 3) == "ID3" -> return "audio/mpeg"
            // FLAC: 66 4C 61 43
            bytes.size >= 4 && String(bytes, 0, 4) == "fLaC" -> return "audio/flac"
            // OGG: 4F 67 67 53
            bytes.size >= 4 && String(bytes, 0, 4) == "OggS" -> return "audio/ogg"
            // WAV: 52 49 46 46 ... 57 41 56 45
            bytes.size >= 12 && String(bytes, 0, 4) == "RIFF"
                && String(bytes, 8, 4) == "WAVE" -> return "audio/wav"
            // PDF: 25 50 44 46
            bytes.size >= 4 && String(bytes, 0, 4) == "%PDF" -> return "application/pdf"
            // ZIP-based (may contain media): PK
            bytes.size >= 2 && bytes[0] == 0x50.toByte() && bytes[1] == 0x4B.toByte() -> return "application/zip"
        }
        return "application/octet-stream"
    }

    private fun buildHeader(mime: String, payloadLen: Long): ByteArray {
        val mimeBytes = mime.toByteArray(Charsets.US_ASCII)
        val headerLen = 10 + mimeBytes.size + 8
        val buf = ByteBuffer.allocate(headerLen).order(ByteOrder.BIG_ENDIAN)
        buf.put(MAGIC.toByteArray())
        buf.putShort(1.toShort()) // version
        buf.putShort(mimeBytes.size.toShort())
        buf.put(mimeBytes)
        buf.putLong(payloadLen)
        return buf.array()
    }

    /**
     * FileObserver that watches for .holmes CLOSE_WRITE and MOVED_TO events.
     */
    inner class HolmesFileObserver(private val watchDir: String) : FileObserver(
        File(watchDir), CLOSE_WRITE or MOVED_TO
    ) {
        override fun onEvent(event: Int, relativePath: String?) {
            if (relativePath == null) return
            if (!relativePath.endsWith(".holmes", ignoreCase = true)) return

            val file = File(watchDir, relativePath)
            Log.d(TAG, "Event $event: ${file.absolutePath}")

            // Small delay to let the file system settle
            handler.postDelayed({
                if (file.exists() && !hasValidHeader(file)) {
                    convertFile(file)
                }
            }, 500)
        }
    }
}