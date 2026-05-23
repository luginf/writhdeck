package com.writhdeck.app

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.compose.material3.MaterialTheme
import com.writhdeck.app.ui.AppNavigation

class MainActivity : ComponentActivity() {

    private val vm: WrithdeckViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        handleIntent(intent)
        setContent {
            MaterialTheme {
                AppNavigation(vm = vm)
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent) {
        val action = intent.action ?: return
        if (action != Intent.ACTION_VIEW && action != Intent.ACTION_EDIT) return
        val uri = intent.data ?: return
        val canWrite = action == Intent.ACTION_EDIT &&
                (intent.flags and Intent.FLAG_GRANT_WRITE_URI_PERMISSION) != 0
        vm.openExternalContent(uri, contentResolver, canWrite)
    }
}
