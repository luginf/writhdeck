# boot-android.tcl — démarrage de l'interpréteur WrithDeck sur Android
# ::ANDROID_FILES_DIR est injecté par nativeInit() avant que ce script soit sourcé

set ::HOME_DIR          $::ANDROID_FILES_DIR
set ::DOCS_DIR_DEFAULT  [file join $::ANDROID_FILES_DIR "documents"]
set ::DOCS_DIR          $::DOCS_DIR_DEFAULT
set ::no_gui            1
set ::cfg_lang          "en"

proc tilde-expand {path} { return $path }

# Source order mirrors the generated writhdeck.tcl order
foreach _mod {state config} {
    set _f [file join $::ANDROID_FILES_DIR "tcl" "${_mod}.tcl"]
    if {[file exists $_f]} {
        source $_f
    } else {
        error "boot-android: module not found: $_f"
    }
}
unset _mod _f

# Kick off state loading now that all procs are defined
state-load
