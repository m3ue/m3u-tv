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
