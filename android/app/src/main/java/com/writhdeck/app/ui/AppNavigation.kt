package com.writhdeck.app.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.writhdeck.app.DocEntry
import com.writhdeck.app.WrithdeckViewModel
import java.net.URLEncoder

@Composable
fun AppNavigation(vm: WrithdeckViewModel = viewModel()) {
    val nav = rememberNavController()
    val currentFile by vm.currentFile.collectAsStateWithLifecycle()

    // If MainActivity already loaded an external file, go straight to the editor
    LaunchedEffect(currentFile) {
        if (currentFile != null && nav.currentDestination?.route == "browser") {
            nav.navigate("editor") { launchSingleTop = true }
        }
    }

    NavHost(navController = nav, startDestination = "browser") {
        composable("browser") {
            BrowserScreen(
                vm = vm,
                onOpenFile = { entry ->
                    vm.openFile(entry)
                    nav.navigate("editor") { launchSingleTop = true }
                }
            )
        }
        composable("editor") {
            EditorScreen(vm = vm, onBack = {
                vm.clearExternalFile()
                nav.popBackStack()
            })
        }
    }
}
