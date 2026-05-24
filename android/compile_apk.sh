#  Compilation sans Android Studio :
#  cd android/
#  ./gradlew assembleDebug          # compile → app/build/outputs/apk/debug/writhdeck-debug.apk
#  ./gradlew installDebug           # compile + installe via adb (appareil connecté)
#  ./gradlew assembleDebug --daemon # daemon Gradle = relances plus rapides (~5s au lieu de 50s)



./gradlew assembleDebug 

printf "app/build/outputs/apk/debug/writhdeck-debug.apk" 