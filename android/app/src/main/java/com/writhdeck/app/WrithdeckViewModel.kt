package com.writhdeck.app

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

data class DocEntry(val name: String, val path: String)

class WrithdeckViewModel(app: Application) : AndroidViewModel(app) {

    private val engine = WrithdeckEngine(app)
    private val docsDir get() = File(getApplication<Application>().filesDir, "documents")

    private val _engineReady = MutableStateFlow(false)
    val engineReady = _engineReady.asStateFlow()

    private val _docs = MutableStateFlow<List<DocEntry>>(emptyList())
    val docs = _docs.asStateFlow()

    private val _content = MutableStateFlow("")
    val content = _content.asStateFlow()

    private val _wordCount = MutableStateFlow(0)
    val wordCount = _wordCount.asStateFlow()

    private val _currentFile = MutableStateFlow<DocEntry?>(null)
    val currentFile = _currentFile.asStateFlow()

    private val _dirty = MutableStateFlow(false)
    val dirty = _dirty.asStateFlow()

    init {
        viewModelScope.launch {
            engine.init() // best-effort — file operations work regardless
            _engineReady.value = true
            refreshDocs()
        }
    }

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
            }
        }
    }

    fun updateContent(text: String) {
        _content.value = text
        _dirty.value = true
        _wordCount.value = countWords(text)
    }

    fun saveFile() {
        val entry = _currentFile.value ?: return
        viewModelScope.launch {
            withContext(Dispatchers.IO) { File(entry.path).writeText(_content.value) }
            _dirty.value = false
            if (_engineReady.value) {
                engine.eval("state-save")
            }
        }
    }

    fun createFile(name: String) {
        viewModelScope.launch(Dispatchers.IO) {
            docsDir.mkdirs()
            val safeName = if (name.endsWith(".txt") || name.endsWith(".md")) name else "$name.txt"
            File(docsDir, safeName).createNewFile()
            refreshDocs()
        }
    }

    private fun countWords(text: String): Int =
        text.trim().split(Regex("\\s+")).count { it.isNotEmpty() }

    override fun onCleared() {
        engine.destroy()
    }
}
