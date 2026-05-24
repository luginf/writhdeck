package com.writhdeck.app

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

class WrithdeckEngine(private val context: Context) {

    external fun nativeInit(filesDir: String): Boolean
    external fun nativeEval(script: String): String
    external fun nativeGetVar(varName: String): String
    external fun nativeSetVar(varName: String, value: String)
    external fun nativeDestroy()

    companion object {
        private var libLoaded = false
        fun tryLoad(): Boolean {
            if (libLoaded) return true
            return try {
                System.loadLibrary("writhdeck")
                libLoaded = true
                true
            } catch (e: UnsatisfiedLinkError) {
                false
            }
        }
    }

    val available = tryLoad()

    suspend fun init(docsDir: String): Boolean {
        if (!available) return false
        return withContext(Dispatchers.IO) {
            copyAssetsToFilesDir()
            val ok = nativeInit(context.filesDir.absolutePath)
            if (ok) {
                nativeSetVar("::ANDROID_DOCS_DIR", docsDir)
                val boot = File(context.filesDir, "tcl/boot-android.tcl").absolutePath
                val result = nativeEval("source {$boot}")
                if (result.startsWith("ERROR:") || result.contains("not found")) {
                    android.util.Log.e("WrithdeckEngine", "boot error: $result")
                }
            }
            ok
        }
    }

    suspend fun eval(script: String): String = withContext(Dispatchers.IO) {
        if (!available) "ERROR: native library not loaded"
        else nativeEval(script)
    }

    suspend fun setVar(name: String, value: String) = withContext(Dispatchers.IO) {
        if (available) nativeSetVar(name, value)
    }

    fun destroy() {
        if (available) nativeDestroy()
    }

    // Copy assets/tcl/** to filesDir/tcl/** on first install or update
    private fun copyAssetsToFilesDir() {
        val tclDir = File(context.filesDir, "tcl")
        tclDir.mkdirs()
        copyAssetDir("tcl", tclDir)
    }

    private fun copyAssetDir(assetPath: String, destDir: File) {
        val entries = context.assets.list(assetPath) ?: return
        for (entry in entries) {
            val subAsset = "$assetPath/$entry"
            val dest = File(destDir, entry)
            val children = context.assets.list(subAsset)
            if (!children.isNullOrEmpty()) {
                dest.mkdirs()
                copyAssetDir(subAsset, dest)
            } else {
                context.assets.open(subAsset).use { src ->
                    dest.outputStream().use { src.copyTo(it) }
                }
            }
        }
    }
}
