package com.writhdeck.app.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.writhdeck.app.DocEntry
import com.writhdeck.app.WrithdeckViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BrowserScreen(vm: WrithdeckViewModel, onOpenFile: (DocEntry) -> Unit) {
    val docs by vm.docs.collectAsStateWithLifecycle()
    val engineReady by vm.engineReady.collectAsStateWithLifecycle()
    var showNewDialog by remember { mutableStateOf(false) }
    var newFileName by remember { mutableStateOf("") }

    Scaffold(
        topBar = {
            TopAppBar(title = { Text("WrithDeck", fontFamily = FontFamily.Monospace) })
        },
        floatingActionButton = {
            FloatingActionButton(onClick = { showNewDialog = true }) {
                Icon(Icons.Default.Add, contentDescription = "New")
            }
        }
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
                if (docs.isEmpty()) {
                    item {
                        Box(
                            Modifier.fillMaxWidth().padding(32.dp),
                            contentAlignment = Alignment.Center
                        ) {
                            Text(
                                "No documents yet. Tap + to create one.",
                                fontFamily = FontFamily.Monospace,
                                style = MaterialTheme.typography.bodyMedium
                            )
                        }
                    }
                }
                items(docs, key = { it.path }) { entry ->
                    ListItem(
                        headlineContent = {
                            Text(entry.name, fontFamily = FontFamily.Monospace)
                        },
                        modifier = Modifier.clickable { onOpenFile(entry) }
                    )
                    HorizontalDivider()
                }
            }
        }
    }

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
                    if (newFileName.isNotBlank()) {
                        vm.createFile(newFileName)
                    }
                    showNewDialog = false
                    newFileName = ""
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
