package com.houseofmates.holmeshandler

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.util.Log
import android.webkit.MimeTypeMap
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.FileProvider
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder

class HolmesActivity : AppCompatActivity() {

    companion object {
        const val TAG = "Holmes"
        const val MAGIC = "HOLMES"
        const val VERSION = 1
        const val HEADER_READ_SIZE = 128
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Check full files access
        if (Build.VERSION.SDK_INT >= 30 && !Environment.isExternalStorageManager()) {
            requestAllFilesAccess()
            return
        }

        when (intent.action) {
            Intent.ACTION_VIEW -> handleOpen()
            Intent.ACTION_SEND -> handleConvertSingle()
            Intent.ACTION_SEND_MULTIPLE -> handleConvertMultiple()
            else -> {
                Toast.makeText(this, "Unknown action: ${intent.action}", Toast.LENGTH_SHORT).show()
                finish()
            }
        }
    }

    // ── ALL FILES ACCESS ────────────────────────────────────────

    private fun requestAllFilesAccess() {
        // Don't bounce to settings immediately — tell the user to run the Setup app
        Toast.makeText(
            this,
            "Holmes needs file access. Please open the Holmes Setup app once to grant permission, then try again.",
            Toast.LENGTH_LONG
        ).show()
        finish()
    }

    // ── OPEN .holmes ────────────────────────────────────────────

    private fun handleOpen() {
        val uri = intent.data
        if (uri == null) {
            Toast.makeText(this, "No file", Toast.LENGTH_SHORT).show()
            finish()
            return
        }
        Log.i(TAG, "OPEN: $uri (scheme=${uri.scheme})")

        try {
            val extractedFile = extractPayload(uri)
            val headerInfo = parseHeaderFromUri(uri)
            launchViewer(extractedFile, headerInfo.mime)
        } catch (e: Exception) {
            Log.e(TAG, "Open failed", e)
            Toast.makeText(this, "Failed to open: ${e.message}", Toast.LENGTH_LONG).show()
        }
        finish()
    }

    private fun extractPayload(uri: Uri): File {
        // Read header to find payload start
        val headerInfo = parseHeaderFromUri(uri)

        val ext = mimeToExtension(headerInfo.mime)
        val outFile = File(cacheDir, "holmes_open_${System.currentTimeMillis()}.$ext")

        contentResolver.openInputStream(uri)?.use { input ->
            input.skip(headerInfo.payloadStart.toLong())
            FileOutputStream(outFile).use { output ->
                val buf = ByteArray(32768)
                var n: Int
                while (input.read(buf).also { n = it } != -1) {
                    output.write(buf, 0, n)
                }
            }
        } ?: throw IllegalStateException("Cannot read file")

        Log.i(TAG, "Extracted ${outFile.length()} bytes → $outFile")
        return outFile
    }

    // ── CONVERT media → .holmes ─────────────────────────────────

    private fun handleConvertSingle() {
        val uri = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM) ?: run {
            Toast.makeText(this, "No file shared", Toast.LENGTH_SHORT).show()
            finish()
            return
        }
        convertOne(uri)
        finish()
    }

    private fun handleConvertMultiple() {
        val uris = intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
        if (uris.isNullOrEmpty()) {
            Toast.makeText(this, "No files shared", Toast.LENGTH_SHORT).show()
            finish()
            return
        }
        var ok = 0
        var fail = 0
        for (uri in uris) {
            try {
                convertOne(uri)
                ok++
            } catch (e: Exception) {
                Log.e(TAG, "Convert failed for $uri", e)
                fail++
            }
        }
        Toast.makeText(this, "Converted $ok files${if (fail > 0) " ($fail failed)" else ""}", Toast.LENGTH_LONG).show()
        finish()
    }

    private fun convertOne(uri: Uri) {
        Log.i(TAG, "CONVERT: $uri")

        // Get original filename and mime type from content resolver
        val originalName = getFileName(uri) ?: "unknown"
        val mime = getMime(uri, originalName)

        // Copy content to temp file
        val tmpFile = File(cacheDir, "convert_${System.currentTimeMillis()}")
        contentResolver.openInputStream(uri)?.use { input ->
            FileOutputStream(tmpFile).use { output ->
                input.copyTo(output)
            }
        } ?: throw IllegalStateException("Cannot read shared file")

        Log.i(TAG, "  original: $originalName, mime=$mime, size=${tmpFile.length()}")

        // Build .holmes file next to the original if possible, else in Downloads
        val outputDir = getOutputDir(uri) ?: Environment.getExternalStoragePublicDirectory(
            Environment.DIRECTORY_DOWNLOADS
        )
        outputDir.mkdirs()

        val baseName = originalName.substringBeforeLast(".")
        val outputFile = File(outputDir, "$baseName.holmes")

        // If file exists, add numbered suffix
        var finalFile = outputFile
        var counter = 1
        while (finalFile.exists()) {
            finalFile = File(outputDir, "${baseName}_$counter.holmes")
            counter++
        }

        writeHolmes(tmpFile, finalFile, mime)
        tmpFile.delete()
        Log.i(TAG, "  → $finalFile (${finalFile.length()} bytes)")
    }

    private fun getOutputDir(uri: Uri): File? {
        // Try to put .holmes next to the original file
        return when (uri.scheme) {
            "file" -> File(uri.path ?: return null).parentFile
            "content" -> {
                // Try to resolve content URI to file path
                val path = getRealPathFromUri(uri)
                if (path != null) File(path).parentFile else null
            }
            else -> null
        }
    }

    private fun getRealPathFromUri(uri: Uri): String? {
        return try {
            contentResolver.query(uri, arrayOf(android.provider.OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
                if (it.moveToFirst()) {
                    it.getString(0)?.let { name -> return null } // content URI, no DIRECT path
                }
            }
            // Try _data column
            contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                val idx = cursor.getColumnIndex("_data")
                if (idx >= 0 && cursor.moveToFirst()) {
                    return cursor.getString(idx)
                }
            }
            null
        } catch (e: Exception) {
            null
        }
    }

    private fun getFileName(uri: Uri): String? {
        return try {
            contentResolver.query(uri, arrayOf(android.provider.OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
                if (it.moveToFirst()) it.getString(0) else null
            }
        } catch (e: Exception) {
            if (uri.scheme == "file") uri.lastPathSegment else null
        }
    }

    private fun writeHolmes(source: File, dest: File, mime: String) {
        val payload = source.readBytes()
        val header = buildHeader(mime, payload.size.toLong())
        FileOutputStream(dest).use { out ->
            out.write(header)
            out.write(payload)
        }
    }

    // ── HEADER PARSING ──────────────────────────────────────────

    data class HeaderInfo(val mime: String, val version: Int, val payloadStart: Int)

    private fun parseHeaderFromUri(uri: Uri): HeaderInfo {
        val headerBytes = ByteArray(HEADER_READ_SIZE)
        val read = contentResolver.openInputStream(uri)?.use { it.read(headerBytes) }
            ?: throw IllegalStateException("Cannot read file")
        if (read < 10) throw IllegalStateException("Too small for .holmes header ($read bytes)")
        return parseHeader(headerBytes, read)
    }

    private fun parseHeader(data: ByteArray, length: Int): HeaderInfo {
        val magic = String(data, 0, 6)
        if (magic != MAGIC) throw IllegalStateException("Not a .holmes file (bad magic: '$magic')")

        val buf = ByteBuffer.wrap(data).order(ByteOrder.BIG_ENDIAN)
        buf.position(6)
        val version = buf.short.toInt() and 0xFFFF
        val mimeLen = buf.short.toInt() and 0xFFFF
        if (10 + mimeLen > length) throw IllegalStateException("Header truncated")
        val mime = String(data, 10, mimeLen)

        Log.i(TAG, "Header: version=$version mime=$mime mimeLen=$mimeLen")
        return HeaderInfo(mime, version, 10 + mimeLen + 8)
    }

    private fun buildHeader(mime: String, payloadLen: Long): ByteArray {
        val mimeBytes = mime.toByteArray(Charsets.US_ASCII)
        val headerLen = 10 + mimeBytes.size + 8
        val buf = ByteBuffer.allocate(headerLen).order(ByteOrder.BIG_ENDIAN)
        buf.put(MAGIC.toByteArray())          // 6
        buf.putShort(VERSION.toShort())       // 2
        buf.putShort(mimeBytes.size.toShort()) // 2
        buf.put(mimeBytes)                    // N
        buf.putLong(payloadLen)               // 8
        return buf.array()
    }

    // ── MIME DETECTION ──────────────────────────────────────────

    private fun getMime(uri: Uri, fileName: String): String {
        // 1) Try content resolver's type
        val resolverType = contentResolver.getType(uri)
        if (resolverType != null && resolverType != "application/octet-stream") {
            return resolverType
        }

        // 2) Try extension from filename
        val ext = fileName.substringAfterLast('.', "").lowercase()
        if (ext.isNotEmpty()) {
            MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext)?.let { return it }
        }

        return "application/octet-stream"
    }

    // ── VIEWER LAUNCH ───────────────────────────────────────────

    private fun launchViewer(file: File, mime: String) {
        Log.i(TAG, "Launching viewer: $mime ← $file")

        val uri = FileProvider.getUriForFile(this, "${packageName}.fileprovider", file)

        // Grant URI permission to any app that handles this
        grantUriPermission("android", uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)

        val viewIntent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, mime)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }

        val resolved = packageManager.resolveActivity(viewIntent, 0)
        if (resolved != null && resolved.activityInfo.packageName != packageName) {
            Log.i(TAG, "Viewer: ${resolved.activityInfo.packageName}")
            startActivity(viewIntent)
        } else {
            // No viewer or self-match — use chooser
            val chooser = Intent.createChooser(viewIntent, "Open with")
            startActivity(chooser)
        }
    }

    // ── EXTENSION FROM MIME ─────────────────────────────────────

    private fun mimeToExtension(mime: String): String {
        val map = MimeTypeMap.getSingleton()
        return map.getExtensionFromMimeType(mime)
            ?: when {
                mime.startsWith("image/") -> "png"
                mime.startsWith("video/") -> "mp4"
                mime.startsWith("audio/") -> "mp3"
                mime == "application/pdf" -> "pdf"
                else -> "bin"
            }
    }
}