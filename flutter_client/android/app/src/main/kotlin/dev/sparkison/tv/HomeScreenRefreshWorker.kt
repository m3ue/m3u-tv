package dev.sparkison.tv

import android.content.Context
import android.util.Log
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume

/**
 * Keeps the home screen rows ([HomeScreenRows]) current while the app isn't
 * open, so they don't go stale for days until it next is: starts the app's
 * engine without an activity, as Android Auto does ([AppFlutterEngine]), asks
 * Dart for fresh rows (Continue Watching from the server, and what's airing
 * on the favorite channels), writes them, and lets the engine go.
 *
 * Runs every [PERIODIC_MINUTES], and also when the programme airing soonest
 * on an "On Now" channel ends, so that row moves on with the guide.
 */
class HomeScreenRefreshWorker(
    context: Context,
    params: WorkerParameters,
) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        val context = applicationContext
        if (!HomeScreenRows.isSupported(context)) return Result.success()
        val payload = withContext(Dispatchers.Main) {
            AppFlutterEngine.attachBackground(context)
            try {
                withTimeoutOrNull(COLLECT_TIMEOUT_MS) {
                    suspendCancellableCoroutine { continuation ->
                        val bridge = HomeScreenBridge.current
                        if (bridge == null) {
                            continuation.resume(null)
                        } else {
                            bridge.callDart("collect") { continuation.resume(it) }
                        }
                    }
                }
            } finally {
                AppFlutterEngine.detachBackground()
            }
        } as? Map<*, *>
        if (payload == null) {
            // Not signed in yet, or Dart didn't answer in time: the rows
            // stay as they are until the next run.
            Log.i(TAG, "No rows to write")
            return Result.success()
        }
        withContext(Dispatchers.IO) { HomeScreenBridge.publish(context, payload) }
        return Result.success()
    }

    companion object {
        private const val TAG = "HomeScreenRefresh"
        private const val PERIODIC_WORK = "home_screen_rows_periodic"
        private const val NEXT_WORK = "home_screen_rows_next"
        private const val PERIODIC_MINUTES = 30L
        private const val COLLECT_TIMEOUT_MS = 90_000L

        // A programme boundary refresh waits a little past the end, so the
        // guide already lists the next one as airing.
        private const val BOUNDARY_SLACK_MS = 30_000L
        private const val MIN_DELAY_MS = 60_000L

        private val constraints = Constraints.Builder()
            .setRequiredNetworkType(NetworkType.CONNECTED)
            .build()

        /** Plans the background refreshes [payload]'s rows need. */
        fun schedule(context: Context, payload: Map<*, *>) {
            val workManager = WorkManager.getInstance(context)
            val watchNextEnabled = payload["watchNextEnabled"] == true
            val onNowEnabled = payload["onNowEnabled"] == true
            if (!watchNextEnabled && !onNowEnabled) {
                workManager.cancelUniqueWork(PERIODIC_WORK)
                workManager.cancelUniqueWork(NEXT_WORK)
                return
            }
            workManager.enqueueUniquePeriodicWork(
                PERIODIC_WORK,
                ExistingPeriodicWorkPolicy.KEEP,
                PeriodicWorkRequestBuilder<HomeScreenRefreshWorker>(PERIODIC_MINUTES, TimeUnit.MINUTES)
                    .setConstraints(constraints)
                    .build(),
            )
            val refreshAt = (payload["refreshAtMs"] as? Number)?.toLong()
            if (!onNowEnabled || refreshAt == null) {
                workManager.cancelUniqueWork(NEXT_WORK)
                return
            }
            // Past the periodic run there's no point waiting for it.
            val delay = (refreshAt + BOUNDARY_SLACK_MS - System.currentTimeMillis())
                .coerceIn(MIN_DELAY_MS, TimeUnit.MINUTES.toMillis(PERIODIC_MINUTES))
            workManager.enqueueUniqueWork(
                NEXT_WORK,
                ExistingWorkPolicy.REPLACE,
                OneTimeWorkRequestBuilder<HomeScreenRefreshWorker>()
                    .setInitialDelay(delay, TimeUnit.MILLISECONDS)
                    .setConstraints(constraints)
                    .build(),
            )
        }

        /** Refreshes the rows soon, e.g. when the launcher asks for them. */
        fun refreshNow(context: Context) {
            WorkManager.getInstance(context).enqueueUniqueWork(
                NEXT_WORK,
                ExistingWorkPolicy.REPLACE,
                OneTimeWorkRequestBuilder<HomeScreenRefreshWorker>()
                    .setConstraints(constraints)
                    .build(),
            )
        }
    }
}
