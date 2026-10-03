package dev.sparkison.tv

import android.app.Activity
import android.content.Context
import android.os.Build
import android.view.Display
import android.view.WindowManager
import java.util.Locale

/**
 * Applies Auto Frame Rate display-mode matching on Android TV (issue #283):
 * switches the Activity window's preferred display mode to one presenting
 * the source's frame rate cleanly, and restores it when playback stops.
 *
 * Opt-in, off by default -- gated by `PlaybackSource.matchDisplayRefreshRate`
 * (mirrors `ViewSettingsService.matchRefreshRate`, surfaced in Settings next
 * to the existing Windows toggle). This mirrors the open-source Plezy
 * player's own Android setting, `matchContentFrameRate` (also off by
 * default) -- Plezy does not force this on Android, so neither does this app.
 * (tvOS's `AVDisplayManager.preferredDisplayCriteria` use in
 * `tvos/Runner/MpvPlayer/MpvPlayerCore.swift` stays unconditional/unchanged:
 * Plezy's own tvOS core has no equivalent toggle either, so there is nothing
 * to surface for that platform.)
 *
 * One instance is shared by both playback plugins (Media3 and mpv), passed
 * in from `MainActivity`: a `Window`'s `preferredDisplayModeId` is inherently
 * single-owner per Activity, so two independent writers racing during a
 * backend fallback handoff would be unsafe. Sharing is safe because the two
 * plugins never render video concurrently -- `PlaybackOrchestrator` fully
 * releases one native view before loading the next backend.
 *
 * Ported and scoped down from the open-source Plezy player's
 * `FrameRateManager` (github.com/edde746/plezy, GPL-3.0,
 * android/.../shared/FrameRateManager.kt): no `DisplayManager.DisplayListener`
 * settle/watchdog confirmation and no HDR-exit sequencing or
 * `Surface.setFrameRate` hinting in v1 -- nothing here awaits the switch
 * landing (unlike Plezy, no caller pauses playback around it), so that
 * machinery would be diagnostic-only complexity with no functional consumer.
 * Left as documented follow-up work if a real report needs it.
 *
 * Every request and its outcome -- including the panel's full mode list and
 * a "nothing to match" -- goes to [log], which `MainActivity` points at
 * [NativeLogChannel] so a user's Logs & Diagnostics upload shows why a
 * switch did or didn't happen (issue #314). Main thread only.
 */
class FrameRateManager(
    private val activity: Activity,
    val log: (String) -> Unit = {},
) {
    private var applied = false

    /**
     * Applies the best available display mode for [fps], if any and if
     * different from the current mode. [source] names where the rate came
     * from (container metadata, a measurement), for the log only.
     */
    fun applyForFrameRate(fps: Double, source: String) {
        if (fps <= 0.0 || Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        val request = "${formatRate(fps)}fps ($source)"
        val display = currentDisplay()
        val supportedModes = display?.supportedModes
        val currentMode = display?.mode
        if (supportedModes == null || currentMode == null) {
            log("$request: display modes unavailable, not matching")
            return
        }
        log("$request: current ${describe(currentMode)}, supported ${supportedModes.joinToString(prefix = "[", postfix = "]") { describe(it) }}")

        val candidates = supportedModes.map {
            DisplayModeSelector.Mode(it.modeId, it.refreshRate.toDouble(), it.physicalWidth, it.physicalHeight)
        }
        val target = DisplayModeSelector.bestMode(candidates, currentMode.modeId, fps)
        if (target == null) {
            log("$request: no ${currentMode.physicalWidth}x${currentMode.physicalHeight} mode presents it cleanly, staying at ${formatRate(currentMode.refreshRate.toDouble())}Hz")
            return
        }
        if (target.modeId == currentMode.modeId) {
            log("$request: current mode already presents it, no switch")
            return
        }

        val window = activity.window ?: return
        log("$request: switching to #${target.modeId} ${target.width}x${target.height}@${formatRate(target.refreshRate)}Hz")
        window.attributes = window.attributes.apply { preferredDisplayModeId = target.modeId }
        applied = true
    }

    /** Restores the system's default display mode. Safe to call even if nothing was ever applied. */
    fun restore() {
        if (!applied) return
        applied = false
        val window = activity.window ?: return
        if (window.attributes.preferredDisplayModeId == 0) return
        log("restoring default display mode")
        window.attributes = window.attributes.apply { preferredDisplayModeId = 0 }
    }

    private fun currentDisplay(): Display? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
        activity.display
    } else {
        @Suppress("DEPRECATION")
        (activity.getSystemService(Context.WINDOW_SERVICE) as? WindowManager)?.defaultDisplay
    }

    private fun describe(mode: Display.Mode): String =
        "#${mode.modeId} ${mode.physicalWidth}x${mode.physicalHeight}@${formatRate(mode.refreshRate.toDouble())}Hz"

    private fun formatRate(rate: Double): String = String.format(Locale.US, "%.3f", rate)
}
