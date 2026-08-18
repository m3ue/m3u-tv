import java.io.File
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.security.MessageDigest
import java.util.Properties
import java.util.UUID

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

// Downloads the prebuilt libmpv-android AAR (dev.jdtech.mpv Kotlin/JNI
// bindings over libmpv, used by AndroidMpvBackend's native side --
// android/app/src/main/kotlin/dev/sparkison/tv/mpv/MpvPlayerCore.kt). Same
// source and hash-pinning approach the open-source Plezy player
// (github.com/edde746/plezy, GPL-3.0) uses for its own Android mpv core.
fun verifySha256(file: File, expected: String, identity: String) {
    val digest = MessageDigest.getInstance("SHA-256")
    file.inputStream().buffered().use { input ->
        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
        while (true) {
            val count = input.read(buffer)
            if (count < 0) break
            digest.update(buffer, 0, count)
        }
    }
    val actual = digest.digest().joinToString("") { (it.toInt() and 0xff).toString(16).padStart(2, '0') }
    if (actual != expected) {
        throw GradleException("SHA-256 mismatch for $identity: expected $expected, got $actual")
    }
}

val mpvVersion = "v1.0.7"
val mpvSha256 = "d55d440e587b2a9ffb91874d93069460a987be05fe72af8394849983f0df2d7a"
val mpvDir = layout.buildDirectory.dir("libmpv").get().asFile
val mpvAar = "libmpv-release.aar"
val mpvUrl = "https://github.com/edde746/libmpv-android/releases/download/$mpvVersion/$mpvAar"

val downloadLibmpv = tasks.register("downloadLibmpv") {
    val aar = File(mpvDir, mpvAar)
    val manifest = File(mpvDir, ".manifest")
    inputs.property("version", mpvVersion)
    inputs.property("sourceUrl", mpvUrl)
    inputs.property("sha256", mpvSha256)
    outputs.files(aar, manifest)
    doLast {
        mpvDir.parentFile.mkdirs()
        val staging = File(mpvDir.parentFile, "${mpvDir.name}.staging-${UUID.randomUUID()}")
        try {
            staging.mkdirs()
            val stagedAar = File(staging, mpvAar)
            try {
                providers.exec {
                    commandLine("curl", "-sfL", mpvUrl, "-o", stagedAar.absolutePath)
                }.result.get().assertNormalExitValue()
            } catch (error: Exception) {
                throw GradleException("Failed to download $mpvAar $mpvVersion", error)
            }
            verifySha256(stagedAar, mpvSha256, "$mpvAar $mpvVersion")
            File(staging, ".manifest").writeText("version=$mpvVersion\nsha256=$mpvSha256\n")

            val backup = File(mpvDir.parentFile, "${mpvDir.name}.backup-${UUID.randomUUID()}")
            val hadDestination = mpvDir.exists()
            if (hadDestination) Files.move(mpvDir.toPath(), backup.toPath(), StandardCopyOption.ATOMIC_MOVE)
            Files.move(staging.toPath(), mpvDir.toPath(), StandardCopyOption.ATOMIC_MOVE)
            if (hadDestination) backup.deleteRecursively()
        } finally {
            staging.deleteRecursively()
        }
    }
}

tasks.matching { it.name.startsWith("pre") && it.name.endsWith("Build") }.configureEach {
    dependsOn(downloadLibmpv)
}

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
        // Overridden ahead of flutter.minSdkVersion (24): libmpv-android's
        // AndroidManifest.xml declares minSdkVersion=26, and the manifest
        // merger fails the build if the app's own minSdk is lower.
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
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    implementation("androidx.lifecycle:lifecycle-process:$lifecycleVersion")
    implementation("androidx.media3:media3-exoplayer:$media3Version")
    implementation("androidx.media3:media3-exoplayer-dash:$media3Version")
    implementation("androidx.media3:media3-exoplayer-hls:$media3Version")
    implementation("androidx.media3:media3-session:$media3Version")
    implementation("androidx.media3:media3-ui:$media3Version")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // libmpv-android (dev.jdtech.mpv) -- see downloadLibmpv above.
    implementation(files(File(mpvDir, mpvAar)))
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.11.0")
    testImplementation("junit:junit:4.13.2")
}

flutter {
    source = "../.."
}
