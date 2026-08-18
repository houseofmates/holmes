package com.houseofmates.holmeshandler

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.Settings
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat

/**
 * One-time setup: guides the user to grant "All files access"
 * and starts the background watcher service.
 */
class SetupActivity : AppCompatActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        if (Build.VERSION.SDK_INT >= 30 && Environment.isExternalStorageManager()) {
            startWatcher()
            showGranted()
            return
        }

        showSetupPrompt()
    }

    private fun startWatcher() {
        val intent = Intent(this, HolmesWatcherService::class.java)
        ContextCompat.startForegroundService(this, intent)
    }

    private fun showSetupPrompt() {
        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(64, 64, 64, 64)
        }

        val title = TextView(this).apply {
            text = "Holmes Setup"
            textSize = 22f
            setPadding(0, 0, 0, 16)
        }
        layout.addView(title)

        val desc = TextView(this).apply {
            text = "Holmes needs access to all files to open and convert .holmes media files. Tap the button below, then toggle \"Allow access to manage all files\" to ON."
            textSize = 16f
            setPadding(0, 0, 0, 32)
        }
        layout.addView(desc)

        val btn = Button(this).apply {
            text = "Open File Access Settings"
            setOnClickListener {
                val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION).apply {
                    data = Uri.parse("package:$packageName")
                }
                startActivity(intent)
            }
        }
        layout.addView(btn)

        setContentView(layout)
    }

    private fun showGranted() {
        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(64, 64, 64, 64)
        }

        val title = TextView(this).apply {
            text = "Holmes is ready"
            textSize = 22f
            setPadding(0, 0, 0, 16)
        }
        layout.addView(title)

        val desc = TextView(this).apply {
            text = "All files access is granted. The watcher is running — rename any media file to .holmes and it auto-converts. Tap .holmes files to open them with the correct viewer."
            textSize = 16f
            setPadding(0, 0, 0, 32)
        }
        layout.addView(desc)

        val btn = Button(this).apply {
            text = "Close"
            setOnClickListener { finish() }
        }
        layout.addView(btn)

        setContentView(layout)
    }

    override fun onResume() {
        super.onResume()
        if (Build.VERSION.SDK_INT >= 30 && Environment.isExternalStorageManager()) {
            startWatcher()
            showGranted()
        } else {
            showSetupPrompt()
        }
    }
}