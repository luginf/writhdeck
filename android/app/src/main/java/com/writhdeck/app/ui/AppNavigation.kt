package com.writhdeck.app.ui

import androidx.compose.runtime.Composable
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.writhdeck.app.WrithdeckViewModel
import java.net.URLDecoder
import java.net.URLEncoder

@Composable
fun AppNavigation(vm: WrithdeckViewModel = viewModel()) {
    val nav = rememberNavController()

    NavHost(navController = nav, startDestination = "browser") {
        composable("browser") {
            BrowserScreen(
                vm = vm,
                onOpenFile = { entry ->
                    vm.openFile(entry)
                    val encoded = URLEncoder.encode(entry.path, "UTF-8")
                    nav.navigate("editor/$encoded")
                }
            )
        }
        composable("editor/{path}") {
            EditorScreen(vm = vm, onBack = { nav.popBackStack() })
        }
    }
}
