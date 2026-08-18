#ifndef FLUTTER_CLIENT_LINUX_WAYLAND_VIDEO_SURFACE_H_
#define FLUTTER_CLIENT_LINUX_WAYLAND_VIDEO_SURFACE_H_

#include <EGL/egl.h>
#include <gtk/gtk.h>

#include <cstdint>
#include <functional>
#include <string>

struct wl_callback;
struct wl_compositor;
struct wl_display;
struct wl_egl_window;
struct wl_subcompositor;
struct wl_subsurface;
struct wl_surface;

namespace m3u_tv_mpv_plane {

// A native Wayland video plane: a wl_subsurface stacked *below* the Flutter
// toplevel surface, carrying its own EGL window surface that mpv renders
// into directly via the OpenGL render API.
//
// Adapted from the open-source Plezy player's `WaylandVideoSurface`
// (github.com/edde746/plezy, GPL-3.0, linux/runner/mpv/wayland_video_surface.h)
// with the wp_color_manager_v1 / HDR passthrough machinery removed for this
// phase: this plane only carries SDR, GPU-rendered output. mpv's own
// tone-mapped SDR output looks the same either way -- what changes here is
// that decode/scale/color conversion happens on the GPU into a real texture
// instead of a CPU pixel-buffer copy through Flutter's software texture
// path (see `desktop_libmpv_backend.cc`'s original SW render fallback,
// which this plane supersedes on Wayland and which X11 sessions still use,
// since mpv's `--wid` embedding -- the X11 equivalent -- has no Wayland
// counterpart and upstream mpv considers one out of scope).
//
// Flutter's own Linux (GTK) embedder has no platform-view API at all (unlike
// macOS/iOS), so this is the only way to give mpv a real GPU-owned surface on
// Linux: a native Wayland object the app manages directly, positioned to
// track a Dart widget's layout via explicit `SetRect()` calls rather than
// anything Flutter's compositor knows about.
//
// Everything here runs on the GTK main thread. The subsurface is
// desynchronized so its commits are independent of the parent's frame loop;
// position and stacking, however, are *parent* state and only take effect on
// a parent commit, which is why SetRect() asks the view to redraw.
class WaylandVideoSurface {
 public:
  WaylandVideoSurface() = default;
  ~WaylandVideoSurface();

  WaylandVideoSurface(const WaylandVideoSurface&) = delete;
  WaylandVideoSurface& operator=(const WaylandVideoSurface&) = delete;

  // True when the process is on a Wayland display. Cheap; safe to call
  // before the view is realized.
  static bool IsSupported(GdkDisplay* display);

  // Binds the Wayland globals, creates the subsurface under `view`'s
  // toplevel, and creates an EGL window surface on it. Returns false and
  // fills `error` on any failure -- the caller falls back to the existing
  // software pixel-buffer texture path.
  bool Create(GtkWidget* view, std::string* error);

  // Releases the EGL surface, subsurface and Wayland objects. Idempotent.
  void Destroy();

  bool valid() const { return egl_surface_ != EGL_NO_SURFACE; }
  EGLDisplay egl_display() const { return egl_display_; }
  EGLConfig egl_config() const { return egl_config_; }
  EGLSurface egl_surface() const { return egl_surface_; }

  // Current buffer size in physical pixels. Zero until the first SetRect().
  int32_t width() const { return width_; }
  int32_t height() const { return height_; }
  bool has_size() const { return rect_valid_; }

  // Places and sizes the plane. Coordinates are physical pixels in the
  // toplevel's frame, matching what Dart sends via setVideoRect.
  void SetRect(int32_t x, int32_t y, int32_t width, int32_t height, int32_t scale);

  // Hides the plane by attaching a null buffer. The next Present() re-shows it.
  void SetVisible(bool visible);
  bool visible() const { return visible_; }

  // True while a committed frame has not yet been acknowledged by the
  // compositor. Callers must not render while this holds.
  bool frame_pending() const { return frame_pending_; }

  // Whether any buffer has been presented since the surface was created.
  bool first_frame_presented() const { return first_frame_presented_; }

  // Invoked on the GTK main thread when the compositor acknowledges a frame,
  // or when the frame-ack watchdog gives up waiting and wants a re-present.
  void SetFrameCallback(std::function<void()> callback) { on_frame_ = std::move(callback); }

  // Presents whatever was rendered into the EGL surface. No-op while hidden
  // or while a frame is still pending.
  bool Present();

  // Bits per colour channel the plane actually got: 10 on a 10-bit unorm
  // config, otherwise 8. Read by MpvGlPlayer so mpv dithers to the plane's
  // real precision (`MPV_RENDER_PARAM_DEPTH`) instead of assuming 8.
  int depth_bits() const { return depth_bits_; }

  static constexpr int kFrameAckTimeoutMs = 500;
  static constexpr int kMaxConsecutiveFrameAckMisses = 5;

 private:
  bool BindGlobals(GdkDisplay* display, std::string* error);
  bool InitEgl(std::string* error);
  void RequestParentCommit();
  void ClearFrameCallback();
  void DetachBuffer();
  void ArmFrameAckWatchdog();
  void CancelFrameAckWatchdog();

  static void HandleFrameDone(void* data, wl_callback* callback, uint32_t time);

  GtkWidget* view_ = nullptr;

  wl_display* wl_display_ = nullptr;           // owned by GDK
  wl_compositor* compositor_ = nullptr;        // owned by GDK
  wl_subcompositor* subcompositor_ = nullptr;  // bound by us
  wl_surface* surface_ = nullptr;
  wl_subsurface* subsurface_ = nullptr;
  wl_egl_window* egl_window_ = nullptr;

  EGLDisplay egl_display_ = EGL_NO_DISPLAY;
  EGLConfig egl_config_ = nullptr;
  EGLSurface egl_surface_ = EGL_NO_SURFACE;

  int32_t x_ = 0;
  int32_t y_ = 0;
  int32_t width_ = 0;
  int32_t height_ = 0;
  int32_t scale_ = 1;
  int32_t scale_sent_ = 1;
  int32_t view_x_ = 0;
  int32_t view_y_ = 0;
  bool visible_ = false;
  bool rect_valid_ = false;
  bool first_frame_presented_ = false;
  bool frame_pending_ = false;
  wl_callback* frame_callback_ = nullptr;
  std::function<void()> on_frame_;

  guint frame_ack_source_ = 0;
  int consecutive_frame_acks_missed_ = 0;

  int depth_bits_ = 8;
};

}  // namespace m3u_tv_mpv_plane

#endif  // FLUTTER_CLIENT_LINUX_WAYLAND_VIDEO_SURFACE_H_
