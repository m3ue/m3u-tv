package dev.sparkison.tv

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageInstaller
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * In-app updates for sideloaded installs (GitHub APK, Downloader). Dart
 * downloads and checksums the APK into the cache dir; this hands it to
 * [PackageInstaller] and reports the session's status back as
 * `onInstallStatus` calls. Android itself refuses an APK that isn't signed
 * with the installed app's key, so a Play-signed install can't be replaced.
 *
 * Installing needs REQUEST_INSTALL_PACKAGES, which only the sideload build's
 * manifest declares (see build.gradle.kts); without it [canRequestInstalls]
 * is always false and Dart never offers the update.
 */
class ApkUpdateInstaller(context: Context, messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {
    private val appContext = context.applicationContext
    private val channel = MethodChannel(messenger, CHANNEL)
    private val mainHandler = Handler(Looper.getMainLooper())
    private var statusReceiver: BroadcastReceiver? = null

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "installerPackage" -> result.success(installerPackage())
            "canRequestInstalls" -> result.success(appContext.packageManager.canRequestPackageInstalls())
            "openInstallPermissionSettings" -> result.success(openInstallPermissionSettings())
            "install" -> {
                val path = call.argument<String>("path")
                val apk = path?.let(::File)?.takeIf(::isInCacheDir)
                if (apk == null || !apk.isFile) {
                    result.error("invalid_path", "APK not found in the app cache", null)
                    return
                }
                install(apk, result)
            }
            else -> result.notImplemented()
        }
    }

    private fun installerPackage(): String? = try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            appContext.packageManager.getInstallSourceInfo(appContext.packageName).installingPackageName
        } else {
            @Suppress("DEPRECATION")
            appContext.packageManager.getInstallerPackageName(appContext.packageName)
        }
    } catch (_: Exception) {
        null
    }

    // Some TV builds don't ship the per-app "Install unknown apps" screen;
    // fall back to the security settings, where the global toggle lives.
    private fun openInstallPermissionSettings(): Boolean {
        val perApp = Intent(
            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
            Uri.parse("package:${appContext.packageName}"),
        )
        val fallback = Intent(Settings.ACTION_SECURITY_SETTINGS)
        for (intent in listOf(perApp, fallback)) {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            try {
                appContext.startActivity(intent)
                return true
            } catch (_: Exception) {
                // Try the next screen.
            }
        }
        return false
    }

    private fun isInCacheDir(file: File): Boolean {
        val cacheDir = appContext.cacheDir.canonicalPath + File.separator
        return file.canonicalPath.startsWith(cacheDir)
    }

    private fun install(apk: File, result: MethodChannel.Result) {
        ensureStatusReceiver()
        // Copying a ~100 MB APK into the session is too slow for the main thread.
        Thread {
            try {
                val installer = appContext.packageManager.packageInstaller
                val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL).apply {
                    setAppPackageName(appContext.packageName)
                    // Android 12+ may skip the confirm prompt once this app is
                    // its own installer of record (after the first self-update).
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED)
                    }
                }
                val sessionId = installer.createSession(params)
                installer.openSession(sessionId).use { session ->
                    apk.inputStream().use { input ->
                        session.openWrite("base.apk", 0, apk.length()).use { output ->
                            input.copyTo(output)
                            session.fsync(output)
                        }
                    }
                    val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                        (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0)
                    val statusIntent = PendingIntent.getBroadcast(
                        appContext,
                        sessionId,
                        Intent(STATUS_ACTION).setPackage(appContext.packageName),
                        flags,
                    )
                    session.commit(statusIntent.intentSender)
                }
                mainHandler.post { result.success(null) }
            } catch (e: Exception) {
                mainHandler.post { result.error("install_failed", e.message ?: e.javaClass.simpleName, null) }
            }
        }.start()
    }

    private fun ensureStatusReceiver() {
        if (statusReceiver != null) return
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                handleStatus(intent)
            }
        }
        ContextCompat.registerReceiver(
            appContext,
            receiver,
            IntentFilter(STATUS_ACTION),
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )
        statusReceiver = receiver
    }

    private fun handleStatus(intent: Intent) {
        val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)
        val message = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)
        if (status == PackageInstaller.STATUS_PENDING_USER_ACTION) {
            val confirm = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra(Intent.EXTRA_INTENT)
            }
            if (confirm != null) {
                confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                try {
                    appContext.startActivity(confirm)
                } catch (e: Exception) {
                    sendStatus("failure", PackageInstaller.STATUS_FAILURE, e.message)
                    return
                }
            }
            sendStatus("pendingUserAction", status, null)
            return
        }
        val kind = if (status == PackageInstaller.STATUS_SUCCESS) "success" else "failure"
        sendStatus(kind, status, message)
    }

    private fun sendStatus(kind: String, code: Int, message: String?) {
        mainHandler.post {
            channel.invokeMethod(
                "onInstallStatus",
                mapOf("kind" to kind, "code" to code, "message" to message),
            )
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        statusReceiver?.let {
            try {
                appContext.unregisterReceiver(it)
            } catch (_: IllegalArgumentException) {
                // Already gone.
            }
        }
        statusReceiver = null
    }

    companion object {
        private const val CHANNEL = "m3u_tv/apk_update"
        private const val STATUS_ACTION = "dev.sparkison.tv.APK_UPDATE_STATUS"
    }
}
