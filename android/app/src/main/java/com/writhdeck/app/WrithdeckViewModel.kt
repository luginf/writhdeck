package com.writhdeck.app

import android.Manifest
import android.app.Application
import android.content.ContentResolver
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import androidx.core.content.ContextCompat
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

data class DocEntry(val name: String, val path: String)
data class StatEntry(val date: String, val words: Int)
data class ThemeColors(
    val bg: String = "#1a1a1a",
    val fg: String = "#d4cfbf",
    val headingColor: String = "#87ceeb"
)

class WrithdeckViewModel(app: Application) : AndroidViewModel(app) {

    private val engine = WrithdeckEngine(app)

    private val externalDocsDir = File(
        Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOCUMENTS), "writhdeck"
    )
    private val internalDocsDir = File(app.filesDir, "documents")

    private val _storagePermissionGranted = MutableStateFlow(checkStoragePermission())
    val storagePermissionGranted = _storagePermissionGranted.asStateFlow()

    private val docsDir: File get() =
        if (_storagePermissionGranted.value) externalDocsDir else internalDocsDir

    private val _engineReady = MutableStateFlow(false)
    val engineReady = _engineReady.asStateFlow()

    private val _docs = MutableStateFlow<List<DocEntry>>(emptyList())
    val docs = _docs.asStateFlow()

    private val _recentDocs = MutableStateFlow<List<DocEntry>>(emptyList())
    val recentDocs = _recentDocs.asStateFlow()

    private val _favoriteDocs = MutableStateFlow<List<DocEntry>>(emptyList())
    val favoriteDocs = _favoriteDocs.asStateFlow()

    private val _content = MutableStateFlow("")
    val content = _content.asStateFlow()

    private val _wordCount = MutableStateFlow(0)
    val wordCount = _wordCount.asStateFlow()

    private val _currentFile = MutableStateFlow<DocEntry?>(null)
    val currentFile = _currentFile.asStateFlow()

    private val _dirty = MutableStateFlow(false)
    val dirty = _dirty.asStateFlow()

    private val _headingMarker = MutableStateFlow("=")
    val headingMarker = _headingMarker.asStateFlow()
    private val _markdownHeadings = MutableStateFlow(true)
    val markdownHeadings = _markdownHeadings.asStateFlow()
    private val _keyToc = MutableStateFlow("F11")
    val keyToc = _keyToc.asStateFlow()

    private val _timerType = MutableStateFlow("countdown")
    val timerType = _timerType.asStateFlow()

    private val _themeColors = MutableStateFlow(ThemeColors())
    val themeColors = _themeColors.asStateFlow()
    private val _timerActive = MutableStateFlow(false)
    val timerActive = _timerActive.asStateFlow()
    private val _timerRemaining = MutableStateFlow(0)
    val timerRemaining = _timerRemaining.asStateFlow()
    private val _timerLastTick = MutableStateFlow(0L)
    val timerLastTick = _timerLastTick.asStateFlow()

    private var timerJob: Job? = null

    private var externalUri: Uri? = null
    private var externalWritable = false

    private val _snackbarMessage = MutableStateFlow<String?>(null)
    val snackbarMessage = _snackbarMessage.asStateFlow()

    init {
        viewModelScope.launch { initEngine() }
    }

    private suspend fun initEngine() {
        val dd = docsDir.also { it.mkdirs() }
        engine.init(dd.absolutePath)
        _engineReady.value = true
        _headingMarker.value = engine.eval("set ::cfg_heading_marker").trim().ifEmpty { "=" }
        _markdownHeadings.value = engine.eval("set ::cfg_markdown_headings").trim() != "0"
        _keyToc.value = engine.eval("set ::cfg_key_toc").trim().ifEmpty { "F11" }
        _timerType.value = engine.eval("set ::cfg_timer_type").trim().ifEmpty { "countdown" }
        applyTimerState(engine.eval("android-timer-state"), resetLastTick = true)
        _themeColors.value = loadThemeColors()
        refreshDocs()
        refreshFavorites()
        refreshRecents()
    }

    // Called from onResume / permission result in MainActivity
    fun onStoragePermissionGranted() {
        if (_storagePermissionGranted.value) return
        _storagePermissionGranted.value = true
        viewModelScope.launch {
            _snackbarMessage.value = "Migrating documents..."
            withContext(Dispatchers.IO) {
                externalDocsDir.mkdirs()
                internalDocsDir.listFiles()?.filter { it.isFile }?.forEach { f ->
                    val dst = File(externalDocsDir, f.name)
                    if (!dst.exists()) f.copyTo(dst)
                    f.delete()
                }
            }
            _engineReady.value = false
            timerJob?.cancel(); timerJob = null
            withContext(Dispatchers.IO) { engine.destroy() }
            initEngine()
            _snackbarMessage.value = "Documents stored in Documents/writhdeck/"
        }
    }

    fun dismissSnackbar() { _snackbarMessage.value = null }

    // --- Docs ---

    fun refreshDocs() {
        viewModelScope.launch(Dispatchers.IO) {
            docsDir.mkdirs()
            val files = docsDir
                .listFiles { f -> f.isFile && (f.extension == "txt" || f.extension == "md" || f.extension == "ini") }
                ?.sortedByDescending { it.lastModified() }
                ?.map { DocEntry(it.name, it.absolutePath) }
                ?: emptyList()
            _docs.value = files
        }
    }

    fun refreshFavorites() {
        viewModelScope.launch {
            if (!_engineReady.value) return@launch
            val raw = withContext(Dispatchers.Default) {
                engine.eval("join \$::state_favorites \"\n\"")
            }
            val entries = raw.lines()
                .map { it.trim() }
                .filter { it.isNotEmpty() }
                .mapNotNull { path ->
                    val f = File(path)
                    if (f.exists() && f.canRead()) DocEntry(f.name, f.absolutePath) else null
                }
            _favoriteDocs.value = entries
        }
    }

    fun openFile(entry: DocEntry) {
        viewModelScope.launch {
            val text = withContext(Dispatchers.IO) { File(entry.path).readText() }
            _content.value = text
            _currentFile.value = entry
            _dirty.value = false
            _wordCount.value = countWords(text)
            if (_engineReady.value) {
                engine.eval("recent-push {${entry.path}}")
                refreshRecents()
            }
        }
    }

    fun openIniFile() {
        viewModelScope.launch {
            val iniFile = File(docsDir, "writhdeck.ini")
            if (_engineReady.value) {
                docsDir.mkdirs()
                engine.eval("ini-save")
            }
            val text = withContext(Dispatchers.IO) {
                if (iniFile.exists()) iniFile.readText() else ""
            }
            _content.value = text
            _currentFile.value = DocEntry("writhdeck.ini", iniFile.absolutePath)
            _dirty.value = false
            _wordCount.value = countWords(text)
        }
    }

    private fun refreshRecents() {
        viewModelScope.launch {
            if (!_engineReady.value) return@launch
            val raw = withContext(Dispatchers.Default) {
                engine.eval("join \$::state_recent \"\n\"")
            }
            val entries = raw.lines()
                .map { it.trim() }
                .filter { it.isNotEmpty() }
                .mapNotNull { path ->
                    val f = File(path)
                    if (f.exists() && f.canRead()) DocEntry(f.name, f.absolutePath) else null
                }
                .take(10)
            _recentDocs.value = entries
        }
    }

    fun updateContent(text: String) {
        if (text == _content.value) return
        _content.value = text
        _dirty.value = true
        _wordCount.value = countWords(text)
    }

    fun createFile(name: String) {
        viewModelScope.launch(Dispatchers.IO) {
            docsDir.mkdirs()
            val safeName = if (name.endsWith(".txt") || name.endsWith(".md")) name else "$name.txt"
            File(docsDir, safeName).createNewFile()
            refreshDocs()
        }
    }

    fun renameFile(entry: DocEntry, newName: String) {
        viewModelScope.launch(Dispatchers.IO) {
            val ext = File(entry.path).extension
            val safeName = if (newName.endsWith(".txt") || newName.endsWith(".md")) newName
                           else if (ext.isNotEmpty()) "$newName.$ext" else "$newName.txt"
            val parent = File(entry.path).parentFile ?: docsDir
            val dst = File(parent, safeName)
            val src = File(entry.path)
            if (dst.exists() || !src.renameTo(dst)) {
                _snackbarMessage.value = "Could not rename"
                return@launch
            }
            if (_engineReady.value) {
                engine.setVar("::android_old", entry.path)
                engine.setVar("::android_new", dst.absolutePath)
                engine.eval("""
                    recent-rename ${'$'}::android_old ${'$'}::android_new
                    if {[lsearch -exact ${'$'}::state_favorites ${'$'}::android_old] >= 0} {
                        toggle-favorite ${'$'}::android_old
                        toggle-favorite ${'$'}::android_new
                    }
                    state-save
                """.trimIndent())
            }
            if (_currentFile.value?.path == entry.path) {
                _currentFile.value = DocEntry(dst.name, dst.absolutePath)
            }
            refreshDocs()
            refreshFavorites()
            refreshRecents()
        }
    }

    fun deleteFile(entry: DocEntry) {
        viewModelScope.launch(Dispatchers.IO) {
            File(entry.path).delete()
            if (_engineReady.value) {
                engine.setVar("::android_del", entry.path)
                engine.eval("""
                    recent-remove ${'$'}::android_del
                    if {[lsearch -exact ${'$'}::state_favorites ${'$'}::android_del] >= 0} {
                        toggle-favorite ${'$'}::android_del
                    }
                    state-save
                """.trimIndent())
            }
            if (_currentFile.value?.path == entry.path) {
                _currentFile.value = null
                _content.value = ""
                _dirty.value = false
            }
            refreshDocs()
            refreshFavorites()
            refreshRecents()
        }
    }

    fun backupFile(entry: DocEntry) {
        viewModelScope.launch {
            if (!_engineReady.value) return@launch
            val result = withContext(Dispatchers.Default) {
                engine.eval("android-backup {${entry.path}}")
            }
            _snackbarMessage.value = if (result.startsWith("ERROR:")) "Backup failed"
                                     else "Backed up: ${File(result).name}"
        }
    }

    fun toggleFavorite(entry: DocEntry) {
        viewModelScope.launch {
            if (!_engineReady.value) return@launch
            withContext(Dispatchers.Default) {
                engine.eval("toggle-favorite {${entry.path}}\nstate-save")
            }
            refreshFavorites()
        }
    }

    fun clearExternalFile() {
        externalUri = null
        externalWritable = false
    }

    fun openExternalContent(uri: Uri, contentResolver: ContentResolver, canWrite: Boolean) {
        viewModelScope.launch {
            val text = withContext(Dispatchers.IO) {
                contentResolver.openInputStream(uri)?.use { it.bufferedReader().readText() } ?: ""
            }
            externalUri = uri
            externalWritable = canWrite
            val name = uri.lastPathSegment?.substringAfterLast('/') ?: "untitled.txt"
            _currentFile.value = DocEntry(name, uri.toString())
            _content.value = text
            _dirty.value = false
            _wordCount.value = countWords(text)
        }
    }

    fun saveFile() {
        val entry = _currentFile.value ?: return
        val uri = externalUri
        if (uri != null && externalWritable) {
            val cr = getApplication<Application>().contentResolver
            viewModelScope.launch {
                withContext(Dispatchers.IO) {
                    cr.openOutputStream(uri, "wt")?.use {
                        it.writer().use { w -> w.write(_content.value) }
                    }
                }
                _dirty.value = false
            }
        } else if (uri == null) {
            viewModelScope.launch {
                withContext(Dispatchers.IO) { File(entry.path).writeText(_content.value) }
                _dirty.value = false
                if (_engineReady.value) {
                    engine.eval("state-save")
                    if (entry.name == "writhdeck.ini") reloadConfig()
                }
            }
        }
    }

    private suspend fun reloadConfig() {
        withContext(Dispatchers.Default) { engine.eval("ini-load\nkeys-init") }
        _headingMarker.value = engine.eval("set ::cfg_heading_marker").trim().ifEmpty { "=" }
        _markdownHeadings.value = engine.eval("set ::cfg_markdown_headings").trim() != "0"
        _keyToc.value = engine.eval("set ::cfg_key_toc").trim().ifEmpty { "F11" }
        _timerType.value = engine.eval("set ::cfg_timer_type").trim().ifEmpty { "countdown" }
        _themeColors.value = loadThemeColors()
    }

    private suspend fun loadThemeColors(): ThemeColors {
        val raw = engine.eval("android-get-theme").trim()
        val parts = raw.split(Regex("\\s+"))
        if (parts.size >= 3 && parts[0].startsWith("#"))
            return ThemeColors(bg = parts[0], fg = parts[1], headingColor = parts[2])
        return ThemeColors()
    }

    // --- Timer ---

    private fun applyTimerState(result: String, resetLastTick: Boolean = false) {
        val parts = result.trim().split(" ")
        val active = parts.getOrNull(0) == "1"
        val remaining = parts.getOrNull(1)?.toIntOrNull() ?: 0
        val tclTick = parts.getOrNull(2)?.toLongOrNull() ?: 0L
        _timerActive.value = active
        _timerRemaining.value = remaining
        if (resetLastTick) {
            _timerLastTick.value = if (tclTick == 0L) 0L else System.currentTimeMillis()
        }
    }

    private fun startTick() {
        timerJob?.cancel()
        timerJob = viewModelScope.launch {
            while (true) {
                delay(1000)
                val result = engine.eval("android-timer-tick")
                val parts = result.trim().split(" ")
                val active = parts.getOrNull(0) == "1"
                val remaining = parts.getOrNull(1)?.toIntOrNull() ?: 0
                _timerRemaining.value = remaining
                _timerActive.value = active
                _timerLastTick.value = System.currentTimeMillis()
                if (!active) break
            }
        }
    }

    fun timerStart() {
        viewModelScope.launch {
            val result = engine.eval("android-timer-start")
            applyTimerState(result)
            _timerLastTick.value = System.currentTimeMillis()
            startTick()
        }
    }

    fun timerPause() {
        timerJob?.cancel()
        timerJob = null
        viewModelScope.launch {
            val result = engine.eval("android-timer-pause")
            applyTimerState(result)
        }
    }

    fun timerResume() {
        if (_timerLastTick.value == 0L) { timerStart(); return }
        viewModelScope.launch {
            val result = engine.eval("android-timer-resume")
            applyTimerState(result)
            _timerLastTick.value = System.currentTimeMillis()
            startTick()
        }
    }

    fun timerReset() {
        timerJob?.cancel()
        timerJob = null
        viewModelScope.launch {
            val result = engine.eval("android-timer-reset")
            applyTimerState(result)
            _timerLastTick.value = 0L
        }
    }

    // --- Stats ---

    suspend fun getDailyStats(): List<StatEntry> {
        val entry = _currentFile.value ?: return emptyList()
        val path = entry.path
        if (!_engineReady.value) return emptyList()
        return withContext(Dispatchers.Default) {
            engine.eval("android-get-stats {$path} ${_wordCount.value}")
                .lines()
                .filter { it.isNotBlank() }
                .mapNotNull { line ->
                    val parts = line.split("\t")
                    if (parts.size >= 2) StatEntry(parts[0], parts[1].toIntOrNull() ?: 0) else null
                }
        }
    }

    // --- Word occurrences ---

    suspend fun getWordOccurrences(): List<Pair<String, Int>> {
        if (!_engineReady.value) return emptyList()
        return withContext(Dispatchers.Default) {
            engine.setVar("::android_content", _content.value)
            engine.eval("android-word-occurrences \$::android_content")
                .lines()
                .filter { it.isNotBlank() }
                .mapNotNull { line ->
                    val tab = line.indexOf('\t')
                    if (tab < 0) null
                    else line.substring(0, tab) to (line.substring(tab + 1).toIntOrNull() ?: 0)
                }
        }
    }

    private fun countWords(text: String): Int =
        text.trim().split(Regex("\\s+")).count { it.isNotEmpty() }

    override fun onCleared() {
        timerJob?.cancel()
        engine.destroy()
    }

    private fun checkStoragePermission(): Boolean {
        val app = getApplication<Application>()
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Environment.isExternalStorageManager()
        } else {
            ContextCompat.checkSelfPermission(
                app, Manifest.permission.WRITE_EXTERNAL_STORAGE
            ) == PackageManager.PERMISSION_GRANTED
        }
    }
}
