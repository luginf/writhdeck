cmake_minimum_required(VERSION 3.22)
project(writhdeck)

# libtcl8.6.a must be pre-built per ABI via tools/build-tcl-android.sh
# Run from android/: ./tools/build-tcl-android.sh arm64-v8a
#                    ./tools/build-tcl-android.sh x86_64
set(TCL_ABI_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../../../tcl-android/${ANDROID_ABI}/install")

add_library(writhdeck SHARED writhdeck_jni.c)

target_include_directories(writhdeck PRIVATE
    ${TCL_ABI_DIR}/include
)

target_link_libraries(writhdeck
    ${TCL_ABI_DIR}/lib/libtcl8.6.a
    android log m z
)
