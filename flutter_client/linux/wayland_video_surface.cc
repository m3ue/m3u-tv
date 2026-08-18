#include "wayland_video_surface.h"

#include <EGL/eglext.h>
#include <gdk/gdkwayland.h>
#include <wayland-client.h>
#include <wayland-egl.h>

#include <cstring>
#include <limits>

#include "plane_geometry.h"

namespace m3u_tv_mpv_plane {
namespace {

bool Fail(std::string* error, const char* message) {
  if (error) *error = message;
  return false;
}

// Scratch state for the registry listener only; the registry proxy is
// destroyed before BindGlobals returns.
struct RegistryTarget {
  wl_subcompositor* subcompositor = nullptr;
};

void RegistryGlobal(void* data, wl_registry* registry, uint32_t name, const char* interface, uint32_t version) {
  (void)version;
  auto* target = static_cast<RegistryTarget*>(data);
  if (g_strcmp0(interface, "wl_subcompositor") == 0 && target->subcompositor == nullptr) {
    target->subcompositor =
        static_cast<wl_subcompositor*>(wl_registry_bind(registry, name, &wl_subcompositor_interface, 1));
  }
}

void RegistryGlobalRemove(void* data, wl_registry* registry, uint32_t name) {
  (void)data;
  (void)registry;
  (void)name;
}

const wl_registry_listener kRegistryListener = {RegistryGlobal, RegistryGlobalRemove};

wl_surface* ParentSurface(GtkWidget* view) {
  GtkWidget* toplevel = gtk_widget_get_toplevel(view);
  if (toplevel == nullptr) return nullptr;
  GdkWindow* window = gtk_widget_get_window(toplevel);
  if (window == nullptr || !GDK_IS_WAYLAND_WINDOW(window)) return nullptr;
  return gdk_wayland_window_get_wl_surface(GDK_WAYLAND_WINDOW(window));
}

}  // namespace

WaylandVideoSurface::~WaylandVideoSurface() { Destroy(); }

bool WaylandVideoSurface::IsSupported(GdkDisplay* display) {
  return display != nullptr && GDK_IS_WAYLAND_DISPLAY(display);
}

bool WaylandVideoSurface::BindGlobals(GdkDisplay* display, std::string* error) {
  wl_display_ = gdk_wayland_display_get_wl_display(GDK_WAYLAND_DISPLAY(display));
  compositor_ = gdk_wayland_display_get_wl_compositor(GDK_WAYLAND_DISPLAY(display));
  if (wl_display_ == nullptr || compositor_ == nullptr) {
    return Fail(error, "Wayland display or compositor is unavailable");
  }

  // Bind on a private queue so the roundtrip cannot dispatch GDK's own events
  // from inside this call, then hand the bound global back to the default
  // queue that GDK's main-loop source already drives.
  wl_event_queue* queue = wl_display_create_queue(wl_display_);
  if (queue == nullptr) return Fail(error, "Failed to create a Wayland event queue");

  wl_registry* registry = wl_display_get_registry(wl_display_);
  if (registry == nullptr) {
    wl_event_queue_destroy(queue);
    return Fail(error, "Failed to obtain the Wayland registry");
  }
  wl_proxy_set_queue(reinterpret_cast<wl_proxy*>(registry), queue);

  RegistryTarget target;
  wl_registry_add_listener(registry, &kRegistryListener, &target);
  const bool round_tripped = wl_display_roundtrip_queue(wl_display_, queue) >= 0;
  wl_registry_destroy(registry);

  if (target.subcompositor != nullptr) {
    wl_proxy_set_queue(reinterpret_cast<wl_proxy*>(target.subcompositor), nullptr);
  }
  wl_event_queue_destroy(queue);

  if (!round_tripped) {
    if (target.subcompositor != nullptr) wl_subcompositor_destroy(target.subcompositor);
    return Fail(error, "Wayland roundtrip failed while binding globals");
  }
  if (target.subcompositor == nullptr) {
    return Fail(error, "Compositor does not expose wl_subcompositor");
  }

  subcompositor_ = target.subcompositor;
  return true;
}

bool WaylandVideoSurface::InitEgl(std::string* error) {
  // The plane's EGL stack is deliberately independent of Flutter's: nothing
  // is shared, so the context is free to pick whatever config renders best.
  egl_display_ = eglGetDisplay(reinterpret_cast<EGLNativeDisplayType>(wl_display_));
  if (egl_display_ == EGL_NO_DISPLAY) return Fail(error, "No EGL display for the Wayland connection");
  if (!eglInitialize(egl_display_, nullptr, nullptr)) {
    egl_display_ = EGL_NO_DISPLAY;
    return Fail(error, "eglInitialize failed for the video plane");
  }

  // Video is opaque, so no alpha channel is requested. Deepest first: PQ/10-
  // bit sources quantised to 8 bits band visibly, and while this phase does
  // not pass HDR metadata through, a 10-bit config still avoids unnecessary
  // banding on wide-gamut SDR content. 8 bits is the last resort.
  auto choose = [this](const EGLint* attributes) {
    EGLConfig config = nullptr;
    EGLint count = 0;
    if (eglChooseConfig(egl_display_, attributes, &config, 1, &count) && count == 1) {
      egl_config_ = config;
      return true;
    }
    return false;
  };
  for (const EGLint bits : {10, 8}) {
    for (const EGLint renderable : {EGL_OPENGL_ES3_BIT, EGL_OPENGL_ES2_BIT}) {
      const EGLint attributes[] = {
          EGL_SURFACE_TYPE, EGL_WINDOW_BIT,
          EGL_RENDERABLE_TYPE, renderable,
          EGL_RED_SIZE, bits,
          EGL_GREEN_SIZE, bits,
          EGL_BLUE_SIZE, bits,
          EGL_ALPHA_SIZE, 0,
          EGL_NONE,
      };
      if (choose(attributes)) {
        depth_bits_ = bits;
        return true;
      }
    }
  }
  return Fail(error, "No matching EGL config for the video plane");
}

bool WaylandVideoSurface::Create(GtkWidget* view, std::string* error) {
  if (view == nullptr) return Fail(error, "Video plane requires a realized view");
  GdkDisplay* display = gtk_widget_get_display(view);
  if (!IsSupported(display)) return Fail(error, "Not a Wayland display");

  wl_surface* parent = ParentSurface(view);
  if (parent == nullptr) return Fail(error, "Toplevel has no Wayland surface yet");

  view_ = view;
  if (!BindGlobals(display, error) || !InitEgl(error)) {
    Destroy();
    return false;
  }

  surface_ = wl_compositor_create_surface(compositor_);
  if (surface_ == nullptr) {
    Destroy();
    return Fail(error, "Failed to create the video wl_surface");
  }

  // Input belongs to the Flutter view, never to the video plane: an empty
  // input region routes pointer/touch straight through to the UI above.
  wl_region* empty = wl_compositor_create_region(compositor_);
  if (empty != nullptr) {
    wl_surface_set_input_region(surface_, empty);
    wl_region_destroy(empty);
  }

  // The plane carries opaque video; saying so lets the compositor skip
  // blending it. Clamped to the surface, so one maximal region outlives
  // every SetRect().
  wl_region* opaque = wl_compositor_create_region(compositor_);
  if (opaque != nullptr) {
    wl_region_add(opaque, 0, 0, std::numeric_limits<int32_t>::max(), std::numeric_limits<int32_t>::max());
    wl_surface_set_opaque_region(surface_, opaque);
    wl_region_destroy(opaque);
  }

  subsurface_ = wl_subcompositor_get_subsurface(subcompositor_, surface_, parent);
  if (subsurface_ == nullptr) {
    Destroy();
    return Fail(error, "Failed to create the video wl_subsurface");
  }
  wl_subsurface_place_below(subsurface_, parent);
  wl_subsurface_set_desync(subsurface_);

  // A 1x1 window keeps EGL happy until the first SetRect() arrives.
  egl_window_ = wl_egl_window_create(surface_, 1, 1);
  if (egl_window_ == nullptr) {
    Destroy();
    return Fail(error, "Failed to create the video wl_egl_window");
  }

  egl_surface_ =
      eglCreateWindowSurface(egl_display_, egl_config_, reinterpret_cast<EGLNativeWindowType>(egl_window_), nullptr);
  if (egl_surface_ == EGL_NO_SURFACE) {
    Destroy();
    return Fail(error, "Failed to create the video EGL surface");
  }

  g_message("MPV video plane: %d bits per channel (GPU render path)", depth_bits_);
  // Swap interval is set once a context is current -- see MpvGlPlayer's
  // render-context init in desktop_libmpv_backend.cc.
  return true;
}

void WaylandVideoSurface::Destroy() {
  CancelFrameAckWatchdog();
  if (egl_surface_ != EGL_NO_SURFACE) {
    if (eglGetCurrentSurface(EGL_DRAW) == egl_surface_ || eglGetCurrentSurface(EGL_READ) == egl_surface_) {
      eglMakeCurrent(egl_display_, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    }
    eglDestroySurface(egl_display_, egl_surface_);
    egl_surface_ = EGL_NO_SURFACE;
  }
  if (egl_window_ != nullptr) {
    wl_egl_window_destroy(egl_window_);
    egl_window_ = nullptr;
  }
  ClearFrameCallback();
  on_frame_ = nullptr;
  if (subsurface_ != nullptr) {
    wl_subsurface_destroy(subsurface_);
    subsurface_ = nullptr;
  }
  if (surface_ != nullptr) {
    wl_surface_destroy(surface_);
    surface_ = nullptr;
  }
  if (subcompositor_ != nullptr) {
    wl_subcompositor_destroy(subcompositor_);
    subcompositor_ = nullptr;
  }
  // compositor_, wl_display_ and the EGLDisplay are owned by GDK/EGL and
  // shared process-wide; only our own references are dropped here.
  compositor_ = nullptr;
  wl_display_ = nullptr;
  egl_config_ = nullptr;
  egl_display_ = EGL_NO_DISPLAY;
  view_ = nullptr;
  x_ = 0;
  y_ = 0;
  width_ = 0;
  height_ = 0;
  scale_ = 1;
  scale_sent_ = 1;
  visible_ = false;
  rect_valid_ = false;
  first_frame_presented_ = false;
  consecutive_frame_acks_missed_ = 0;
  depth_bits_ = 8;
}

void WaylandVideoSurface::RequestParentCommit() {
  // Subsurface position/stacking are double-buffered *parent* state: they
  // only land when the parent surface commits. Asking the view to redraw is
  // the one way to make GTK do that without reaching into its pending state.
  if (view_ != nullptr) gtk_widget_queue_draw(view_);
}

void WaylandVideoSurface::SetRect(int32_t x, int32_t y, int32_t width, int32_t height, int32_t scale) {
  scale = NormalizePlaneScale(scale);
  const bool was_valid = rect_valid_;
  rect_valid_ = width > 0 && height > 0;
  if (was_valid && !rect_valid_) DetachBuffer();

  width = PlaneBufferExtent(x, width, scale);
  height = PlaneBufferExtent(y, height, scale);

  int32_t view_x = 0;
  int32_t view_y = 0;
  if (view_ != nullptr) {
    GtkWidget* toplevel = gtk_widget_get_toplevel(view_);
    gint offset_x = 0;
    gint offset_y = 0;
    if (toplevel != nullptr && gtk_widget_translate_coordinates(view_, toplevel, 0, 0, &offset_x, &offset_y)) {
      view_x = offset_x;
      view_y = offset_y;
    }
  }
  if (x == x_ && y == y_ && width == width_ && height == height_ && scale == scale_ && view_x == view_x_ &&
      view_y == view_y_) {
    return;
  }

  const bool size_changed = width != width_ || height != height_;
  const bool scale_changed = scale != scale_;
  x_ = x;
  y_ = y;
  width_ = width;
  height_ = height;
  scale_ = scale;
  view_x_ = view_x;
  view_y_ = view_y;

  if (surface_ == nullptr || subsurface_ == nullptr || egl_window_ == nullptr) return;

  // A buffer_scale change must not reach the wire before the first frame is
  // presented: mesa commits the EGL surface's pre-allocated 1x1 back buffer
  // on the first swap regardless of wl_egl_window_resize, and a 1x1 buffer
  // at scale > 1 is a fatal protocol error.
  if (scale_changed && first_frame_presented_ && scale_ != scale_sent_) {
    wl_surface_set_buffer_scale(surface_, scale_);
    scale_sent_ = scale_;
  }
  if (size_changed || scale_changed) wl_egl_window_resize(egl_window_, width_, height_, 0, 0);
  wl_subsurface_set_position(
      subsurface_, PlaneSurfacePosition(x_, scale_, view_x_), PlaneSurfacePosition(y_, scale_, view_y_));
  RequestParentCommit();
}

void WaylandVideoSurface::DetachBuffer() {
  // The only way to take pixels off screen: a subsurface has no visibility
  // of its own, so "hidden" means "carrying no buffer".
  if (surface_ == nullptr) return;
  ClearFrameCallback();
  wl_surface_attach(surface_, nullptr, 0, 0);
  wl_surface_commit(surface_);
}

void WaylandVideoSurface::SetVisible(bool visible) {
  if (visible == visible_) return;
  visible_ = visible;
  if (surface_ == nullptr) return;
  if (!visible) DetachBuffer();
  RequestParentCommit();
}

void WaylandVideoSurface::ClearFrameCallback() {
  CancelFrameAckWatchdog();
  if (frame_callback_ != nullptr) {
    wl_callback_destroy(frame_callback_);
    frame_callback_ = nullptr;
  }
  frame_pending_ = false;
}

void WaylandVideoSurface::HandleFrameDone(void* data, wl_callback* callback, uint32_t time) {
  (void)time;
  auto* self = static_cast<WaylandVideoSurface*>(data);
  if (self->frame_callback_ == callback) {
    wl_callback_destroy(self->frame_callback_);
    self->frame_callback_ = nullptr;
  }
  self->frame_pending_ = false;
  self->consecutive_frame_acks_missed_ = 0;
  self->CancelFrameAckWatchdog();
  if (self->on_frame_) self->on_frame_();
}

void WaylandVideoSurface::ArmFrameAckWatchdog() {
  // Bounds the acknowledgement wait: a compositor is entitled to stop
  // acknowledging frames for an occluded/minimized surface, and
  // frame_pending_ is the only latch between Present() and the frame
  // callback -- without a bound, one missed wl_callback freezes the plane on
  // its last buffer for good.
  if (frame_ack_source_ != 0 || !frame_pending_ || !visible_) return;
  frame_ack_source_ = g_timeout_add(
      kFrameAckTimeoutMs,
      +[](gpointer data) -> gboolean {
        auto* self = static_cast<WaylandVideoSurface*>(data);
        self->frame_ack_source_ = 0;
        if (!self->frame_pending_) return G_SOURCE_REMOVE;
        self->ClearFrameCallback();
        if (++self->consecutive_frame_acks_missed_ > kMaxConsecutiveFrameAckMisses) {
          g_warning(
              "MPV video plane: compositor is not acknowledging frames (%d misses); "
              "stopping re-present attempts until a frame or visibility change",
              self->consecutive_frame_acks_missed_);
          return G_SOURCE_REMOVE;
        }
        g_message("MPV video plane: frame not acknowledged within %d ms; re-presenting", kFrameAckTimeoutMs);
        if (self->on_frame_) self->on_frame_();
        return G_SOURCE_REMOVE;
      },
      this);
}

void WaylandVideoSurface::CancelFrameAckWatchdog() {
  if (frame_ack_source_ != 0) {
    g_source_remove(frame_ack_source_);
    frame_ack_source_ = 0;
  }
}

bool WaylandVideoSurface::Present() {
  if (!visible_ || egl_surface_ == EGL_NO_SURFACE || frame_pending_) return false;

  static const wl_callback_listener kFrameListener = {HandleFrameDone};
  frame_callback_ = wl_surface_frame(surface_);
  if (frame_callback_ != nullptr) {
    wl_callback_add_listener(frame_callback_, &kFrameListener, this);
    frame_pending_ = true;
  }

  if (eglSwapBuffers(egl_display_, egl_surface_) != EGL_TRUE) {
    ClearFrameCallback();
    g_warning("MPV video plane: eglSwapBuffers failed: 0x%x", eglGetError());
    return false;
  }
  if (!first_frame_presented_) {
    first_frame_presented_ = true;
    if (scale_ != scale_sent_) {
      wl_surface_set_buffer_scale(surface_, scale_);
      scale_sent_ = scale_;
    }
    RequestParentCommit();
  }
  ArmFrameAckWatchdog();
  return true;
}

}  // namespace m3u_tv_mpv_plane
