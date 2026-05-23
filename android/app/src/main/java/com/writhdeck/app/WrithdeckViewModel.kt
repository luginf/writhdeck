package com.writhdeck.app

import android.app.Application
import android.content.ContentResolver
import android.net.Uri
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

class WrithdeckViewModel(app: Application) : AndroidViewModel(app) {

    private val engine = WrithdeckEngine(app)
    private val docsDir get() = File(getApplication<Application>().filesDir, "documents")

    private val _engineReady = MutableStateFlow(false)
    val engineReady = _engineReady.asStateFlow()

    private val _docs = MutableStateFlow<List<DocEntry>>(emptyList())
    val docs = _docs.asStateFlow()

    private val _recentDocs = MutableStateFlow<List<DocEntry>>(emptyList())
    val recentDocs = _recentDocs.asStateFlow()

    private val _content = MutableStateFlow("")
    val content = _content.asStateFlow()

    private val _wordCount = MutableStateFlow(0)
    val wordCount = _wordCount.asStateFlow()

    private val _currentFile = MutableStateFlow<DocEntry?>(null)
    val currentFile = _currentFile.asStateFlow()

    private val _dirty = MutableStateFlow(false)
    val dirty = _dirty.asStateFlow()

    // Heading / key config (lus depuis le moteur Tcl après ini-load)
    private val _headingMarker = MutableStateFlow("=")
    val headingMarker = _headingMarker.asStateFlow()
    private val _markdownHeadings = MutableStateFlow(true)
    val markdownHeadings = _markdownHeadings.asStateFlow()
    private val _keyToc = MutableStateFlow("F11")
    val keyToc = _keyToc.asStateFlow()

    // Timer — état piloté par le moteur Tcl, tick déclenché par coroutine Kotlin
    private val _timerType = MutableStateFlow("countdown")
    val timerType = _timerType.asStateFlow()
    private val _timerActive = MutableStateFlow(false)
    val timerActive = _timerActive.asStateFlow()
    private val _timerRemaining = MutableStateFlow(0)
    val timerRemaining = _timerRemaining.asStateFlow()
    // 0L = jamais démarré / réinitialisé ; non-nul = en cours ou en pause
    private val _timerLastTick = MutableStateFlow(0L)
    val timerLastTick = _timerLastTick.asStateFlow()

    private var timerJob: Job? = null

    // Non-null when a file was opened via ACTION_VIEW / ACTION_EDIT from another app
    private var externalUri: Uri? = null
    private var externalWritable = false

    init {
        viewModelScope.launch {
            engine.init()
            _engineReady.value = true
            _headingMarker.value = engine.eval("set ::cfg_heading_marker").trim().ifEmpty { "=" }
            _markdownHeadings.value = engine.eval("set ::cfg_markdown_headings").trim() != "0"
            _keyToc.value = engine.eval("set ::cfg_key_toc").trim().ifEmpty { "F11" }
            _timerType.value = engine.eval("set ::cfg_timer_type").trim().ifEmpty { "countdown" }
            // Lit l'état initial du timer depuis Tcl (après ini-load dans boot-android.tcl)
            applyTimerState(engine.eval("android-timer-state"), resetLastTick = true)
            refreshDocs()
            refreshRecents()
        }
    }

    // --- Docs ---

    fun refreshDocs() {
        viewModelScope.launch(Dispatchers.IO) {
            docsDir.mkdirs()
            val files = docsDir
                .listFiles { f -> f.isFile && (f.extension == "txt" || f.extension == "md") }
                ?.sortedByDescending { it.lastModified() }
                ?.map { DocEntry(it.name, it.absolutePath) }
                ?: emptyList()
            _docs.value = files
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
            // Toujours régénérer pour avoir les valeurs courantes (pas un fichier vide ou obsolète)
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
    }

    // --- Timer (état géré par le moteur Tcl, tick piloté par coroutine) ---

    private fun applyTimerState(result: String, resetLastTick: Boolean = false) {
        val parts = result.trim().split(" ")
        val active = parts.getOrNull(0) == "1"
        val remaining = parts.getOrNull(1)?.toIntOrNull() ?: 0
        val tclTick = parts.getOrNull(2)?.toLongOrNull() ?: 0L
        _timerActive.value = active
        _timerRemaining.value = remaining
        if (resetLastTick) {
            // 0 dans Tcl = jamais démarré
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
            // lastTick non-nul → affiche le timer en pause dans la barre
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
            _timerLastTick.value = 0L  // réinitialise → masque le timer dans la barre
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

    // --- Occurrences de mots (via moteur Tcl) ---

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

    // --- Comptage de mots (Kotlin, sur contenu en mémoire) ---

    private fun countWords(text: String): Int =
        text.trim().split(Regex("\\s+")).count { it.isNotEmpty() }

    override fun onCleared() {
        timerJob?.cancel()
        engine.destroy()
    }
}
