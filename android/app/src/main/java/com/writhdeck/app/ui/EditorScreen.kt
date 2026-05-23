package com.writhdeck.app.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.List
import androidx.compose.material.icons.filled.Menu
import androidx.compose.material.icons.filled.Save
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.input.key.*
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.writhdeck.app.StatEntry
import com.writhdeck.app.WrithdeckViewModel
import kotlinx.coroutines.launch

fun tkKeyToAndroid(tkName: String): Key? = when (tkName.trim()) {
    "F1"  -> Key.F1;  "F2"  -> Key.F2;  "F3"  -> Key.F3;  "F4"  -> Key.F4
    "F5"  -> Key.F5;  "F6"  -> Key.F6;  "F7"  -> Key.F7;  "F8"  -> Key.F8
    "F9"  -> Key.F9;  "F10" -> Key.F10; "F11" -> Key.F11; "F12" -> Key.F12
    "Escape"    -> Key.Escape
    "Return"    -> Key.Enter
    "Tab"       -> Key.Tab
    "BackSpace" -> Key.Backspace
    "Delete"    -> Key.Delete
    "Home"      -> Key.MoveHome
    "End"       -> Key.MoveEnd
    "Prior"     -> Key.PageUp
    "Next"      -> Key.PageDown
    else -> null
}

fun formatTimer(seconds: Int, active: Boolean, lastTick: Long, type: String): String {
    val secs = if (type == "stopwatch") seconds
               else if (active || lastTick != 0L) seconds
               else seconds
    val m = secs / 60
    val s = secs % 60
    val display = "$m'${s.toString().padStart(2, '0')}\""
    return if (active) "[$display]" else " $display"
}

data class TocEntry(val level: Int, val title: String, val charOffset: Int)

fun buildToc(text: String, headingMarker: String, markdownHeadings: Boolean): List<TocEntry> {
    val entries = mutableListOf<TocEntry>()
    val mLen = headingMarker.length
    val mdRe = if (markdownHeadings) Regex("^(#{1,6})\\s+(.+)$") else null

    var offset = 0
    for (line in text.lines()) {
        val trimmed = line.trim()
        var added = false

        if (mLen > 0 && trimmed.startsWith(headingMarker) && trimmed.endsWith(headingMarker)) {
            // Count leading markers
            var level = 0
            var pos = 0
            while (pos + mLen <= trimmed.length &&
                   trimmed.substring(pos, pos + mLen) == headingMarker) {
                level++; pos += mLen
            }
            // Strip trailing markers
            var end = trimmed.length
            while (end >= mLen &&
                   trimmed.substring(end - mLen, end) == headingMarker) {
                end -= mLen
            }
            val title = trimmed.substring(pos, end).trim()
            if (level > 0 && title.isNotEmpty()) {
                entries.add(TocEntry(level, title, offset))
                added = true
            }
        }

        if (!added && mdRe != null) {
            val m = mdRe.find(trimmed)
            if (m != null)
                entries.add(TocEntry(m.groupValues[1].length, m.groupValues[2].trim(), offset))
        }
        offset += line.length + 1
    }
    return entries
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EditorScreen(vm: WrithdeckViewModel, onBack: () -> Unit) {
    val content by vm.content.collectAsStateWithLifecycle()
    val wordCount by vm.wordCount.collectAsStateWithLifecycle()
    val currentFile by vm.currentFile.collectAsStateWithLifecycle()
    val dirty by vm.dirty.collectAsStateWithLifecycle()
    val headingMarker by vm.headingMarker.collectAsStateWithLifecycle()
    val markdownHeadings by vm.markdownHeadings.collectAsStateWithLifecycle()
    val keyToc by vm.keyToc.collectAsStateWithLifecycle()
    val tocAndroidKey = remember(keyToc) { tkKeyToAndroid(keyToc) }

    // Timer
    val timerActive by vm.timerActive.collectAsStateWithLifecycle()
    val timerRemaining by vm.timerRemaining.collectAsStateWithLifecycle()
    val timerLastTick by vm.timerLastTick.collectAsStateWithLifecycle()
    val timerType by vm.timerType.collectAsStateWithLifecycle()

    val colorScheme = MaterialTheme.colorScheme
    val scope = rememberCoroutineScope()

    var tfv by remember { mutableStateOf(TextFieldValue(content)) }
    LaunchedEffect(content) {
        if (content != tfv.text) tfv = TextFieldValue(content)
    }

    var showToc by remember { mutableStateOf(false) }
    val toc = remember(content, headingMarker, markdownHeadings) {
        buildToc(content, headingMarker, markdownHeadings)
    }

    // Overlays
    var showCmdMode by remember { mutableStateOf(false) }
    var showStats by remember { mutableStateOf(false) }
    var showWords by remember { mutableStateOf(false) }
    var statsData by remember { mutableStateOf<List<StatEntry>>(emptyList()) }
    var wordsData by remember { mutableStateOf<List<Pair<String, Int>>>(emptyList()) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        text = buildString {
                            append(currentFile?.name ?: "Editor")
                            if (dirty) append(" *")
                        },
                        fontFamily = FontFamily.Monospace,
                        maxLines = 1
                    )
                },
                navigationIcon = {
                    IconButton(onClick = {
                        if (dirty) vm.saveFile()
                        onBack()
                    }) {
                        @Suppress("DEPRECATION")
                        Icon(Icons.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    if (toc.isNotEmpty()) {
                        IconButton(onClick = { showToc = true }) {
                            Icon(Icons.Filled.List, contentDescription = "TOC")
                        }
                    }
                    IconButton(onClick = { showCmdMode = true }) {
                        Icon(Icons.Filled.Menu, contentDescription = "Commands")
                    }
                    IconButton(onClick = { vm.saveFile() }, enabled = dirty) {
                        Icon(Icons.Filled.Save, contentDescription = "Save")
                    }
                }
            )
        },
        bottomBar = {
            Surface(tonalElevation = 2.dp) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 8.dp)
                        .navigationBarsPadding(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = "$wordCount words",
                        fontFamily = FontFamily.Monospace,
                        style = MaterialTheme.typography.bodySmall,
                        color = colorScheme.onSurfaceVariant
                    )
                    if (timerActive || timerLastTick != 0L) {
                        Text(
                            text = formatTimer(timerRemaining, timerActive, timerLastTick, timerType),
                            fontFamily = FontFamily.Monospace,
                            style = MaterialTheme.typography.bodySmall,
                            color = if (timerActive) colorScheme.primary else colorScheme.onSurfaceVariant,
                            modifier = Modifier.clickable { showCmdMode = true }
                        )
                    }
                }
            }
        }
    ) { padding ->
        BasicTextField(
            value = tfv,
            onValueChange = { new ->
                tfv = new
                if (new.text != content) vm.updateContent(new.text)
            },
            textStyle = TextStyle(
                fontFamily = FontFamily.Monospace,
                fontSize = 16.sp,
                lineHeight = 24.sp,
                color = colorScheme.onSurface
            ),
            cursorBrush = SolidColor(colorScheme.primary),
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(horizontal = 20.dp, vertical = 12.dp)
                .imePadding()
                .onKeyEvent { event ->
                    if (event.type != KeyEventType.KeyDown) return@onKeyEvent false
                    when {
                        tocAndroidKey != null && event.key == tocAndroidKey && toc.isNotEmpty() -> {
                            showToc = true; true
                        }
                        event.key == Key.Escape -> {
                            showCmdMode = true; true
                        }
                        else -> false
                    }
                }
        )
    }

    // TOC sheet
    if (showToc) {
        ModalBottomSheet(onDismissRequest = { showToc = false }) {
            Text(
                text = "Table of contents",
                style = MaterialTheme.typography.titleMedium,
                modifier = Modifier.padding(start = 20.dp, end = 20.dp, bottom = 8.dp)
            )
            LazyColumn(contentPadding = PaddingValues(bottom = 32.dp)) {
                itemsIndexed(toc) { _, entry ->
                    val indent = (entry.level - 1) * 16
                    Text(
                        text = entry.title,
                        fontFamily = FontFamily.Monospace,
                        fontWeight = if (entry.level == 1) FontWeight.Bold else FontWeight.Normal,
                        fontSize = when (entry.level) { 1 -> 16.sp; 2 -> 15.sp; else -> 14.sp },
                        color = if (entry.level == 1) colorScheme.primary else colorScheme.onSurface,
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable {
                                val pos = entry.charOffset.coerceIn(0, tfv.text.length)
                                tfv = tfv.copy(selection = TextRange(pos))
                                showToc = false
                            }
                            .padding(start = (20 + indent).dp, end = 20.dp, top = 10.dp, bottom = 10.dp)
                    )
                    HorizontalDivider(modifier = Modifier.padding(horizontal = 20.dp))
                }
            }
        }
    }

    // Command mode sheet
    if (showCmdMode) {
        ModalBottomSheet(onDismissRequest = { showCmdMode = false }) {
            Text(
                text = "Commands",
                style = MaterialTheme.typography.titleMedium,
                modifier = Modifier.padding(start = 20.dp, end = 20.dp, bottom = 16.dp)
            )

            // Timer section
            Surface(
                tonalElevation = 2.dp,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp)
            ) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween,
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(
                            text = formatTimer(timerRemaining, timerActive, timerLastTick, timerType)
                                .trim(),
                            fontFamily = FontFamily.Monospace,
                            style = MaterialTheme.typography.titleLarge,
                            color = if (timerActive) colorScheme.primary else colorScheme.onSurface
                        )
                        Row {
                            if (!timerActive && timerLastTick == 0L) {
                                // Fresh — show Start
                                Button(onClick = { vm.timerStart() }) { Text("Start") }
                            } else if (timerActive) {
                                // Running — show Pause
                                Button(onClick = { vm.timerPause() }) { Text("Pause") }
                            } else {
                                // Paused — show Resume
                                Button(onClick = { vm.timerResume() }) { Text("Resume") }
                                Spacer(Modifier.width(8.dp))
                                OutlinedButton(onClick = { vm.timerReset() }) { Text("Reset") }
                            }
                            if (timerActive) {
                                Spacer(Modifier.width(8.dp))
                                OutlinedButton(onClick = { vm.timerReset() }) { Text("Reset") }
                            }
                        }
                    }
                }
            }

            Spacer(Modifier.height(12.dp))

            // Action buttons row 1
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                OutlinedButton(
                    onClick = {
                        showCmdMode = false
                        scope.launch {
                            statsData = vm.getDailyStats()
                            showStats = true
                        }
                    },
                    modifier = Modifier.weight(1f)
                ) { Text("Stats") }
                OutlinedButton(
                    onClick = {
                        showCmdMode = false
                        scope.launch {
                            wordsData = vm.getWordOccurrences()
                            showWords = true
                        }
                    },
                    modifier = Modifier.weight(1f)
                ) { Text("Words") }
            }

            Spacer(Modifier.height(8.dp))

            // Action buttons row 2
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                OutlinedButton(
                    onClick = { showCmdMode = false; showToc = true },
                    enabled = toc.isNotEmpty(),
                    modifier = Modifier.weight(1f)
                ) { Text("TOC") }
            }

            Spacer(Modifier.height(24.dp))
        }
    }

    // Stats dialog
    if (showStats) {
        AlertDialog(
            onDismissRequest = { showStats = false },
            title = { Text("Writing stats", fontFamily = FontFamily.Monospace) },
            text = {
                if (statsData.isEmpty()) {
                    Text("No stats yet.", fontFamily = FontFamily.Monospace,
                         color = colorScheme.onSurfaceVariant)
                } else {
                    LazyColumn {
                        itemsIndexed(statsData) { _, entry ->
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(vertical = 6.dp),
                                horizontalArrangement = Arrangement.SpaceBetween
                            ) {
                                Text(entry.date, fontFamily = FontFamily.Monospace,
                                     style = MaterialTheme.typography.bodyMedium)
                                Text("${entry.words} w", fontFamily = FontFamily.Monospace,
                                     style = MaterialTheme.typography.bodyMedium,
                                     color = colorScheme.primary)
                            }
                            HorizontalDivider()
                        }
                    }
                }
            },
            confirmButton = {
                TextButton(onClick = { showStats = false }) { Text("Close") }
            }
        )
    }

    // Word occurrences dialog
    if (showWords) {
        AlertDialog(
            onDismissRequest = { showWords = false },
            title = { Text("Word frequency", fontFamily = FontFamily.Monospace) },
            text = {
                if (wordsData.isEmpty()) {
                    Text("No words found.", fontFamily = FontFamily.Monospace,
                         color = colorScheme.onSurfaceVariant)
                } else {
                    LazyColumn(modifier = Modifier.heightIn(max = 400.dp)) {
                        itemsIndexed(wordsData) { idx, (word, count) ->
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(vertical = 5.dp),
                                horizontalArrangement = Arrangement.SpaceBetween
                            ) {
                                Text(
                                    text = "${idx + 1}. $word",
                                    fontFamily = FontFamily.Monospace,
                                    style = MaterialTheme.typography.bodyMedium
                                )
                                Text(
                                    text = "$count",
                                    fontFamily = FontFamily.Monospace,
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = colorScheme.primary
                                )
                            }
                            if (idx < wordsData.lastIndex)
                                HorizontalDivider()
                        }
                    }
                }
            },
            confirmButton = {
                TextButton(onClick = { showWords = false }) { Text("Close") }
            }
        )
    }
}
