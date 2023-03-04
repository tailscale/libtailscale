#include <jni.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include "../tailscale.h"

JNIEXPORT jint JNICALL
Java_com_tailscale_Tailscale_tailscaleNew(JNIEnv* env, jclass clazz) {
	return (jint)tailscale_new();
}

JNIEXPORT jint JNICALL
Java_com_tailscale_Tailscale_up(JNIEnv* env, jclass clazz, jint sd) {
	return tailscale_up(sd);
}

JNIEXPORT jint JNICALL
Java_com_tailscale_Tailscale_close(JNIEnv* env, jclass clazz, jint sd) {
	return tailscale_close(sd);
}

JNIEXPORT jint JNICALL
Java_com_tailscale_Tailscale_disableLog(JNIEnv* env, jclass clazz, jint sd) {
	return tailscale_set_logfd(sd, -1);
}

// jstringdup makes a NUL-terminated copy of jstr.
static const char* jstringdup(JNIEnv* env, jstring jstr) {
	char* dst;
	if (jstr == NULL) {
		dst = calloc(1, 1);
		return dst;
	}
	jsize len = (*env)->GetStringUTFLength(env, jstr);
	dst = calloc(len+1, 1);
	const char* src = (*env)->GetStringUTFChars(env, jstr, NULL);
	strncpy(dst, src, len);
	(*env)->ReleaseStringUTFChars(env, jstr, src);
	return dst;
}

// callstr calls fn with sd and a NUL-terminated copy of jstr.
static int callstr(JNIEnv* env, int sd, jstring jstr, int (*fn)(int, const char*)) {
	const char* str = jstringdup(env, jstr);
	int ret = fn(sd, str);
	free((void*)str);
	return ret;
}

JNIEXPORT jint JNICALL
Java_com_tailscale_Tailscale_setDir(JNIEnv* env, jclass clazz, jint sd, jstring jdir) {
	return callstr(env, sd, jdir, tailscale_set_dir);
}

JNIEXPORT jint JNICALL
Java_com_tailscale_Tailscale_setHostname(JNIEnv* env, jclass clazz, jint sd, jstring jstr) {
	return callstr(env, sd, jstr, tailscale_set_hostname);
}

JNIEXPORT jint JNICALL
Java_com_tailscale_Tailscale_setAuthkey(JNIEnv* env, jclass clazz, jint sd, jstring jstr) {
	return callstr(env, sd, jstr, tailscale_set_authkey);
}

JNIEXPORT jint JNICALL
Java_com_tailscale_Tailscale_setControlURL(JNIEnv* env, jclass clazz, jint sd, jstring jstr) {
	return callstr(env, sd, jstr, tailscale_set_control_url);
}

JNIEXPORT jint JNICALL
Java_com_tailscale_Tailscale_setEphemeral(JNIEnv* env, jclass clazz, jint sd, jboolean val) {
	return tailscale_set_ephemeral(sd, val);
}

JNIEXPORT jint JNICALL
Java_com_tailscale_Tailscale_dial(JNIEnv* env, jclass clazz, jint sd, jstring jnetwork, jstring jaddr) {
	const char* network = jstringdup(env, jnetwork);
	const char* addr = jstringdup(env, jaddr);
	tailscale conn;
	int ret = tailscale_dial(sd, network, addr, &conn);
	free((void*)network);
	free((void*)addr);

	if (ret) {
		return ret;
	}
	return conn;
}

JNIEXPORT jint JNICALL
Java_com_tailscale_Tailscale_listen(JNIEnv* env, jclass clazz, jint sd, jstring jnetwork, jstring jaddr) {
	const char* network = jstringdup(env, jnetwork);
	const char* addr = jstringdup(env, jaddr);
	tailscale_conn conn;
	int ret = tailscale_listen(sd, network, addr, &conn);
	free((void*)network);
	free((void*)addr);

	if (ret) {
		return ret;
	}
	return conn;
}

JNIEXPORT jint JNICALL
Java_com_tailscale_Tailscale_listenerClose(JNIEnv* env, jclass clazz, jint ln) {
	return tailscale_listener_close(ln);
}

JNIEXPORT jint JNICALL
Java_com_tailscale_Tailscale_accept(JNIEnv* env, jclass clazz, jint ln) {
	tailscale_conn conn;
	int ret = tailscale_accept(ln, &conn);
	if (ret) {
		return ret;
	}
	return conn;
}

JNIEXPORT jstring JNICALL
Java_com_tailscale_Tailscale_loopback(JNIEnv* env, jclass clazz, jint sd, jarray proxyOut, jarray localOut) {
	char buf[4096] = {0};
	jbyte* proxy_out = (*env)->GetByteArrayElements(env, proxyOut, NULL);
	jbyte* local_out = (*env)->GetByteArrayElements(env, localOut, NULL);
	int ret = tailscale_loopback(sd, buf, sizeof(buf), (char*)proxy_out, (char*)local_out);
	(*env)->ReleaseByteArrayElements(env, localOut, local_out, 0);
	(*env)->ReleaseByteArrayElements(env, proxyOut, proxy_out, 0);
	if (ret) {
		return NULL;
	}
	return (*env)->NewStringUTF(env, buf);
}

JNIEXPORT jstring JNICALL
Java_com_tailscale_Tailscale_errmsg(JNIEnv* env, jclass clazz, jint sd) {
	char buf[4096] = {0};
	int ret;
	if ((ret = tailscale_errmsg(sd, buf, sizeof(buf))) != 0) {
		snprintf(buf, sizeof(buf), "tailscale_errmsg failed: %d", ret);
	}
	return (*env)->NewStringUTF(env, buf);
}
