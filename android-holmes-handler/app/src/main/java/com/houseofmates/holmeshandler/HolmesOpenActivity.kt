package com.houseofmates.holmeshandler

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.Settings
import android.util.Log
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.FileProvider
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder

class HolmesOpenActivity : AppCompatActivity() {

    companion object {
        const val TAG = "HolmesHandler"
        const val MAGIC = "HOLMES"
        const val HEADER_READ_SIZE = 128
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val uri = intent.data
        Log.i(TAG, "onCreate called, uri=$uri, scheme=${uri?.scheme}, action=${intent.action}")

        if (uri == null) {
            Log.w(TAG, "No URI in intent")
            Toast.makeText(this, "No file provided", Toast.LENGTH_SHORT).show()
            finish()
            return
        }

        // For file:// URIs, check if we have all-files access
        if (uri.scheme == "file") {
            if (Build.VERSION.SDK_INT >= 30 && !Environment.isExternalStorageManager()) {
                Log.i(TAG, "Need MANAGE_EXTERNAL_STORAGE, launching settings")
                Toast.makeText(
                    this,
                    "Holmes Handler needs file access. Please grant 'All files access'.",
                    Toast.LENGTH_LONG
                ).show()
                val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION).apply {
                    data = Uri.parse("package:$packageName")
                }
                startActivity(intent)
                finish()
                return
            }
        }

        try {
            handleHolmesFile(uri)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to open .holmes", e)
            Toast.makeText(this, "Failed: ${e.message}", Toast.LENGTH_LONG).show()
        }

        finish()
    }

    private fun handleHolmesFile(uri: Uri) {
        Log.i(TAG, "Handling: $uri")

        val headerBytes = ByteArray(HEADER_READ_SIZE)
        val inputStream = contentResolver.openInputStream(uri)

        if (inputStream == null) {
            // fallback: try direct file access for file:// URIs
            if (uri.scheme == "file") {
                val path = uri.path ?: throw IllegalStateException("No path in file URI")
                handleDirectFile(File(path))
                return
            }
            throw IllegalStateException("Cannot open file: $uri")
        }

        val read = inputStream.use { it.read(headerBytes) }
        Log.i(TAG, "Read $read header bytes")
        if (read < 10) throw IllegalStateException("File too small ($read bytes)")

        val (mime, headerSize) = parseHeader(headerBytes, read)

        val extension = mimeToExtension(mime)
        val outputFile = File(cacheDir, "holmes_${System.currentTimeMillis()}.$extension")
        Log.i(TAG, "Extracting to: $outputFile")

        contentResolver.openInputStream(uri)?.use { input ->
            input.skip(headerSize.toLong())
            FileOutputStream(outputFile).use { output ->
                val buffer = ByteArray(8192)
                var bytesRead: Int
                while (input.read(buffer).also { bytesRead = it } != -1) {
                    output.write(buffer, 0, bytesRead)
                }
            }
        } ?: throw IllegalStateException("Cannot re-open for extraction")

        launchViewer(outputFile, mime)
    }

    private fun handleDirectFile(file: File) {
        Log.i(TAG, "Direct file access: $file")
        if (!file.exists()) throw IllegalStateException("File not found: $file")
        if (!file.canRead()) throw IllegalStateException("Cannot read file: $file")

        val headerBytes = file.inputStream().use { it.readBytes() }
        if (headerBytes.size < 10) throw IllegalStateException("File too small")

        val (mime, headerSize) = parseHeader(headerBytes, headerBytes.size)

        val extension = mimeToExtension(mime)
        val outputFile = File(cacheDir, "holmes_${System.currentTimeMillis()}.$extension")
        Log.i(TAG, "Extracting (direct) to: $outputFile")

        file.inputStream().use { input ->
            input.skip(headerSize.toLong())
            FileOutputStream(outputFile).use { output ->
                input.copyTo(output)
            }
        }

        launchViewer(outputFile, mime)
    }

    private data class HeaderInfo(val mime: String, val headerSize: Int)

    private fun parseHeader(data: ByteArray, length: Int): HeaderInfo {
        val magic = String(data, 0, 6)
        if (magic != MAGIC) throw IllegalStateException("Not a .holmes file: magic='$magic'")

        val buf = ByteBuffer.wrap(data).order(ByteOrder.BIG_ENDIAN)
        buf.position(6)
        val version = buf.short.toInt() and 0xFFFF
        val mimeLen = buf.short.toInt() and 0xFFFF
        if (10 + mimeLen > length) throw IllegalStateException("Header truncated")
        val mime = String(data, 10, mimeLen)

        Log.i(TAG, "Parsed: version=$version mime=$mime mimeLen=$mimeLen")
        if (version != 1) throw IllegalStateException("Unsupported version: $version")

        return HeaderInfo(mime, 10 + mimeLen + 8)
    }

    private fun launchViewer(extractedFile: File, mime: String) {
        Log.i(TAG, "Extracted ${extractedFile.length()} bytes, launching viewer for $mime")

        val outputUri = FileProvider.getUriForFile(this, "${packageName}.fileprovider", extractedFile)
        val viewIntent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(outputUri, mime)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }

        val resolved = packageManager.resolveActivity(viewIntent, 0)
        Log.i(TAG, "Resolved viewer: ${resolved?.activityInfo?.packageName ?: "none"}")

        if (resolved != null) {
            startActivity(viewIntent)
        } else {
            val fallback = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(outputUri, "*/*")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(fallback)
        }
    }

    private fun mimeToExtension(mime: String): String {
        return when {
            mime.startsWith("image/png") -> "png"
            mime.startsWith("image/jpeg") -> "jpg"
            mime.startsWith("image/gif") -> "gif"
            mime.startsWith("image/webp") -> "webp"
            mime.startsWith("image/bmp") -> "bmp"
            mime.startsWith("image/svg") -> "svg"
            mime.startsWith("image/") -> "png"
            mime.startsWith("video/mp4") -> "mp4"
            mime.startsWith("video/webm") -> "webm"
            mime.startsWith("video/x-matroska") -> "mkv"
            mime.startsWith("video/quicktime") -> "mov"
            mime.startsWith("video/") -> "mp4"
            mime.startsWith("audio/mpeg") -> "mp3"
            mime.startsWith("audio/mp4") -> "m4a"
            mime.startsWith("audio/wav") || mime.startsWith("audio/x-wav") -> "wav"
            mime.startsWith("audio/flac") -> "flac"
            mime.startsWith("audio/ogg") -> "ogg"
            mime.startsWith("audio/opus") -> "opus"
            mime.startsWith("audio/aac") -> "aac"
            mime.startsWith("audio/") -> "mp3"
            mime.startsWith("application/pdf") -> "pdf"
            else -> "bin"
        }
    }
}