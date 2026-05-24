package com.writhdeck.app.ui

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.writhdeck.app.DocEntry
import com.writhdeck.app.WrithdeckViewModel
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
fun BrowserScreen(
    vm: WrithdeckViewModel,
    onOpenFile: (DocEntry) -> Unit,
    onRequestPermission: () -> Unit
) {
    val docs by vm.docs.collectAsStateWithLifecycle()
    val recentDocs by vm.recentDocs.collectAsStateWithLifecycle()
    val favoriteDocs by vm.favoriteDocs.collectAsStateWithLifecycle()
    val storageGranted by vm.storagePermissionGranted.collectAsStateWithLifecycle()
    val engineReady by vm.engineReady.collectAsStateWithLifecycle()
    val snackbarMessage by vm.snackbarMessage.collectAsStateWithLifecycle()

    var showNewDialog by remember { mutableStateOf(false) }
    var newFileName by remember { mutableStateOf("") }

    var contextEntry by remember { mutableStateOf<DocEntry?>(null) }
    var showContextMenu by remember { mutableStateOf(false) }
    var showRenameDialog by remember { mutableStateOf(false) }
    var renameValue by remember { mutableStateOf("") }
    var showDeleteConfirm by remember { mutableStateOf(false) }
    var showInfoDialog by remember { mutableStateOf(false) }

    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(snackbarMessage) {
        val msg = snackbarMessage
        if (msg != null) {
            snackbarHostState.showSnackbar(msg)
            vm.dismissSnackbar()
        }
    }

    val favPaths by remember { derivedStateOf { favoriteDocs.map { it.path }.toSet() } }
    val recentOnly by remember {
        derivedStateOf {
            recentDocs.filter { r -> docs.none { d -> d.path == r.path } && r.path !in favPaths }
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("WrithDeck", fontFamily = FontFamily.Monospace) },
                actions = {
                    IconButton(onClick = { vm.openIniFile() }) {
                        Icon(Icons.Default.Settings, contentDescription = "Config")
                    }
                }
            )
        },
        floatingActionButton = {
            FloatingActionButton(onClick = { showNewDialog = true }) {
                Icon(Icons.Default.Add, contentDescription = "New")
            }
        },
        snackbarHost = { SnackbarHost(snackbarHostState) }
    ) { padding ->
        if (!engineReady) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }
        } else {
            LazyColumn(
                contentPadding = padding,
                modifier = Modifier.fillMaxSize()
            ) {
                // Storage permission banner
                if (!storageGranted) {
                    item {
                        Card(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 16.dp, vertical = 8.dp),
                            colors = CardDefaults.cardColors(
                                containerColor = MaterialTheme.colorScheme.secondaryContainer
                            )
                        ) {
                            Row(
                                modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Text(
                                    "Grant storage access to store files in Documents/WrithDeck/",
                                    modifier = Modifier.weight(1f),
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = MaterialTheme.colorScheme.onSecondaryContainer
                                )
                                Spacer(Modifier.width(8.dp))
                                TextButton(onClick = onRequestPermission) { Text("Grant") }
                            }
                        }
                    }
                }

                // Favorites section
                if (favoriteDocs.isNotEmpty()) {
                    item { SectionHeader("Favorites") }
                    items(favoriteDocs, key = { "fav_${it.path}" }) { entry ->
                        DocListItem(
                            entry = entry,
                            isFavorite = true,
                            onClick = { onOpenFile(entry) },
                            onLongClick = { contextEntry = entry; showContextMenu = true }
                        )
                    }
                }

                // Documents section
                item { SectionHeader("Documents") }
                if (docs.isEmpty()) {
                    item {
                        Box(
                            Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 16.dp, vertical = 12.dp),
                            contentAlignment = Alignment.CenterStart
                        ) {
                            Text(
                                "No documents yet. Tap + to create one.",
                                fontFamily = FontFamily.Monospace,
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                } else {
                    items(docs, key = { it.path }) { entry ->
                        DocListItem(
                            entry = entry,
                            isFavorite = entry.path in favPaths,
                            onClick = { onOpenFile(entry) },
                            onLongClick = { contextEntry = entry; showContextMenu = true }
                        )
                    }
                }

                // Recent section
                if (recentOnly.isNotEmpty()) {
                    item { SectionHeader("Recent") }
                    items(recentOnly, key = { "recent_${it.path}" }) { entry ->
                        DocListItem(
                            entry = entry,
                            isFavorite = false,
                            onClick = { onOpenFile(entry) },
                            onLongClick = { contextEntry = entry; showContextMenu = true }
                        )
                    }
                }

                item { Spacer(Modifier.height(80.dp)) }
            }
        }
    }

    // Context menu
    if (showContextMenu && contextEntry != null) {
        val entry = contextEntry!!
        val isFav = entry.path in favPaths
        AlertDialog(
            onDismissRequest = { showContextMenu = false },
            title = {
                Text(
                    entry.name,
                    fontFamily = FontFamily.Monospace,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            },
            text = {
                Column(modifier = Modifier.fillMaxWidth()) {
                    TextButton(
                        onClick = {
                            renameValue = entry.name.substringBeforeLast('.')
                            showContextMenu = false
                            showRenameDialog = true
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text("Rename", modifier = Modifier.fillMaxWidth(), textAlign = TextAlign.Start)
                    }
                    TextButton(
                        onClick = { showContextMenu = false; showDeleteConfirm = true },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(
                            "Delete",
                            modifier = Modifier.fillMaxWidth(),
                            textAlign = TextAlign.Start,
                            color = MaterialTheme.colorScheme.error
                        )
                    }
                    TextButton(
                        onClick = { vm.backupFile(entry); showContextMenu = false },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text("Backup", modifier = Modifier.fillMaxWidth(), textAlign = TextAlign.Start)
                    }
                    TextButton(
                        onClick = { vm.toggleFavorite(entry); showContextMenu = false },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(
                            if (isFav) "Remove from favorites" else "Add to favorites",
                            modifier = Modifier.fillMaxWidth(),
                            textAlign = TextAlign.Start
                        )
                    }
                    TextButton(
                        onClick = { showContextMenu = false; showInfoDialog = true },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text("Info", modifier = Modifier.fillMaxWidth(), textAlign = TextAlign.Start)
                    }
                }
            },
            confirmButton = {},
            dismissButton = {
                TextButton(onClick = { showContextMenu = false }) { Text("Cancel") }
            }
        )
    }

    // Info dialog
    if (showInfoDialog && contextEntry != null) {
        val entry = contextEntry!!
        val f = File(entry.path)
        val sizeStr = when {
            f.length() < 1024L -> "${f.length()} B"
            f.length() < 1024L * 1024 -> "${"%.1f".format(f.length() / 1024.0)} KB"
            else -> "${"%.1f".format(f.length() / (1024.0 * 1024))} MB"
        }
        val dateStr = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault())
            .format(Date(f.lastModified()))
        AlertDialog(
            onDismissRequest = { showInfoDialog = false },
            title = {
                Text(
                    entry.name,
                    fontFamily = FontFamily.Monospace,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("Path", style = MaterialTheme.typography.labelSmall,
                         color = MaterialTheme.colorScheme.primary)
                    Text(entry.path, fontFamily = FontFamily.Monospace,
                         style = MaterialTheme.typography.bodySmall)
                    HorizontalDivider()
                    Text("Size: $sizeStr", style = MaterialTheme.typography.bodyMedium)
                    Text("Modified: $dateStr", style = MaterialTheme.typography.bodyMedium)
                }
            },
            confirmButton = {},
            dismissButton = {
                TextButton(onClick = { showInfoDialog = false }) { Text("Close") }
            }
        )
    }

    // Rename dialog
    if (showRenameDialog && contextEntry != null) {
        AlertDialog(
            onDismissRequest = { showRenameDialog = false },
            title = { Text("Rename") },
            text = {
                OutlinedTextField(
                    value = renameValue,
                    onValueChange = { renameValue = it },
                    label = { Text("New name") },
                    singleLine = true,
                    textStyle = LocalTextStyle.current.copy(fontFamily = FontFamily.Monospace)
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    if (renameValue.isNotBlank()) vm.renameFile(contextEntry!!, renameValue)
                    showRenameDialog = false; contextEntry = null
                }) { Text("Rename") }
            },
            dismissButton = {
                TextButton(onClick = { showRenameDialog = false }) { Text("Cancel") }
            }
        )
    }

    // Delete confirmation
    if (showDeleteConfirm && contextEntry != null) {
        AlertDialog(
            onDismissRequest = { showDeleteConfirm = false },
            title = { Text("Delete") },
            text = { Text("Delete \"${contextEntry!!.name}\"? This cannot be undone.") },
            confirmButton = {
                TextButton(
                    onClick = {
                        vm.deleteFile(contextEntry!!)
                        showDeleteConfirm = false
                        contextEntry = null
                    },
                    colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error)
                ) { Text("Delete") }
            },
            dismissButton = {
                TextButton(onClick = { showDeleteConfirm = false }) { Text("Cancel") }
            }
        )
    }

    // New file dialog
    if (showNewDialog) {
        AlertDialog(
            onDismissRequest = { showNewDialog = false; newFileName = "" },
            title = { Text("New document") },
            text = {
                OutlinedTextField(
                    value = newFileName,
                    onValueChange = { newFileName = it },
                    label = { Text("File name") },
                    singleLine = true,
                    textStyle = LocalTextStyle.current.copy(fontFamily = FontFamily.Monospace)
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    if (newFileName.isNotBlank()) vm.createFile(newFileName)
                    showNewDialog = false; newFileName = ""
                }) { Text("Create") }
            },
            dismissButton = {
                TextButton(onClick = { showNewDialog = false; newFileName = "" }) {
                    Text("Cancel")
                }
            }
        )
    }
}

@Composable
private fun SectionHeader(title: String) {
    Text(
        text = title.uppercase(),
        style = MaterialTheme.typography.labelSmall,
        fontWeight = FontWeight.Bold,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 16.dp, bottom = 4.dp)
    )
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun DocListItem(
    entry: DocEntry,
    isFavorite: Boolean,
    onClick: () -> Unit,
    onLongClick: () -> Unit
) {
    ListItem(
        headlineContent = { Text(entry.name, fontFamily = FontFamily.Monospace) },
        trailingContent = if (isFavorite) {
            {
                Icon(
                    Icons.Default.Star,
                    contentDescription = "Favorite",
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(18.dp)
                )
            }
        } else null,
        modifier = Modifier.combinedClickable(
            onClick = onClick,
            onLongClick = onLongClick
        )
    )
    HorizontalDivider()
}
