package dev.sparkison.tv.mpv

import android.content.Context
import android.view.View
import android.widget.FrameLayout
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/**
 * `AndroidView` factory backing `m3u_tv/android_mpv_view`. Creates the
 * container `View` hosting the `SurfaceView` mpv draws directly into (via
 * `MpvPlayerCore.attachSurface`), and registers the resulting core with
 * [MpvPlayerPlugin] so the method/event channel can find it by `viewId`.
 *
 * Modeled on `macos/Runner/MpvPlayer/MpvPlayerPlatformView.swift`.
 */
class MpvPlayerPlatformViewFactory(private val plugin: MpvPlayerPlugin) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, androidViewId: Int, args: Any?): PlatformView {
        @Suppress("UNCHECKED_CAST")
        val params = args as? Map<String, Any?>
        val mpvViewId = (params?.get("viewId") as? Int) ?: androidViewId
        return MpvPlayerPlatformView(context, mpvViewId, plugin)
    }
}

class MpvPlayerPlatformView(context: Context, viewId: Int, plugin: MpvPlayerPlugin) : PlatformView {
    private val container = FrameLayout(context)

    init {
        val core = plugin.attachCore(viewId, context)
        container.addView(
            core.surfaceView,
            FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT),
        )
    }

    override fun getView(): View = container

    // Native teardown is driven by the `dispose` method-channel call (see
    // MpvPlayerPlugin.handle), which -- like the Apple platform views --
    // must finish before Flutter unmounts this view (PlaybackOrchestrator
    // awaits PlatformViewProvider.releaseNativeView() first). Nothing extra
    // to do here.
    override fun dispose() {}
}
