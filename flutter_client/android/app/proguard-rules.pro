# WorkManager (HomeScreenRefreshWorker) builds its Room database by
# reflection, through the generated class's no-argument constructor. R8's full
# mode strips that constructor from release builds, and the app then crashed
# on launch while androidx.startup initialized WorkManager
# (NoSuchMethodException: androidx.work.impl.WorkDatabase_Impl.<init>).
-keep class * extends androidx.room.RoomDatabase {
    <init>();
}
-keep class androidx.work.impl.WorkDatabase_Impl { *; }
