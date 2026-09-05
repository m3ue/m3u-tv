import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Requires android/app/google-services.json to be present (gitignored,
    // downloaded from Firebase Console) — build fails without it.
    id("com.google.gms.google-services")
}

val media3Version = "1.10.1"
val lifecycleVersion = "2.9.4"

// The mpv-build tarballs' libc++_shared.so (extracted by :libmpv's own
// extractLibmpvNative task into its build dir, but deliberately left out of
// that module's own jniLibs -- see android/libmpv/build.gradle.kts) needs to
// win the merge over whatever default NDK libc++_shared.so AGP would
// otherwise auto-package for :libmpv's CMake-built glue library, so the
// runtime STL matches the toolchain generation libmpv.so/libavcodec.so were
// actually built against. Packaged here, at PROJECT scope, per the
// packaging{}/sourceSets{} blocks below.
val libmpvLibcxxJniDir = File(project(":libmpv").layout.buildDirectory.dir("libmpv").get().asFile, "libcxx/jni")

// Reads from (in priority order):
//   1. Gradle properties  (-PANDROID_KEYSTORE_PATH=...)
//   2. Environment variables  (ANDROID_KEYSTORE_PATH=...)
//   3. android/signing.properties  (gitignored, for local dev)
val androidSigningPropertiesFile = rootProject.file("signing.properties")
val androidSigningProperties = Properties().apply {
    if (androidSigningPropertiesFile.isFile) {
        androidSigningPropertiesFile.inputStream().use(::load)
    }
}

fun signingValue(name: String): String? =
    providers.gradleProperty(name).orNull?.takeIf { it.isNotBlank() }
        ?: providers.environmentVariable(name).orNull?.takeIf { it.isNotBlank() }
        ?: androidSigningProperties.getProperty(name)?.takeIf { it.isNotBlank() }

val releaseSigningKeys = listOf(
    "ANDROID_KEYSTORE_PATH",
    "ANDROID_KEY_ALIAS",
    "ANDROID_KEYSTORE_PASSWORD",
    "ANDROID_KEY_PASSWORD",
)

fun hasReleaseSigningKeys(): Boolean {
    val keystorePath = signingValue("ANDROID_KEYSTORE_PATH") ?: return false
    if (!file(keystorePath).isFile) return false
    return releaseSigningKeys.all { !signingValue(it).isNullOrBlank() }
}

val releaseSigningRequired =
    signingValue("ANDROID_REQUIRE_RELEASE_SIGNING")?.toBooleanStrictOrNull() ?: false
val releaseSigningAvailable = hasReleaseSigningKeys()

if (releaseSigningRequired && !releaseSigningAvailable) {
    throw GradleException(
        "ANDROID_REQUIRE_RELEASE_SIGNING is enabled, but Android release signing inputs are incomplete or the keystore file is missing.",
    )
}

android {
    namespace = "dev.sparkison.tv"
    // Overridden ahead of flutter.compileSdkVersion (still 36) so we're not
    // blocked when flutter_secure_storage 11.x (requires compileSdk 37) lands.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "dev.sparkison.tv"
        // Overridden ahead of flutter.minSdkVersion (24): kept at 26 as the
        // app's existing floor (the :libmpv module itself only requires 25,
        // see android/libmpv/build.gradle.kts).
        minSdk = maxOf(flutter.minSdkVersion, 26)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            val keystorePath = signingValue("ANDROID_KEYSTORE_PATH")
            if (keystorePath != null) storeFile = file(keystorePath)
            keyAlias = signingValue("ANDROID_KEY_ALIAS")
            storePassword = signingValue("ANDROID_KEYSTORE_PASSWORD")
            keyPassword = signingValue("ANDROID_KEY_PASSWORD")
        }
    }

    buildTypes {
        release {
            // Publication requires release signing. Local contributors without
            // credentials retain a debug-signed release build for development only.
            signingConfig = if (releaseSigningAvailable) {
                signingConfigs.getByName("release")
            } else {
                logger.warn("Creating a debug-signed release build for local development only. Do not publish it.")
                signingConfigs.getByName("debug")
            }
        }
    }

    packaging {
        jniLibs {
            // pickFirst only suppresses the duplicate libc++ merge error; the
            // sourceSets rule below makes the runtime :libmpv extracts from
            // the mpv-build tarballs win.
            pickFirsts.add("lib/*/libc++_shared.so")
        }
    }

    sourceSets {
        getByName("main") {
            // PROJECT-scope jniLibs merge ahead of subprojects/AARs, so
            // dependency order cannot accidentally select an older libc++
            // copy. The directory is :libmpv's extractLibmpvNative output,
            // wired below via the JniLibFolders task dependency.
            jniLibs.srcDir(libmpvLibcxxJniDir)
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

// Gradle snapshots jniLibs source dirs before task execution; this keeps the
// extracted mpv-build libc++ directory present during input discovery.
tasks.matching { it.name.startsWith("merge") && it.name.endsWith("JniLibFolders") }.configureEach {
    dependsOn(":libmpv:extractLibmpvNative")
}

dependencies {
    implementation("androidx.lifecycle:lifecycle-process:$lifecycleVersion")
    implementation("androidx.media3:media3-exoplayer:$media3Version")
    implementation("androidx.media3:media3-exoplayer-dash:$media3Version")
    implementation("androidx.media3:media3-exoplayer-hls:$media3Version")
    implementation("androidx.media3:media3-session:$media3Version")
    implementation("androidx.media3:media3-ui:$media3Version")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // mpv Kotlin API + JNI glue, built in-project against the pinned
    // mpv-build native tarballs -- see android/libmpv/build.gradle.kts.
    implementation(project(":libmpv"))
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.11.0")
    testImplementation("junit:junit:4.13.2")
}

flutter {
    source = "../.."
}
