package dev.sparkison.tv

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * The launcher asking for the app's home screen rows ([HomeScreenRows]),
 * after install and after it cleared its data. A Watch Next card the viewer
 * removes needs nothing here: the next write finds it hidden and records it.
 */
class HomeScreenReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (!HomeScreenRows.isSupported(context)) return
        HomeScreenRefreshWorker.refreshNow(context)
    }
}
