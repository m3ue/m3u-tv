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
 * - The app's own channels: "On Now" (the Live TV lineup, with what's
 *   airing on each channel) and Sports (today's games a channel carries).
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
    private const val PREFS = "home_screen_rows"
    private const val PROGRESS_STEP_MS = 2 * 60 * 1000L
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
        val channels = (payload["channels"] as? List<*>).orEmpty().filterIsInstance<Map<*, *>>()
        for (row in channels) {
            val id = row["id"] as? String ?: continue
            try {
                val enabled = row["enabled"] == true
                val items = (row["items"] as? List<*>).orEmpty().filterIsInstance<Map<*, *>>()
                // An empty channel shows on the home screen as a row with
                // nothing in it, so there's none until there is something to
                // put in it.
                if (enabled && items.isNotEmpty()) {
                    syncChannel(context, id, row["title"] as? String ?: id, items, cardKeys)
                } else {
                    Log.i(TAG, "$id: off or nothing to show (enabled=$enabled), removing the channel")
                    deleteChannel(context, id)
                }
            } catch (error: RuntimeException) {
                Log.w(TAG, "$id update failed", error)
            }
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
        var inserted = 0
        var updated = 0
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
                val uri = resolver.insert(TvContractCompat.WatchNextPrograms.CONTENT_URI, program.toContentValues())
                if (uri == null) Log.w(TAG, "Watch Next: insert refused for $key") else inserted++
            } else {
                val rows = resolver.update(
                    TvContractCompat.buildWatchNextProgramUri(current.id),
                    program.toContentValues(),
                    null,
                    null,
                )
                if (rows < 1) Log.w(TAG, "Watch Next: update refused for $key") else updated++
            }
        }
        for ((key, program) in existing) {
            if (key !in wanted) {
                resolver.delete(TvContractCompat.buildWatchNextProgramUri(program.id), null, null)
            }
        }
        Log.i(
            TAG,
            "Watch Next: ${items.size} sent, $inserted added, $updated updated, " +
                "${existing.size - existing.keys.count { it in wanted }} dropped, ${removed.size} hidden by the viewer",
        )
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
    // The app's channels ("On Now", Sports)
    // -------------------------------------------------------------------------

    @SuppressLint("RestrictedApi")
    private fun syncChannel(
        context: Context,
        id: String,
        title: String,
        items: List<Map<*, *>>,
        cardKeys: MutableSet<String>,
    ) {
        val resolver = context.contentResolver
        val channelId = channelIdFor(context, id, title) ?: return
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
        var inserted = 0
        var updated = 0
        var unchanged = 0
        items.forEachIndexed { index, item ->
            val key = item["key"] as? String ?: return@forEachIndexed
            if (!wanted.add(key)) return@forEachIndexed
            val program = previewProgram(context, channelId, item, key, items.size - index, now, cardKeys)
            val current = existing[key]
            if (current == null) {
                val uri = resolver.insert(TvContractCompat.PreviewPrograms.CONTENT_URI, program.toContentValues())
                if (uri == null) Log.w(TAG, "$id: insert refused for $key") else inserted++
            } else if (!changed(current, program)) {
                unchanged++
            } else {
                val rows = resolver.update(
                    TvContractCompat.buildPreviewProgramUri(current.id),
                    program.toContentValues(),
                    null,
                    null,
                )
                if (rows < 1) Log.w(TAG, "$id: update refused for $key") else updated++
            }
        }
        for ((key, program) in existing) {
            if (key !in wanted) {
                resolver.delete(TvContractCompat.buildPreviewProgramUri(program.id), null, null)
            }
        }
        Log.i(
            TAG,
            "$id: channel $channelId, ${items.size} sent, $inserted added, $updated updated, $unchanged unchanged",
        )
    }

    /**
     * Whether [next] would show differently from [current]. Rewriting a card
     * makes the launcher redraw it, and a focused card loses its channel
     * logo until it's focused again, so a card is only rewritten when
     * something shown changed. Programme progress counts once it has moved
     * on a little: the bar is too short to show less.
     */
    @SuppressLint("RestrictedApi")
    private fun changed(current: PreviewProgram, next: PreviewProgram): Boolean {
        val shown = current.toContentValues()
        val wanted = next.toContentValues()
        val position = TvContractCompat.PreviewPrograms.COLUMN_LAST_PLAYBACK_POSITION_MILLIS
        for (column in wanted.keySet()) {
            if (column == position) continue
            if (wanted.get(column)?.toString() != shown.get(column)?.toString()) return true
        }
        val moved = (wanted.getAsLong(position) ?: 0L) - (shown.getAsLong(position) ?: 0L)
        return kotlin.math.abs(moved) >= PROGRESS_STEP_MS
    }

    private fun previewProgram(
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
        builder.setLive(item["live"] == true)
        builder.setInternalProviderId(key)
        builder.setTitle(item["title"] as? String)
        (item["description"] as? String)?.let { builder.setDescription(it) }
        val artUri = (item["artworkUrl"] as? String)?.let(Uri::parse)
            ?: cardUri(context, (item["cardLogos"] as? List<*>).orEmpty().filterIsInstance<String>(), cardKeys)
        artUri?.let {
            builder.setPosterArtUri(it)
            builder.setPosterArtAspectRatio(TvContractCompat.PreviewPrograms.ASPECT_RATIO_16_9)
        }
        val start = (item["startMs"] as? Number)?.toLong()
        val end = (item["endMs"] as? Number)?.toLong()
        if (start != null) builder.setStartTimeUtcMillis(start)
        val showsProgress = start != null && end != null && end > start
        if (showsProgress) {
            builder.setEndTimeUtcMillis(end)
            // How far into the programme it is now; the next refresh moves it.
            builder.setDurationMillis((end - start).toInt())
            builder.setLastPlaybackPositionMillis((now - start).coerceIn(0, end - start).toInt())
        } else {
            // The launcher draws the logo badge where a focused card's
            // progress bar goes, covering it, so only a card without one
            // gets it.
            (item["logoUrl"] as? String)?.let { builder.setLogoUri(Uri.parse(it)) }
        }
        (item["launch"] as? Map<*, *>)?.let { builder.setIntentUri(launchUri(context, it)) }
        return builder.build()
    }

    /** A card drawn from [logos] (one channel, or a game's two teams). */
    private fun cardUri(context: Context, logos: List<String>, cardKeys: MutableSet<String>): Uri? {
        if (logos.isEmpty()) return null
        val cardKey = LogoArtworkProvider.keyFor(logos.joinToString("|"))
        if (!LogoArtworkProvider.writeCard(context, cardKey, logos)) return null
        cardKeys += cardKey
        return LogoArtworkProvider.cardUri(context, cardKey)
    }

    @SuppressLint("RestrictedApi")
    private fun findChannels(context: Context, id: String): List<androidx.tvprovider.media.tv.Channel> {
        val found = mutableListOf<androidx.tvprovider.media.tv.Channel>()
        context.contentResolver.query(
            TvContractCompat.Channels.CONTENT_URI,
            androidx.tvprovider.media.tv.Channel.PROJECTION,
            null,
            null,
            null,
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                val channel = androidx.tvprovider.media.tv.Channel.fromCursor(cursor)
                if (channel.internalProviderId == id) found += channel
            }
        }
        return found
    }

    /** The id of the app's channel [id], created (and shown) on first use. */
    @SuppressLint("RestrictedApi")
    private fun channelIdFor(context: Context, id: String, title: String): Long? {
        val resolver = context.contentResolver
        val appLink = Uri.parse(openAppIntent(context).toUri(Intent.URI_INTENT_SCHEME))
        val values = androidx.tvprovider.media.tv.Channel.Builder()
            .setType(TvContractCompat.Channels.TYPE_PREVIEW)
            .setDisplayName(title)
            .setAppLinkIntentUri(appLink)
            .setInternalProviderId(id)
            .build()
            .toContentValues()
        findChannels(context, id).firstOrNull()?.let { existing ->
            if (existing.displayName != title) {
                resolver.update(TvContractCompat.buildChannelUri(existing.id), values, null, null)
            }
            return existing.id
        }
        val uri = resolver.insert(TvContractCompat.Channels.CONTENT_URI, values) ?: return null
        val channelId = ContentUris.parseId(uri)
        BitmapFactory.decodeResource(context.resources, R.mipmap.launcher_icon)?.let { icon ->
            ChannelLogoUtils.storeChannelLogo(context, channelId, icon)
        }
        // Only the app's first channel is shown without asking; the launcher
        // lists any others for the viewer to turn on.
        try {
            TvContractCompat.requestChannelBrowsable(context, channelId)
        } catch (error: RuntimeException) {
            Log.w(TAG, "Couldn't show the $id channel", error)
        }
        return channelId
    }

    private fun deleteChannel(context: Context, id: String) {
        for (channel in findChannels(context, id)) {
            // Takes the channel's programmes with it.
            context.contentResolver.delete(TvContractCompat.buildChannelUri(channel.id), null, null)
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
