import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android Gradle plugin.
    id("dev.flutter.flutter-gradle-plugin")
}

val media3Version = "1.10.1"
val lifecycleVersion = "2.9.4"

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
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "dev.sparkison.tv"
        minSdk = flutter.minSdkVersion
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

dependencies {
    implementation("androidx.lifecycle:lifecycle-process:$lifecycleVersion")
    implementation("androidx.media3:media3-exoplayer:$media3Version")
    implementation("androidx.media3:media3-exoplayer-dash:$media3Version")
    implementation("androidx.media3:media3-exoplayer-hls:$media3Version")
    implementation("androidx.media3:media3-session:$media3Version")
    implementation("androidx.media3:media3-ui:$media3Version")
}

flutter {
    source = "../.."
}
