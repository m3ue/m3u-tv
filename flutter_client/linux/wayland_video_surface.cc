#include "wayland_video_surface.h"

#include <EGL/eglext.h>
#include <gdk/gdkwayland.h>
#include <unistd.h>
#include <wayland-client.h>
#include <wayland-egl.h>

#include <cstring>
#include <limits>
#include <vector>

#include "plane_geometry.h"
#include "wayland/color-management-v1-client-protocol.h"

// Adapted from the open-source Plezy player's `wayland_video_surface.cc`
// (github.com/edde746/plezy, GPL-3.0, linux/runner/mpv/wayland_video_surface.cc).

namespace m3u_tv_mpv_plane {
namespace {

// The client understands up to this version of color-management-v1; KWin 6.4
// implements 1. Binding min(advertised, this) keeps newer compositors
// working without requiring them.
constexpr uint32_t kColorManagerMaxVersion = 3;

bool Fail(std::string* error, const char* message) {
  if (error) *error = message;
  return false;
}

// Scratch state for the registry listener only; the registry proxy is
// destroyed before BindGlobals returns.
struct RegistryTarget {
  wl_subcompositor* subcompositor = nullptr;
  wp_color_manager_v1* color_manager = nullptr;
};

void RegistryGlobal(void* data, wl_registry* registry, uint32_t name, const char* interface, uint32_t version) {
  auto* target = static_cast<RegistryTarget*>(data);
  if (g_strcmp0(interface, "wl_subcompositor") == 0 && target->subcompositor == nullptr) {
    target->subcompositor =
        static_cast<wl_subcompositor*>(wl_registry_bind(registry, name, &wl_subcompositor_interface, 1));
  } else if (g_strcmp0(interface, "wp_color_manager_v1") == 0 && target->color_manager == nullptr) {
    const uint32_t bind_version = version < kColorManagerMaxVersion ? version : kColorManagerMaxVersion;
    target->color_manager = static_cast<wp_color_manager_v1*>(
        wl_registry_bind(registry, name, &wp_color_manager_v1_interface, bind_version));
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

void WaylandVideoSurface::HandleManagerIntent(void* data, wp_color_manager_v1* manager, uint32_t intent) {
  (void)manager;
  // set_image_description raises the render_intent protocol error (fatal,
  // not a rejected description) for any intent the compositor did not
  // advertise here. Perceptual is the only one this plane ever asks for.
  if (intent == WP_COLOR_MANAGER_V1_RENDER_INTENT_PERCEPTUAL) {
    static_cast<WaylandVideoSurface*>(data)->manager_caps_.perceptual = true;
  }
}

void WaylandVideoSurface::HandleManagerFeature(void* data, wp_color_manager_v1* manager, uint32_t feature) {
  (void)manager;
  auto* self = static_cast<WaylandVideoSurface*>(data);
  if (feature == WP_COLOR_MANAGER_V1_FEATURE_PARAMETRIC) self->manager_caps_.parametric = true;
  if (feature == WP_COLOR_MANAGER_V1_FEATURE_SET_MASTERING_DISPLAY_PRIMARIES) {
    self->manager_caps_.mastering = true;
  }
  if (feature == WP_COLOR_MANAGER_V1_FEATURE_EXTENDED_TARGET_VOLUME) {
    self->manager_caps_.extended_target_volume = true;
  }
}

void WaylandVideoSurface::HandleManagerTransferFunction(void* data, wp_color_manager_v1* manager, uint32_t tf) {
  (void)manager;
  auto* self = static_cast<WaylandVideoSurface*>(data);
  if (tf == WP_COLOR_MANAGER_V1_TRANSFER_FUNCTION_ST2084_PQ) self->manager_caps_.pq = true;
  if (tf == WP_COLOR_MANAGER_V1_TRANSFER_FUNCTION_HLG) self->manager_caps_.hlg = true;
}

void WaylandVideoSurface::HandleManagerPrimaries(void* data, wp_color_manager_v1* manager, uint32_t primaries) {
  (void)manager;
  if (primaries == WP_COLOR_MANAGER_V1_PRIMARIES_BT2020) {
    static_cast<WaylandVideoSurface*>(data)->manager_caps_.bt2020 = true;
  }
}

void WaylandVideoSurface::HandleManagerDone(void* data, wp_color_manager_v1* manager) {
  (void)manager;
  static_cast<WaylandVideoSurface*>(data)->manager_caps_.done = true;
}

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
  // from inside this call, then hand the bound globals back to the default
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
  bool round_tripped = wl_display_roundtrip_queue(wl_display_, queue) >= 0;

  // The color manager reports what it supports right after binding, so a
  // second roundtrip is needed before those answers can be trusted. The
  // listener is given `this`, not the local target: the manager proxy is
  // kept for the life of the plane and a burst still in flight when the loop
  // below gives up must not be dispatched into a dead stack frame once
  // GDK's queue picks it up.
  if (round_tripped && target.color_manager != nullptr) {
    static_assert(
        sizeof(wp_color_manager_v1_listener) == 5 * sizeof(void (*)()),
        "wp_color_manager_v1_listener gained an event; handle it here");
    static const wp_color_manager_v1_listener kManagerListener = {
        HandleManagerIntent,    HandleManagerFeature, HandleManagerTransferFunction,
        HandleManagerPrimaries, HandleManagerDone,
    };
    wp_color_manager_v1_add_listener(target.color_manager, &kManagerListener, this);
    for (int attempt = 0; attempt < kBootstrapRoundtrips && !manager_caps_.done; ++attempt) {
      if (wl_display_roundtrip_queue(wl_display_, queue) < 0) {
        round_tripped = false;
        break;
      }
    }
  }

  wl_registry_destroy(registry);

  // Both globals were bound from a registry on `queue`, so they must be
  // moved off before it is destroyed: libwayland >= 1.22 warns that a queue
  // was destroyed with proxies still attached and nulls their queue
  // pointer, and a proxy with no queue is a null dereference the moment
  // anything is dispatched for it.
  if (target.subcompositor != nullptr) {
    wl_proxy_set_queue(reinterpret_cast<wl_proxy*>(target.subcompositor), nullptr);
  }
  if (target.color_manager != nullptr) {
    wl_proxy_set_queue(reinterpret_cast<wl_proxy*>(target.color_manager), nullptr);
  }
  wl_event_queue_destroy(queue);

  // Every failure below has to release both globals itself; they are not yet
  // owned by a member, so Destroy() would not see them.
  auto abandon = [&](const char* message) {
    if (target.color_manager != nullptr) wp_color_manager_v1_destroy(target.color_manager);
    if (target.subcompositor != nullptr) wl_subcompositor_destroy(target.subcompositor);
    manager_caps_ = ManagerCaps{};
    return Fail(error, message);
  };
  if (!round_tripped) return abandon("Wayland roundtrip failed while binding globals");
  if (target.subcompositor == nullptr) return abandon("Compositor does not expose wl_subcompositor");

  subcompositor_ = target.subcompositor;

  if (target.color_manager != nullptr) {
    color_manager_ = target.color_manager;
    supports_pq_ = manager_caps_.pq;
    supports_hlg_ = manager_caps_.hlg;
    supports_bt2020_ = manager_caps_.bt2020;
    // BT.2020, at least one HDR curve, a parametric creator, and the
    // perceptual rendering intent. Either curve will do here; which one a
    // given source needs is checked per source by CanDescribeSource().
    supports_hdr_ = manager_caps_.done && manager_caps_.parametric && manager_caps_.perceptual &&
                    manager_caps_.bt2020 && (manager_caps_.pq || manager_caps_.hlg);
    luminance_support_.mastering = manager_caps_.mastering;
    luminance_support_.extended_target_volume = manager_caps_.extended_target_volume;
    luminance_support_.interface_version = wp_color_manager_v1_get_version(color_manager_);
    if (!supports_hdr_) {
      g_message(
          "MPV video plane: compositor color management is incomplete "
          "(parametric=%d perceptual=%d pq=%d hlg=%d bt2020=%d); HDR passthrough unavailable",
          manager_caps_.parametric, manager_caps_.perceptual, manager_caps_.pq, manager_caps_.hlg,
          manager_caps_.bt2020);
    }
  }
  return true;
}

bool WaylandVideoSurface::InitEgl(std::string* error) {
  // The plane's EGL stack is deliberately independent of Flutter's: nothing
  // is shared, so the context is free to be ES 3.x and to pick a deep config.
  egl_display_ = eglGetDisplay(reinterpret_cast<EGLNativeDisplayType>(wl_display_));
  if (egl_display_ == EGL_NO_DISPLAY) return Fail(error, "No EGL display for the Wayland connection");
  if (!eglInitialize(egl_display_, nullptr, nullptr)) {
    egl_display_ = EGL_NO_DISPLAY;
    return Fail(error, "eglInitialize failed for the video plane");
  }

  // Video is opaque, so no alpha channel is requested for the unorm tiers. A
  // config that carries one anyway (the fp16 tier -- no driver offers an
  // alpha-less half-float config) is still fine: Create() declares the whole
  // surface opaque, so the compositor never reads the alpha channel.
  //
  // Deepest first, because PQ quantised to 8 bits bands visibly. The middle
  // tier exists for NVIDIA: its Wayland EGL exposes no 10-bit unorm window
  // configs at all -- only 8-bit unorm and half-float. fp16 exceeds 10-bit
  // precision at twice the bandwidth, so it ranks between the two unorm
  // tiers rather than first. 8 bits is the last resort and means HDR stays
  // off.
  const char* extensions = eglQueryString(egl_display_, EGL_EXTENSIONS);
  const bool has_float_configs = extensions != nullptr && strstr(extensions, "EGL_EXT_pixel_format_float") != nullptr;
  auto choose = [this](const EGLint* attributes) {
    EGLConfig config = nullptr;
    EGLint count = 0;
    if (eglChooseConfig(egl_display_, attributes, &config, 1, &count) && count == 1) {
      egl_config_ = config;
      return true;
    }
    return false;
  };
  struct ConfigTier {
    EGLint bits;    // per-channel size requested, and the depth then reported
    bool floating;  // half-float rather than unorm
  };
  for (const ConfigTier tier : std::vector<ConfigTier>{{10, false}, {16, true}, {8, false}}) {
    if (tier.floating && !has_float_configs) continue;
    for (const EGLint renderable : {EGL_OPENGL_ES3_BIT, EGL_OPENGL_ES2_BIT}) {
      const EGLint attributes[] = {
          EGL_SURFACE_TYPE,
          EGL_WINDOW_BIT,
          EGL_RENDERABLE_TYPE,
          renderable,
          EGL_RED_SIZE,
          tier.bits,
          EGL_GREEN_SIZE,
          tier.bits,
          EGL_BLUE_SIZE,
          tier.bits,
          // Asking for zero alpha would reject every half-float config, since
          // no driver offers an alpha-less one.
          tier.floating ? EGL_COLOR_COMPONENT_TYPE_EXT : EGL_ALPHA_SIZE,
          tier.floating ? EGL_COLOR_COMPONENT_TYPE_FLOAT_EXT : 0,
          EGL_NONE,
      };
      if (choose(attributes)) {
        depth_bits_ = tier.bits;
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

  // Swap interval is set once a context is current -- see the GPU render
  // context init in desktop_libmpv_backend.cc.

  if (color_manager_ != nullptr) {
    color_surface_ = wp_color_manager_v1_get_surface(color_manager_, surface_);
  }
  // PQ in 8 bits bands badly enough to be worse than tone-mapping to SDR, so
  // HDR is only offered when the plane actually got a deep config (10-bit
  // unorm or fp16).
  if (supports_hdr_ && (color_surface_ == nullptr || depth_bits_ < 10)) {
    supports_hdr_ = false;
    g_message(
        "MPV video plane: HDR unavailable (color surface=%p, depth=%d bits)", static_cast<void*>(color_surface_),
        depth_bits_);
  }
  g_message("MPV video plane: %d bits per channel, HDR %s", depth_bits_, supports_hdr_ ? "available" : "unavailable");

  // Feedback tells us what the compositor would prefer for this surface,
  // which is the only channel that reveals the output's real peak luminance
  // and whether it is in HDR at all. Bootstrapped synchronously on a private
  // queue so callers see a populated answer as soon as Create returns, then
  // handed to the default queue that GDK drives so later preferred_changed
  // events keep arriving.
  if (supports_hdr_) {
    static_assert(
        sizeof(wp_color_management_surface_feedback_v1_listener) == 2 * sizeof(void (*)()),
        "wp_color_management_surface_feedback_v1_listener gained an event");
    static const wp_color_management_surface_feedback_v1_listener kFeedbackListener = {
        HandlePreferredChanged,
        HandlePreferredChanged2,
    };
    wl_event_queue* queue = wl_display_create_queue(wl_display_);
    color_feedback_ = wp_color_manager_v1_get_surface_feedback(color_manager_, surface_);
    if (color_feedback_ != nullptr) {
      wp_color_management_surface_feedback_v1_add_listener(color_feedback_, &kFeedbackListener, this);
      if (queue != nullptr) {
        wl_proxy_set_queue(reinterpret_cast<wl_proxy*>(color_feedback_), queue);
        BeginPreferredQuery();
        for (int attempt = 0; attempt < kBootstrapRoundtrips && !preferred_.valid; ++attempt) {
          if (wl_display_roundtrip_queue(wl_display_, queue) < 0) break;
        }
        // The description and info proxies must not outlive the queue they
        // were created on, so whatever is still in flight is abandoned here
        // and retried below on the default queue. Keyed on there being an
        // outstanding query rather than on preferred_ being invalid: a
        // preferred_changed dispatched in the same batch that completed the
        // first query re-arms BeginPreferredQuery on this queue after the
        // loop's condition has already gone false, so a validity test alone
        // would see the first, superseded answer and skip the retry.
        const bool query_outstanding = preferred_description_ != nullptr;
        ClearPreferredQuery();
        wl_proxy_set_queue(reinterpret_cast<wl_proxy*>(color_feedback_), nullptr);
        if (!preferred_.valid || query_outstanding) BeginPreferredQuery();
      } else {
        BeginPreferredQuery();
      }
    }
    if (queue != nullptr) wl_event_queue_destroy(queue);
    g_message("MPV video plane: output is %s", output_is_hdr() ? "in HDR" : "SDR or unknown");
  }

  RequestParentCommit();
  return true;
}

void WaylandVideoSurface::ClearPreferredQuery() {
  if (preferred_info_ != nullptr) {
    wp_image_description_info_v1_destroy(preferred_info_);
    preferred_info_ = nullptr;
  }
  if (preferred_description_ != nullptr) {
    wp_image_description_v1_destroy(preferred_description_);
    preferred_description_ = nullptr;
  }
}

void WaylandVideoSurface::BeginPreferredQuery() {
  if (color_feedback_ == nullptr) return;
  // The protocol asks clients to stop using descriptions from earlier
  // invocations, so a query in flight is abandoned rather than raced.
  ClearPreferredQuery();
  pending_preferred_ = PreferredColorDescription();

  static_assert(
      sizeof(wp_image_description_v1_listener) == 3 * sizeof(void (*)()),
      "wp_image_description_v1_listener gained an event; handle it here");
  static const wp_image_description_v1_listener kPreferredListener = {
      HandlePreferredFailed,
      HandlePreferredReady,
      HandlePreferredReady2,
  };
  // get_preferred_parametric rather than get_preferred: only parameters can
  // be read here, and an ICC-based preferred description would tell us
  // nothing. Gated on the parametric feature, which supports_hdr_ already
  // implies.
  preferred_description_ = wp_color_management_surface_feedback_v1_get_preferred_parametric(color_feedback_);
  if (preferred_description_ == nullptr) return;
  wp_image_description_v1_add_listener(preferred_description_, &kPreferredListener, this);
}

void WaylandVideoSurface::CommitPreferredQuery() {
  pending_preferred_.valid = true;
  const bool changed = preferred_.valid != pending_preferred_.valid || preferred_.pq != pending_preferred_.pq ||
                       preferred_.bt2020 != pending_preferred_.bt2020 ||
                       preferred_.max_luminance != pending_preferred_.max_luminance ||
                       preferred_.min_luminance_scaled != pending_preferred_.min_luminance_scaled ||
                       preferred_.reference_luminance != pending_preferred_.reference_luminance;
  preferred_ = pending_preferred_;
  ClearPreferredQuery();
  g_message(
      "MPV video plane: compositor prefers %s / %s, target %u nits (floor %.4f), reference %u nits",
      preferred_.pq ? "PQ" : "non-PQ", preferred_.bt2020 ? "BT.2020" : "non-BT.2020", preferred_.max_luminance,
      static_cast<double>(preferred_.min_luminance_scaled) / kMinLuminanceScale, preferred_.reference_luminance);
  if (changed && on_preferred_changed_) on_preferred_changed_();
}

void WaylandVideoSurface::HandlePreferredChanged(
    void* data, wp_color_management_surface_feedback_v1* feedback, uint32_t identity) {
  (void)feedback;
  (void)identity;
  static_cast<WaylandVideoSurface*>(data)->BeginPreferredQuery();
}

void WaylandVideoSurface::HandlePreferredChanged2(
    void* data, wp_color_management_surface_feedback_v1* feedback, uint32_t identity_hi, uint32_t identity_lo) {
  (void)identity_hi;
  (void)identity_lo;
  HandlePreferredChanged(data, feedback, 0);
}

void WaylandVideoSurface::HandlePreferredReady(void* data, wp_image_description_v1* desc, uint32_t identity) {
  (void)identity;
  auto* self = static_cast<WaylandVideoSurface*>(data);
  if (self->preferred_description_ != desc) return;
  self->preferred_info_ = wp_image_description_v1_get_information(desc);
  if (self->preferred_info_ == nullptr) return;
  static_assert(
      sizeof(wp_image_description_info_v1_listener) == 11 * sizeof(void (*)()),
      "wp_image_description_info_v1_listener gained an event; handle it here");
  static const wp_image_description_info_v1_listener kInfoListener = {
      HandleInfoDone,           HandleInfoIccFile,         HandleInfoPrimaries,
      HandleInfoPrimariesNamed, HandleInfoTfPower,         HandleInfoTfNamed,
      HandleInfoLuminances,     HandleInfoTargetPrimaries, HandleInfoTargetLuminance,
      HandleInfoTargetMaxCll,   HandleInfoTargetMaxFall,
  };
  wp_image_description_info_v1_add_listener(self->preferred_info_, &kInfoListener, self);
}

void WaylandVideoSurface::HandlePreferredReady2(
    void* data, wp_image_description_v1* desc, uint32_t identity_hi, uint32_t identity_lo) {
  (void)identity_hi;
  (void)identity_lo;
  HandlePreferredReady(data, desc, 0);
}

void WaylandVideoSurface::HandlePreferredFailed(
    void* data, wp_image_description_v1* desc, uint32_t cause, const char* message) {
  auto* self = static_cast<WaylandVideoSurface*>(data);
  if (self->preferred_description_ != desc) return;
  g_message(
      "MPV video plane: no preferred color description (cause %u): %s", cause, message ? message : "no reason given");
  const bool had_preference = self->preferred_.valid;
  self->ClearPreferredQuery();
  self->preferred_ = PreferredColorDescription();
  if (had_preference && self->on_preferred_changed_) self->on_preferred_changed_();
}

void WaylandVideoSurface::HandleInfoDone(void* data, wp_image_description_info_v1* info) {
  auto* self = static_cast<WaylandVideoSurface*>(data);
  if (self->preferred_info_ != info) return;
  self->CommitPreferredQuery();
}

void WaylandVideoSurface::HandleInfoTfNamed(void* data, wp_image_description_info_v1* info, uint32_t tf) {
  (void)info;
  auto* self = static_cast<WaylandVideoSurface*>(data);
  self->pending_preferred_.pq = tf == WP_COLOR_MANAGER_V1_TRANSFER_FUNCTION_ST2084_PQ;
}

void WaylandVideoSurface::HandleInfoPrimariesNamed(void* data, wp_image_description_info_v1* info, uint32_t primaries) {
  (void)info;
  auto* self = static_cast<WaylandVideoSurface*>(data);
  self->pending_preferred_.bt2020 = primaries == WP_COLOR_MANAGER_V1_PRIMARIES_BT2020;
}

void WaylandVideoSurface::HandleInfoLuminances(
    void* data, wp_image_description_info_v1* info, uint32_t min_lum, uint32_t max_lum, uint32_t reference_lum) {
  (void)info;
  (void)min_lum;
  (void)max_lum;
  // These describe the transfer function's own encodable range (for PQ
  // always 0.005 to 10000), so only the reference is informative -- the
  // panel's actual peak arrives in target_luminance instead.
  static_cast<WaylandVideoSurface*>(data)->pending_preferred_.reference_luminance = reference_lum;
}

void WaylandVideoSurface::HandleInfoTargetLuminance(
    void* data, wp_image_description_info_v1* info, uint32_t min_lum, uint32_t max_lum) {
  (void)info;
  auto* self = static_cast<WaylandVideoSurface*>(data);
  self->pending_preferred_.min_luminance_scaled = min_lum;
  self->pending_preferred_.max_luminance = max_lum;
}

void WaylandVideoSurface::HandleInfoIccFile(
    void* data, wp_image_description_info_v1* info, int32_t icc, uint32_t icc_size) {
  (void)data;
  (void)info;
  (void)icc_size;
  // The fd is ours once received; leaking it would exhaust the process's
  // fds over repeated monitor changes.
  if (icc >= 0) close(icc);
}

// Events the plane has no use for. Present rather than omitted: every member
// of the listener struct must be filled in, see the static_assert beside it.
void WaylandVideoSurface::HandleInfoPrimaries(
    void* data, wp_image_description_info_v1* info, int32_t r_x, int32_t r_y, int32_t g_x, int32_t g_y, int32_t b_x,
    int32_t b_y, int32_t w_x, int32_t w_y) {
  (void)data;
  (void)info;
  (void)r_x;
  (void)r_y;
  (void)g_x;
  (void)g_y;
  (void)b_x;
  (void)b_y;
  (void)w_x;
  (void)w_y;
}

void WaylandVideoSurface::HandleInfoTfPower(void* data, wp_image_description_info_v1* info, uint32_t eexp) {
  (void)data;
  (void)info;
  (void)eexp;
}

void WaylandVideoSurface::HandleInfoTargetPrimaries(
    void* data, wp_image_description_info_v1* info, int32_t r_x, int32_t r_y, int32_t g_x, int32_t g_y, int32_t b_x,
    int32_t b_y, int32_t w_x, int32_t w_y) {
  (void)data;
  (void)info;
  (void)r_x;
  (void)r_y;
  (void)g_x;
  (void)g_y;
  (void)b_x;
  (void)b_y;
  (void)w_x;
  (void)w_y;
}

void WaylandVideoSurface::HandleInfoTargetMaxCll(void* data, wp_image_description_info_v1* info, uint32_t max_cll) {
  (void)data;
  (void)info;
  (void)max_cll;
}

void WaylandVideoSurface::HandleInfoTargetMaxFall(void* data, wp_image_description_info_v1* info, uint32_t max_fall) {
  (void)data;
  (void)info;
  (void)max_fall;
}

void WaylandVideoSurface::ClearStagedDescription() {
  if (staged_description_ != nullptr) {
    wp_image_description_v1_destroy(staged_description_);
    staged_description_ = nullptr;
  }
}

void WaylandVideoSurface::SettleTransition(bool ok) {
  if (!transition_staged_) return;
  // Re-armed, not cancelled: the compositor answering only ends the *first*
  // of two waits. The plane stays staged -- and Present() stays held --
  // until the caller's mpv leg commits or aborts, which is a longer wait
  // than this one and has no timeout of its own.
  ArmTransitionWatchdog();
  // Moved out first: the callback is entitled to start the next transition,
  // and it must not be running out of a member this object may reassign
  // underneath it.
  auto settled = std::move(on_transition_settled_);
  on_transition_settled_ = nullptr;
  if (settled) settled(transition_token_, ok);
}

void WaylandVideoSurface::HandleImageDescriptionReady(void* data, wp_image_description_v1* desc, uint32_t identity) {
  (void)identity;
  auto* self = static_cast<WaylandVideoSurface*>(data);
  if (self->staged_description_ != desc) return;
  self->SettleTransition(true);
}

void WaylandVideoSurface::HandleImageDescriptionReady2(
    void* data, wp_image_description_v1* desc, uint32_t identity_hi, uint32_t identity_lo) {
  (void)identity_hi;
  (void)identity_lo;
  HandleImageDescriptionReady(data, desc, 0);
}

void WaylandVideoSurface::HandleImageDescriptionFailed(
    void* data, wp_image_description_v1* desc, uint32_t cause, const char* message) {
  auto* self = static_cast<WaylandVideoSurface*>(data);
  if (self->staged_description_ != desc) return;
  g_warning(
      "MPV video plane: compositor rejected the HDR image description (cause %u): %s", cause,
      message ? message : "no reason given");
  self->SettleTransition(false);
}

bool WaylandVideoSurface::CanDescribeSource(const HdrMetadata& metadata) const {
  return SourceIsDescribable(metadata, {supports_bt2020_, supports_pq_, supports_hlg_});
}

void WaylandVideoSurface::BeginHdrTransition(
    bool describe, const HdrMetadata& metadata, std::function<void(uint64_t, bool)> on_settled) {
  // The two hard capabilities are facts about this surface rather than
  // policy, so they are checked here even though the caller's HdrDecision
  // has already weighed everything else.
  if (!supports_hdr_ || color_surface_ == nullptr) {
    if (on_settled) on_settled(0, !describe);
    return;
  }
  // One at a time; the caller serializes them. Superseding here cannot be
  // made safe: the displaced waiter is told synchronously, and anything it
  // stages in response would be clobbered as this call continues.
  if (transition_staged_) {
    if (on_settled) on_settled(0, false);
    return;
  }

  // Metadata matters only while described; otherwise every SDR source
  // change would stage a no-op transition that holds Present() and forces a
  // render.
  if (describe == hdr_active_ && (!describe || metadata_ == metadata)) {
    if (on_settled) on_settled(0, true);
    return;
  }

  transition_staged_ = true;
  transition_token_ += 1;
  staged_describe_ = describe;
  staged_metadata_ = metadata;
  on_transition_settled_ = std::move(on_settled);

  if (!describe) {
    // Unsetting needs no validation, so it is settled at once; the request
    // itself is deferred to Commit so it still lands on the same commit as
    // the first buffer mpv renders in the new color space.
    SettleTransition(true);
    return;
  }
  ArmTransitionWatchdog();
  BuildImageDescription();
}

// Present() is held while a transition is staged, so a compositor that
// accepts create() and then answers with neither ready nor failed freezes
// the plane on its last buffer for good. Everything else in this file that
// waits on the compositor is bounded; this is the one place that was not.
void WaylandVideoSurface::ArmTransitionWatchdog() {
  CancelTransitionWatchdog();
  watchdog_source_ = g_timeout_add_seconds(
      kTransitionTimeoutSeconds,
      +[](gpointer data) -> gboolean {
        auto* self = static_cast<WaylandVideoSurface*>(data);
        self->watchdog_source_ = 0;
        // Every path out of the staged state cancels the watchdog first, so
        // reaching here means somebody went silent. Which one is still owed
        // an answer says which:
        if (!self->transition_staged_) return G_SOURCE_REMOVE;
        if (self->on_transition_settled_) {
          // Nothing has consumed the callback, so the compositor never
          // answered the description at all.
          g_warning(
              "MPV video plane: the compositor never answered the image description; "
              "abandoning the color transition after %d seconds",
              kTransitionTimeoutSeconds);
          self->SettleTransition(false);
          return G_SOURCE_REMOVE;
        }
        // The compositor answered and the caller took the callback, but
        // never came back to commit or abort -- the caller's own mpv leg
        // stopped answering. Only unstage: the description *committed*
        // right now is the one the pixels on screen were rendered under and
        // stays true precisely because the caller has not finished moving
        // off that color space.
        g_warning(
            "MPV video plane: the color transition was never committed; "
            "resuming presentation on the description already in force after %d seconds",
            kTransitionTimeoutSeconds);
        self->DiscardTransition();
        if (self->on_forced_render_) self->on_forced_render_();
        return G_SOURCE_REMOVE;
      },
      this);
}

void WaylandVideoSurface::CancelTransitionWatchdog() {
  if (watchdog_source_ != 0) {
    g_source_remove(watchdog_source_);
    watchdog_source_ = 0;
  }
}

bool WaylandVideoSurface::CommitHdrTransition(uint64_t token) {
  // A stale token means the transition was torn down (teardown, or a forced
  // undescribe) while its caller's mpv request was still in flight.
  // Committing then would attach a description the plane no longer has
  // pixels for. Token zero is the "nothing was staged" case.
  if (!transition_staged_ || token == 0 || token != transition_token_) return false;
  CancelTransitionWatchdog();

  const bool describe = staged_describe_;

  if (describe) {
    if (staged_description_ == nullptr) {
      DiscardTransition();
      return false;
    }
    // Copies (see staged_description_), so the surface's pending state
    // carries the description from here until the next commit.
    wp_color_management_surface_v1_set_image_description(
        color_surface_, staged_description_, WP_COLOR_MANAGER_V1_RENDER_INTENT_PERCEPTUAL);
    hdr_active_ = true;
    // Promoted here and nowhere earlier: this is the record BeginHdrTransition
    // compares a new request against to skip an identical one, so it has to
    // name a description that was actually attached.
    metadata_ = staged_metadata_;
    g_message("MPV video plane: image description attached");
  } else if (hdr_active_) {
    wp_color_management_surface_v1_unset_image_description(color_surface_);
    hdr_active_ = false;
    metadata_ = HdrMetadata();
    g_message("MPV video plane: image description cleared");
  }

  ClearStagedDescription();
  transition_staged_ = false;
  on_transition_settled_ = nullptr;

  // The color state is now pending on the child surface and lands on its
  // next commit, which only eglSwapBuffers performs. Telling the caller to
  // render and present now is what makes the pairing atomic.
  return true;
}

void WaylandVideoSurface::AbortHdrTransition(uint64_t token) {
  if (!transition_staged_ || token == 0 || token != transition_token_) return;
  DiscardTransition();
}

void WaylandVideoSurface::DiscardTransition() {
  if (!transition_staged_) return;
  CancelTransitionWatchdog();
  // The callback is moved out and the state torn down *before* it is
  // invoked, so a handler that aborts again finds nothing staged.
  auto displaced = std::move(on_transition_settled_);
  const uint64_t token = transition_token_;
  on_transition_settled_ = nullptr;
  ClearStagedDescription();
  transition_staged_ = false;
  if (displaced) displaced(token, false);
}

bool WaylandVideoSurface::ForceUndescribed() {
  DiscardTransition();
  if (color_surface_ == nullptr || !hdr_active_) {
    return false;
  }
  wp_color_management_surface_v1_unset_image_description(color_surface_);
  hdr_active_ = false;
  metadata_ = HdrMetadata();
  g_warning("MPV video plane: description withdrawn, output color space had to be forced to SDR");
  return true;
}

void WaylandVideoSurface::BuildImageDescription() {
  // The staged metadata, not the committed one: this description belongs to
  // the transition being validated, and metadata_ only moves when it commits.
  const HdrMetadata& metadata = staged_metadata_;
  wp_image_description_creator_params_v1* creator = wp_color_manager_v1_create_parametric_creator(color_manager_);
  if (creator == nullptr) {
    g_warning("MPV video plane: compositor refused a parametric image-description creator");
    SettleTransition(false);
    return;
  }

  // Describe the source's own curve and gamut, never a fixed PQ / BT.2020.
  // Both arms below assume CanDescribeSource() already accepted this
  // source, so an SDR transfer cannot reach here.
  wp_image_description_creator_params_v1_set_tf_named(
      creator, metadata.transfer == SourceTransfer::kHlg ? WP_COLOR_MANAGER_V1_TRANSFER_FUNCTION_HLG
                                                         : WP_COLOR_MANAGER_V1_TRANSFER_FUNCTION_ST2084_PQ);
  wp_image_description_creator_params_v1_set_primaries_named(creator, WP_COLOR_MANAGER_V1_PRIMARIES_BT2020);

  // Only forward metadata the source actually carried, and only in a
  // combination the protocol accepts -- every luminance rule here is a
  // protocol *error* on create(), so a badly authored file would disconnect
  // the whole client rather than merely fail the description.
  const HdrLuminancePlan plan = PlanHdrLuminance(metadata, luminance_support_);
  if (plan.send_mastering) {
    wp_image_description_creator_params_v1_set_mastering_luminance(
        creator, plan.mastering_min_scaled, plan.mastering_max);
  }
  if (plan.send_max_cll) {
    wp_image_description_creator_params_v1_set_max_cll(creator, plan.max_cll);
  }
  if (plan.send_max_fall) {
    wp_image_description_creator_params_v1_set_max_fall(creator, plan.max_fall);
  }
  if (plan.send_max_cll != (metadata.max_cll > 0) || plan.send_max_fall != (metadata.max_fall > 0)) {
    g_message(
        "MPV video plane: dropped source light levels the protocol would reject "
        "(MaxCLL %u kept=%d, MaxFALL %u kept=%d, mastering max %u kept=%d)",
        metadata.max_cll, plan.send_max_cll, metadata.max_fall, plan.send_max_fall, plan.mastering_max,
        plan.send_mastering);
  }

  // Every member must be filled in: libwayland calls implementation[opcode]
  // through libffi with no null check, so a listener short by one member is
  // a segfault on the first compositor that sends that event.
  static_assert(
      sizeof(wp_image_description_v1_listener) == 3 * sizeof(void (*)()),
      "wp_image_description_v1_listener gained an event; handle it below");
  static const wp_image_description_v1_listener kDescriptionListener = {
      HandleImageDescriptionFailed,
      HandleImageDescriptionReady,
      HandleImageDescriptionReady2,
  };
  // create() consumes the creator, so it must not be destroyed afterwards.
  staged_description_ = wp_image_description_creator_params_v1_create(creator);
  if (staged_description_ == nullptr) {
    g_warning("MPV video plane: could not create the HDR image description");
    SettleTransition(false);
    return;
  }
  wp_image_description_v1_add_listener(staged_description_, &kDescriptionListener, this);
}

void WaylandVideoSurface::Destroy() {
  // Unconditionally, ahead of everything: both timeout closures capture
  // `this`.
  CancelTransitionWatchdog();
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
  on_forced_render_ = nullptr;
  // Drops the staged description and, importantly, the settled callback: it
  // captures the caller, which is being torn down alongside this.
  DiscardTransition();
  // Before the color surface and manager: these are children of the manager
  // and reference the wl_surface.
  ClearPreferredQuery();
  on_preferred_changed_ = nullptr;
  if (color_feedback_ != nullptr) {
    wp_color_management_surface_feedback_v1_destroy(color_feedback_);
    color_feedback_ = nullptr;
  }
  preferred_ = PreferredColorDescription();
  pending_preferred_ = PreferredColorDescription();
  if (color_surface_ != nullptr) {
    wp_color_management_surface_v1_destroy(color_surface_);
    color_surface_ = nullptr;
  }
  if (color_manager_ != nullptr) {
    wp_color_manager_v1_destroy(color_manager_);
    color_manager_ = nullptr;
  }
  // Every advertised capability, not just the aggregate: CanDescribeSource()
  // reads the per-curve flags directly, and a partial recreate would
  // otherwise consult what the *previous* compositor connection offered.
  supports_hdr_ = false;
  supports_pq_ = false;
  supports_hlg_ = false;
  supports_bt2020_ = false;
  luminance_support_ = CompositorLuminanceSupport();
  manager_caps_ = ManagerCaps();
  hdr_active_ = false;
  metadata_ = HdrMetadata();
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
  view_x_ = 0;
  view_y_ = 0;
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
  // Held while a color transition is staged. eglSwapBuffers is the child
  // surface's commit, so presenting now would publish a buffer paired with a
  // color state it was not rendered for -- the flash this two-phase dance
  // exists to avoid.
  if (transition_staged_) return false;

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
