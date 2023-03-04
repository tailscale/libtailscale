#include <jni.h>
#include <stdlib.h>

extern char* RunTestControl();

JNIEXPORT jstring JNICALL
Java_com_tailscale_TailscaleTest_run(JNIEnv* env, jclass clazz) {
	char* addr = RunTestControl();
	jstring res = (*env)->NewStringUTF(env, addr);
	free((void*)addr);
	return res;
}
