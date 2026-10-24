package dev.sparkison.tv

import android.content.Context
import android.view.View
import android.widget.FrameLayout
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/**
 * `AndroidView` factory backing `m3u_tv/android_exo_view`. Creates the
 * container `View` hosting the `SurfaceView` ExoPlayer renders directly
 * into, keyed by the Dart-generated `playerId` so `Media3PlaybackPlugin` can
 * find it by the same id `load`/control method calls carry.
 *
 * A real, window-attached `SurfaceView` (Hybrid Composition) instead of a
 * Flutter `SurfaceProducer` texture is required for correct HDR rendering:
 * Flutter's texture path is an offscreen GL texture never attached to a
 * real `Display`, so SurfaceFlinger has no HDR dataspace to negotiate and
 * hands back raw BT.2020/PQ pixel data that Flutter's compositor samples as
 * plain BT.709/SDR -- a strong red/magenta push, not a subtle tint. A
 * `SurfaceView` is a genuine hardware-composited layer attached to the
 * physical `Display`, matching the open-source Plezy player
 * (github.com/edde746/plezy, GPL-3.0)'s `PlayerSurfaceHost`/`ExoPlayerCore`,
 * which renders its primary ExoPlayer path the same way.
 */
class Media3PlatformViewFactory(private val plugin: Media3PlaybackPlugin) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, androidViewId: Int, args: Any?): PlatformView {
        @Suppress("UNCHECKED_CAST")
        val params = args as? Map<String, Any?>
        val playerId = (params?.get("playerId") as? String) ?: "default"
        return Media3PlatformView(context, playerId, plugin)
    }
}

class Media3PlatformView(context: Context, private val playerId: String, private val plugin: Media3PlaybackPlugin) :
    PlatformView {
    private val container = FrameLayout(context)
    private val surfaceView = plugin.attachSurfaceView(playerId, context)
    private val subtitleView = plugin.attachSubtitleView(playerId, context)
    private val posterView = plugin.attachPosterView(playerId, context)

    init {
        container.addView(
            surfaceView,
            FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT),
        )
        // Added above the SurfaceView, same layer ordering as Plezy's
        // PlayerSurfaceHost/ExoPlayerCore (see this file's header comment):
        // under hybrid composition, native views composite in add order, so
        // cue text draws over the video without any z-order/transparency
        // hacks.
        container.addView(
            subtitleView,
            FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT),
        )
        // Added last (topmost) so it covers both of the above while a
        // stream loads - see `PosterLoader.kt`'s header comment for why
        // this has to be a native view rather than a Flutter-side overlay.
        container.addView(
            posterView,
            FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT),
        )
    }

    override fun getView(): View = container

    // Native teardown is driven by the `dispose` method-channel call (see
    // Media3PlaybackPlugin.onMethodCall), which -- like the mpv/Apple
    // platform views -- must finish before Flutter unmounts this view
    // (PlaybackOrchestrator awaits PlatformViewProvider.releaseNativeView()
    // first). Only detach the surface/subtitle/poster references here so a
    // later `load` for this playerId doesn't race against a torn-down view.
    override fun dispose() {
        plugin.detachSurfaceView(playerId, surfaceView)
        plugin.detachSubtitleView(playerId, subtitleView)
        plugin.detachPosterView(playerId, posterView)
    }
}
