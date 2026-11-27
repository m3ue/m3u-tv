package dev.sparkison.tv

import android.annotation.SuppressLint
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.BitmapFactory
import android.net.Uri
import android.util.Log
import androidx.tvprovider.media.tv.ChannelLogoUtils
import androidx.tvprovider.media.tv.PreviewProgram
import androidx.tvprovider.media.tv.TvContractCompat
import androidx.tvprovider.media.tv.WatchNextProgram

/**
 * The app's rows on the Android TV home screen, from what Dart sends
 * (`android_home_screen_bridge.dart`):
 *
 * - Watch Next: the shared row every app adds to. Continue Watching entries
 *   (with the launcher's own progress bar) and Up Next episodes.
 * - "On Now": the app's own channel, the favorite live channels with what's
 *   airing on each.
 *
 * The launcher only shows what was last written here, so these are written
 * again whenever they may have changed: on leaving the app, after playback,
 * and from [HomeScreenRefreshWorker] while the app isn't open.
 *
 * A Watch Next card the viewer removes on the home screen stays removed
 * until they watch more of it (its position changes), as Android asks.
 *
 * Blocking (content provider and network), so call off the main thread.
 */
internal object HomeScreenRows {
    private const val TAG = "HomeScreenRows"
    private const val ON_NOW_CHANNEL_ID = "on_now"
    private const val PREFS = "home_screen_rows"
    private const val REMOVED_KEY = "removed_watch_next"

    const val ACTION_OPEN = "dev.sparkison.tv.action.HOME_SCREEN_OPEN"
    private const val EXTRA_PREFIX = "home_screen."

    /** Whether this device has a home screen to put rows on. */
    fun isSupported(context: Context): Boolean =
        context.packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK)

    fun publish(context: Context, payload: Map<*, *>) {
        if (!isSupported(context)) return
        val cardKeys = mutableSetOf<String>()
        try {
            val watchNextEnabled = payload["watchNextEnabled"] == true
            val watchNext = (payload["watchNext"] as? List<*>).orEmpty().filterIsInstance<Map<*, *>>()
            syncWatchNext(context, if (watchNextEnabled) watchNext else emptyList())
        } catch (error: RuntimeException) {
            // No TvProvider (some OEM builds), or it refused the write.
            Log.w(TAG, "Watch Next update failed", error)
        }
        try {
            val onNowEnabled = payload["onNowEnabled"] == true
            if (onNowEnabled) {
                val title = payload["onNowTitle"] as? String ?: "On Now"
                val items = (payload["onNow"] as? List<*>).orEmpty().filterIsInstance<Map<*, *>>()
                syncOnNow(context, title, items, cardKeys)
            } else {
                deleteOnNowChannel(context)
            }
        } catch (error: RuntimeException) {
            Log.w(TAG, "On Now update failed", error)
        }
        LogoArtworkProvider.pruneCards(context, cardKeys)
    }

    // -------------------------------------------------------------------------
    // Watch Next
    // -------------------------------------------------------------------------

    @SuppressLint("RestrictedApi")
    private fun syncWatchNext(context: Context, items: List<Map<*, *>>) {
        val resolver = context.contentResolver
        val existing = mutableMapOf<String, WatchNextProgram>()
        val removed = removedWatchNext(context)
        resolver.query(
            TvContractCompat.WatchNextPrograms.CONTENT_URI,
            WatchNextProgram.PROJECTION,
            null,
            null,
            null,
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                val program = WatchNextProgram.fromCursor(cursor)
                val key = program.internalProviderId
                if (key == null || !program.isBrowsable) {
                    // Removed by the viewer on the home screen: remember at
                    // which point, then drop the row.
                    if (key != null) removed[key] = engagementOf(program)
                    resolver.delete(TvContractCompat.buildWatchNextProgramUri(program.id), null, null)
                    continue
                }
                existing[key] = program
            }
        }

        val now = System.currentTimeMillis()
        val wanted = mutableSetOf<String>()
        items.forEachIndexed { index, item ->
            val key = item["key"] as? String ?: return@forEachIndexed
            val engagement = item["engagement"] as? String ?: ""
            val removedAt = removed[key]
            if (removedAt != null) {
                if (removedAt == engagement) return@forEachIndexed
                removed.remove(key)
            }
            wanted += key
            val current = existing[key]
            // Keeps the card where it was while nothing about it changed;
            // the launcher orders Watch Next by this.
            val engagedAt = if (current != null && engagementOf(current) == engagement) {
                current.lastEngagementTimeUtcMillis
            } else {
                now - index * 1000L
            }
            val program = watchNextProgram(context, item, key, engagement, engagedAt)
            if (current == null) {
                resolver.insert(TvContractCompat.WatchNextPrograms.CONTENT_URI, program.toContentValues())
            } else {
                resolver.update(
                    TvContractCompat.buildWatchNextProgramUri(current.id),
                    program.toContentValues(),
                    null,
                    null,
                )
            }
        }
        for ((key, program) in existing) {
            if (key !in wanted) {
                resolver.delete(TvContractCompat.buildWatchNextProgramUri(program.id), null, null)
            }
        }
        // Forget removals of items no longer listed at all.
        val listed = items.mapNotNull { it["key"] as? String }.toSet()
        saveRemovedWatchNext(context, removed.filterKeys { it in listed })
    }

    private fun watchNextProgram(
        context: Context,
        item: Map<*, *>,
        key: String,
        engagement: String,
        engagedAt: Long,
    ): WatchNextProgram {
        val isEpisode = item["contentType"] == "episode"
        val builder = WatchNextProgram.Builder()
            .setWatchNextType(
                if (item["upNext"] == true) {
                    TvContractCompat.WatchNextPrograms.WATCH_NEXT_TYPE_NEXT
                } else {
                    TvContractCompat.WatchNextPrograms.WATCH_NEXT_TYPE_CONTINUE
                },
            )
            .setLastEngagementTimeUtcMillis(engagedAt)
        builder.setType(
            if (isEpisode) {
                TvContractCompat.PreviewPrograms.TYPE_TV_EPISODE
            } else {
                TvContractCompat.PreviewPrograms.TYPE_MOVIE
            },
        )
        builder.setInternalProviderId(key)
        builder.setInternalProviderData(engagement.toByteArray())
        builder.setTitle(item["title"] as? String)
        (item["episodeTitle"] as? String)?.let { builder.setEpisodeTitle(it) }
        (item["seasonNumber"] as? Number)?.let { builder.setSeasonNumber(it.toInt()) }
        (item["episodeNumber"] as? Number)?.let { builder.setEpisodeNumber(it.toInt()) }
        (item["description"] as? String)?.let { builder.setDescription(it) }
        (item["imageUrl"] as? String)?.let { url ->
            builder.setPosterArtUri(Uri.parse(url))
            builder.setPosterArtAspectRatio(TvContractCompat.PreviewPrograms.ASPECT_RATIO_16_9)
        }
        (item["positionMs"] as? Number)?.let { builder.setLastPlaybackPositionMillis(it.toInt()) }
        (item["durationMs"] as? Number)?.let { builder.setDurationMillis(it.toInt()) }
        (item["launch"] as? Map<*, *>)?.let { builder.setIntentUri(launchUri(context, it)) }
        return builder.build()
    }

    @SuppressLint("RestrictedApi")
    private fun engagementOf(program: WatchNextProgram): String =
        program.internalProviderDataByteArray?.let { String(it) } ?: ""

    private fun removedWatchNext(context: Context): MutableMap<String, String> {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        return prefs.getStringSet(REMOVED_KEY, emptySet()).orEmpty()
            .mapNotNull { entry ->
                val split = entry.indexOf('|')
                if (split < 0) null else entry.substring(0, split) to entry.substring(split + 1)
            }
            .toMap(mutableMapOf())
    }

    private fun saveRemovedWatchNext(context: Context, removed: Map<String, String>) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putStringSet(REMOVED_KEY, removed.map { (key, at) -> "$key|$at" }.toSet())
            .apply()
    }

    // -------------------------------------------------------------------------
    // On Now
    // -------------------------------------------------------------------------

    @SuppressLint("RestrictedApi")
    private fun syncOnNow(
        context: Context,
        title: String,
        items: List<Map<*, *>>,
        cardKeys: MutableSet<String>,
    ) {
        val resolver = context.contentResolver
        val channelId = onNowChannelId(context, title) ?: return
        val existing = mutableMapOf<String, PreviewProgram>()
        resolver.query(
            TvContractCompat.buildPreviewProgramsUriForChannel(channelId),
            PreviewProgram.PROJECTION,
            null,
            null,
            null,
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                val program = PreviewProgram.fromCursor(cursor)
                val key = program.internalProviderId
                if (key == null || key in existing) {
                    resolver.delete(TvContractCompat.buildPreviewProgramUri(program.id), null, null)
                } else {
                    existing[key] = program
                }
            }
        }

        val now = System.currentTimeMillis()
        val wanted = mutableSetOf<String>()
        items.forEachIndexed { index, item ->
            val key = item["key"] as? String ?: return@forEachIndexed
            if (!wanted.add(key)) return@forEachIndexed
            val program = onNowProgram(context, channelId, item, key, items.size - index, now, cardKeys)
            val current = existing[key]
            if (current == null) {
                resolver.insert(TvContractCompat.PreviewPrograms.CONTENT_URI, program.toContentValues())
            } else {
                resolver.update(
                    TvContractCompat.buildPreviewProgramUri(current.id),
                    program.toContentValues(),
                    null,
                    null,
                )
            }
        }
        for ((key, program) in existing) {
            if (key !in wanted) {
                resolver.delete(TvContractCompat.buildPreviewProgramUri(program.id), null, null)
            }
        }
    }

    private fun onNowProgram(
        context: Context,
        channelId: Long,
        item: Map<*, *>,
        key: String,
        weight: Int,
        now: Long,
        cardKeys: MutableSet<String>,
    ): PreviewProgram {
        val builder = PreviewProgram.Builder()
            .setChannelId(channelId)
            .setWeight(weight)
        builder.setType(TvContractCompat.PreviewPrograms.TYPE_CHANNEL)
        builder.setLive(true)
        builder.setInternalProviderId(key)
        builder.setTitle(item["title"] as? String)
        (item["description"] as? String)?.let { builder.setDescription(it) }
        val artUri = (item["artworkUrl"] as? String)?.let(Uri::parse)
            ?: (item["logoUrl"] as? String)?.let { logo ->
                val cardKey = LogoArtworkProvider.keyFor(logo)
                if (LogoArtworkProvider.writeCard(context, cardKey, logo)) {
                    cardKeys += cardKey
                    LogoArtworkProvider.cardUri(context, cardKey)
                } else {
                    null
                }
            }
        artUri?.let {
            builder.setPosterArtUri(it)
            builder.setPosterArtAspectRatio(TvContractCompat.PreviewPrograms.ASPECT_RATIO_16_9)
        }
        (item["logoUrl"] as? String)?.let { builder.setLogoUri(Uri.parse(it)) }
        val start = (item["startMs"] as? Number)?.toLong()
        val end = (item["endMs"] as? Number)?.toLong()
        if (start != null && end != null && end > start) {
            builder.setStartTimeUtcMillis(start)
            builder.setEndTimeUtcMillis(end)
            // How far into the programme it is now; the next refresh moves it.
            builder.setDurationMillis((end - start).toInt())
            builder.setLastPlaybackPositionMillis((now - start).coerceIn(0, end - start).toInt())
        }
        (item["launch"] as? Map<*, *>)?.let { builder.setIntentUri(launchUri(context, it)) }
        return builder.build()
    }

    /** The "On Now" channel's id, created (and shown) on first use. */
    @SuppressLint("RestrictedApi")
    private fun onNowChannelId(context: Context, title: String): Long? {
        val resolver = context.contentResolver
        var channel: androidx.tvprovider.media.tv.Channel? = null
        resolver.query(
            TvContractCompat.Channels.CONTENT_URI,
            androidx.tvprovider.media.tv.Channel.PROJECTION,
            null,
            null,
            null,
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                val found = androidx.tvprovider.media.tv.Channel.fromCursor(cursor)
                if (found.internalProviderId == ON_NOW_CHANNEL_ID && channel == null) {
                    channel = found
                }
            }
        }
        val appLink = Uri.parse(openAppIntent(context).toUri(Intent.URI_INTENT_SCHEME))
        val values = androidx.tvprovider.media.tv.Channel.Builder()
            .setType(TvContractCompat.Channels.TYPE_PREVIEW)
            .setDisplayName(title)
            .setAppLinkIntentUri(appLink)
            .setInternalProviderId(ON_NOW_CHANNEL_ID)
            .build()
            .toContentValues()
        channel?.let { existing ->
            if (existing.displayName != title) {
                resolver.update(TvContractCompat.buildChannelUri(existing.id), values, null, null)
            }
            return existing.id
        }
        val uri = resolver.insert(TvContractCompat.Channels.CONTENT_URI, values) ?: return null
        val id = ContentUris.parseId(uri)
        BitmapFactory.decodeResource(context.resources, R.mipmap.launcher_icon)?.let { icon ->
            ChannelLogoUtils.storeChannelLogo(context, id, icon)
        }
        // The app's first channel is shown without asking the viewer.
        try {
            TvContractCompat.requestChannelBrowsable(context, id)
        } catch (error: RuntimeException) {
            Log.w(TAG, "Couldn't show the On Now channel", error)
        }
        return id
    }

    @SuppressLint("RestrictedApi")
    private fun deleteOnNowChannel(context: Context) {
        val resolver = context.contentResolver
        resolver.query(
            TvContractCompat.Channels.CONTENT_URI,
            androidx.tvprovider.media.tv.Channel.PROJECTION,
            null,
            null,
            null,
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                val channel = androidx.tvprovider.media.tv.Channel.fromCursor(cursor)
                if (channel.internalProviderId == ON_NOW_CHANNEL_ID) {
                    // Takes the channel's programmes with it.
                    resolver.delete(TvContractCompat.buildChannelUri(channel.id), null, null)
                }
            }
        }
    }

    // -------------------------------------------------------------------------
    // Launching
    // -------------------------------------------------------------------------

    private fun openAppIntent(context: Context): Intent =
        Intent(context, MainActivity::class.java)
            .setAction(Intent.ACTION_MAIN)
            .addCategory(Intent.CATEGORY_LAUNCHER)

    /**
     * What a card opens: the app, with what to play as `home_screen.*`
     * extras (handed to Dart by [HomeScreenBridge]). Flat string/number
     * extras, the only kind an intent URI carries, and no data URI, so the
     * engine's deep linking doesn't route it.
     */
    private fun launchUri(context: Context, launch: Map<*, *>): Uri {
        val intent = Intent(context, MainActivity::class.java).setAction(ACTION_OPEN)
        for ((name, value) in launch) {
            val key = name as? String ?: continue
            when (value) {
                is String -> intent.putExtra(EXTRA_PREFIX + key, value)
                is Number -> intent.putExtra(EXTRA_PREFIX + key, value.toLong())
            }
        }
        return Uri.parse(intent.toUri(Intent.URI_INTENT_SCHEME))
    }

    /** What [intent] (a card's) asks to open, for Dart; null for any other. */
    fun launchFrom(intent: Intent?): Map<String, Any?>? {
        if (intent?.action != ACTION_OPEN) return null
        val extras = intent.extras ?: return null
        return extras.keySet()
            .filter { it.startsWith(EXTRA_PREFIX) }
            .associate { key ->
                @Suppress("DEPRECATION")
                key.removePrefix(EXTRA_PREFIX) to extras.get(key)
            }
            .takeIf { it.isNotEmpty() }
    }
}
