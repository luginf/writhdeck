plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

// Copy Tcl engine modules from the parent src/ directory into assets at build time.
// boot-android.tcl stays in assets/tcl/ and is committed; state.tcl + config.tcl
// are generated from the parent source tree so they stay in sync automatically.
val copyTclModules = tasks.register<Copy>("copyTclModules") {
    // WrithDeck engine modules from parent src/
    from("${rootProject.rootDir.parent}/src") {
        include("state.tcl", "config.tcl")
    }
    // Tcl stdlib — Tcl_Init() needs init.tcl / clock.tcl at runtime on Android.
    // Source: tcl8.6.15/library/ (created by build-tcl-android.sh download step).
    from("${rootProject.rootDir}/tcl8.6.15/library") {
        include("init.tcl", "auto.tcl", "clock.tcl", "tclIndex",
                "package.tcl", "word.tcl", "safe.tcl", "parray.tcl", "history.tcl")
        into("lib/tcl8.6")
    }
    into("src/main/assets/tcl")
}
tasks.named("preBuild") { dependsOn(copyTclModules) }

android {
    namespace = "com.writhdeck.app"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.writhdeck.app"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "1.0"

        externalNativeBuild {
            cmake { arguments("-DANDROID_STL=none") }
        }
        ndk {
            // Phase 1: arm64-v8a (device) + x86_64 (emulator)
            abiFilters += listOf("arm64-v8a", "x86_64")
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions { jvmTarget = "17" }

    buildFeatures { compose = true }

    externalNativeBuild {
        cmake { path("src/main/cpp/CMakeLists.txt") }
    }
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2024.09.03")
    implementation(composeBom)

    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.5")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.5")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.5")
    implementation("androidx.activity:activity-compose:1.9.2")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.navigation:navigation-compose:2.8.1")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")

    debugImplementation("androidx.compose.ui:ui-tooling")
    debugImplementation("androidx.compose.ui:ui-test-manifest")
}
