# JNI exports bind by name (Java_dev_sparkison_tv_libmpv_MpvPlayer_native*); keep the names stable.
-keepclasseswithmembernames class dev.sparkison.tv.libmpv.* {
    native <methods>;
}

# jni_utils.cpp caches MpvPlayer with FindClass and resolves these static callbacks
# with GetStaticMethodID on the native event thread. R8 sees no reference to the
# class name or the member names, so both must stay alive and un-renamed.
# Callback names, return type and static access are matched without the JNI
# argument descriptors: init_methods_cache resolves every exact descriptor, and
# listing them here let a signature change (the session token) silently stop
# matching.
-keep class dev.sparkison.tv.libmpv.MpvPlayer {
    public static void onPropertyChanged(...);
    public static void onEvent(...);
    public static void onEndFile(...);
    public static void onLogMessage(...);
    public static void onHook(...);
}

# main.cpp resolves MediaCodecCallbackBridge with FindClass and hands it to libavcodec
# (av_jni_set_mediacodec_callback_class), which resolves the constructor, handler() and
# release() with GetMethodID and binds the native methods with RegisterNatives. No app
# code references the class, so R8 would drop it and the Java MediaCodec wrapper would
# silently fall back to synchronous decoding with no rendered-frame feedback.
-keep class dev.sparkison.tv.libmpv.MediaCodecCallbackBridge {
    <init>(long);
    android.os.Handler handler();
    void release();
    native <methods>;
}
