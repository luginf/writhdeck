#include <jni.h>
#include <tcl.h>
#include <string.h>
#include <stdlib.h>
#include <android/log.h>

#define LOG_TAG "WrithdeckJNI"
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO,  LOG_TAG, __VA_ARGS__)

static Tcl_Interp *interp = NULL;

JNIEXPORT jboolean JNICALL
Java_com_writhdeck_app_WrithdeckEngine_nativeInit(
    JNIEnv *env, jobject thiz, jstring filesDir)
{
    if (interp) {
        Tcl_DeleteInterp(interp);
        interp = NULL;
    }
    Tcl_FindExecutable(NULL);
    interp = Tcl_CreateInterp();
    if (!interp) { LOGE("Tcl_CreateInterp failed"); return JNI_FALSE; }
    if (Tcl_Init(interp) != TCL_OK) {
        LOGE("Tcl_Init: %s", Tcl_GetStringResult(interp));
        Tcl_DeleteInterp(interp); interp = NULL;
        return JNI_FALSE;
    }
    const char *dir = (*env)->GetStringUTFChars(env, filesDir, NULL);

    /* Point tcl_library to the stdlib files we copy from assets.
       Must be set BEFORE Tcl_Init() so init.tcl / clock.tcl are found. */
    char lib_path[1024];
    snprintf(lib_path, sizeof(lib_path), "%s/tcl/lib/tcl8.6", dir);
    Tcl_SetVar(interp, "tcl_library", lib_path, TCL_GLOBAL_ONLY);

    if (Tcl_Init(interp) != TCL_OK) {
        /* Log but continue — basic built-in commands still work */
        LOGE("Tcl_Init: %s", Tcl_GetStringResult(interp));
    }

    Tcl_SetVar(interp, "::ANDROID_FILES_DIR", dir, TCL_GLOBAL_ONLY);
    LOGI("Tcl interp ready, filesDir=%s, lib=%s", dir, lib_path);
    (*env)->ReleaseStringUTFChars(env, filesDir, dir);
    return JNI_TRUE;
}

JNIEXPORT jstring JNICALL
Java_com_writhdeck_app_WrithdeckEngine_nativeEval(
    JNIEnv *env, jobject thiz, jstring script)
{
    if (!interp) return (*env)->NewStringUTF(env, "ERROR: interp not initialized");
    const char *s = (*env)->GetStringUTFChars(env, script, NULL);
    int rc = Tcl_Eval(interp, s);
    (*env)->ReleaseStringUTFChars(env, script, s);
    const char *result = Tcl_GetStringResult(interp);
    if (rc != TCL_OK) LOGE("Tcl error: %s", result);
    return (*env)->NewStringUTF(env, result ? result : "");
}

JNIEXPORT jstring JNICALL
Java_com_writhdeck_app_WrithdeckEngine_nativeGetVar(
    JNIEnv *env, jobject thiz, jstring varName)
{
    if (!interp) return (*env)->NewStringUTF(env, "");
    const char *name = (*env)->GetStringUTFChars(env, varName, NULL);
    const char *val  = Tcl_GetVar(interp, name, TCL_GLOBAL_ONLY);
    (*env)->ReleaseStringUTFChars(env, varName, name);
    return (*env)->NewStringUTF(env, val ? val : "");
}

JNIEXPORT void JNICALL
Java_com_writhdeck_app_WrithdeckEngine_nativeSetVar(
    JNIEnv *env, jobject thiz, jstring varName, jstring value)
{
    if (!interp) return;
    const char *name = (*env)->GetStringUTFChars(env, varName, NULL);
    const char *val  = (*env)->GetStringUTFChars(env, value,   NULL);
    Tcl_SetVar(interp, name, val, TCL_GLOBAL_ONLY);
    (*env)->ReleaseStringUTFChars(env, varName, name);
    (*env)->ReleaseStringUTFChars(env, value,   val);
}

JNIEXPORT void JNICALL
Java_com_writhdeck_app_WrithdeckEngine_nativeDestroy(
    JNIEnv *env, jobject thiz)
{
    if (interp) { Tcl_DeleteInterp(interp); interp = NULL; }
}
