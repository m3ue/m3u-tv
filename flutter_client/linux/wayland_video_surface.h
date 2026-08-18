#ifndef FLUTTER_CLIENT_LINUX_WAYLAND_VIDEO_SURFACE_H_
#define FLUTTER_CLIENT_LINUX_WAYLAND_VIDEO_SURFACE_H_

#include <EGL/egl.h>
#include <gtk/gtk.h>

#include <cstdint>
#include <functional>
#include <string>

#include "hdr_metadata.h"

struct wl_callback;
struct wl_compositor;
struct wl_display;
struct wl_egl_window;
struct wl_subcompositor;
struct wl_subsurface;
struct wl_surface;
struct wp_color_management_surface_v1;
struct wp_color_management_surface_feedback_v1;
struct wp_color_manager_v1;
struct wp_image_description_v1;
struct wp_image_description_info_v1;

namespace m3u_tv_mpv_plane {

// The compositor's preferred color encoding for a surface, as delivered by
// wp_image_description_info_v1 in response to get_information.
//
// Only the fields that matter for video are kept. The important one is
// max_luminance: it is the output's *target* peak (KWin sources it from an
// HDR peak override, else the EDID's desired maximum, else 800 nits), which
// is the number a player needs if it is going to tone-map for the display
// itself. Nothing else in the protocol reveals it -- PQ's own encoded
// maximum is always 10000 regardless of the panel.
struct PreferredColorDescription {
  bool valid = false;                 // a complete info burst has arrived
  bool pq = false;                    // transfer function is ST2084 PQ
  bool bt2020 = false;                // container primaries are BT.2020
  uint32_t max_luminance = 0;         // nits, the output's target peak
  uint32_t min_luminance_scaled = 0;  // nits * 10000, the output's target floor
  uint32_t reference_luminance = 0;   // nits, diffuse/SDR white
};

// A native Wayland video plane: a wl_subsurface stacked *below* the Flutter
// toplevel surface, carrying its own EGL window surface that mpv renders
// into directly via the OpenGL render API, plus (when the compositor
// supports it) a wp_color_manager_v1-described HDR image description.
//
// Adapted from the open-source Plezy player's `WaylandVideoSurface`
// (github.com/edde746/plezy, GPL-3.0, linux/runner/mpv/wayland_video_surface.h).
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

  // Invoked when the plane needs a frame *now* independent of the ordinary
  // frame callback -- used to resume presenting after an HDR transition the
  // watchdog abandoned, where nothing else will prompt a re-render.
  void SetForcedRenderCallback(std::function<void()> callback) { on_forced_render_ = std::move(callback); }

  // Presents whatever was rendered into the EGL surface. No-op while hidden,
  // while a frame is still pending, or while a color transition is staged
  // (see hdr_transition_staged()).
  bool Present();

  // Bits per color channel the plane actually got: 10 on a 10-bit unorm
  // config, otherwise 8. Read by the GPU render path so mpv dithers to the
  // plane's real precision (`MPV_RENDER_PARAM_DEPTH`) instead of assuming 8.
  int depth_bits() const { return depth_bits_; }

  // True when this plane can be described as HDR at all: the compositor
  // offers a parametric image-description creator, accepts the perceptual
  // render intent, and advertises BT.2020 primaries plus at least one HDR
  // curve (PQ or HLG) -- *and* the plane itself got a deep EGL config (10-bit
  // unorm) and a color surface. Says nothing about whether the *display* is
  // in HDR right now -- see output_is_hdr().
  bool supports_hdr() const { return supports_hdr_; }

  // What the compositor says it would prefer for this surface. The only way
  // to learn the output's *real* peak: an HDR output's preferred description
  // carries the panel's target luminance, where PQ's own nominal maximum is
  // always 10000.
  const PreferredColorDescription& preferred() const { return preferred_; }

  // True when the output this surface sits on has enough luminance headroom
  // above its own reference white to be worth passing HDR through instead of
  // tone-mapping in mpv.
  bool output_is_hdr() const {
    return preferred_.valid && OutputHasHdrHeadroom(preferred_.max_luminance, preferred_.reference_luminance);
  }

  // Invoked on the GTK main thread when the compositor's preferred
  // description changes -- a monitor move, or HDR being switched on or off
  // under us.
  void SetPreferredChangedCallback(std::function<void()> callback) { on_preferred_changed_ = std::move(callback); }

  // Stages a color change. Two-phase: BeginHdrTransition stages and
  // validates the description and holds Present() while it does, the caller
  // switches mpv's output color space once it settles, and
  // CommitHdrTransition attaches the state and releases the hold so the
  // first buffer rendered in the new color space is the one that carries it.
  // Abort backs out and changes nothing.
  //
  // `describe` is an instruction, not a request: the caller's HDR decision
  // (see hdr_metadata.h's DecideHdr) has already weighed the app's
  // permission, this surface's capabilities, the output's state and the
  // source.
  //
  // `on_settled(token, true)` means Commit may proceed. It fires
  // synchronously when there is nothing to validate, so the caller must
  // tolerate re-entry.
  //
  // The token identifies *this* transition; Commit and Abort ignore any
  // other, so a settled-but-uncommitted transition whose mpv leg is still in
  // flight cannot be committed against a newer description. A token of zero
  // means nothing was staged.
  void BeginHdrTransition(bool describe, const HdrMetadata& metadata, std::function<void(uint64_t, bool)> on_settled);

  // Applies the transition named by `token`. Returns true when the plane
  // should be re-rendered and presented at once, so the new state reaches
  // the screen instead of waiting for whatever frame mpv happens to produce
  // next. Ignores a token that is not the staged one.
  bool CommitHdrTransition(uint64_t token);

  // Discards the transition named by `token` and releases the hold. The
  // committed color state is left exactly as it was. Ignores a stale token.
  void AbortHdrTransition(uint64_t token);

  // True while a transition is staged, i.e. while Present() is being held.
  bool hdr_transition_staged() const { return transition_staged_; }

  // Drops any staged transition and unsets the description immediately, for
  // when mpv's color space had to be forced back to SDR while unwinding a
  // refused change and the already-committed description is no longer true
  // of the pixels. Returns true when the plane should be re-rendered and
  // presented at once.
  bool ForceUndescribed();

  // Whether this source could be described at all: it carries an HDR curve,
  // a BT.2020 container, and the compositor advertised that specific named
  // pair. Public because the caller has to know the answer *before* it
  // changes mpv's output color space -- the pixels have to be committed to
  // before the surface is described, or the two disagree for a frame.
  bool CanDescribeSource(const HdrMetadata& metadata) const;

  // Whether a description is attached, i.e. whether the compositor is
  // currently being told this plane carries an HDR curve.
  bool hdr_active() const { return hdr_active_; }

  // Bounds each half of a staged transition: first the compositor's verdict
  // on the image description, then the caller's mpv leg deciding to commit
  // or abort. Present() is held across *both*, so it is re-armed rather than
  // cancelled when the compositor answers -- the second wait is the longer
  // one and has no timeout of its own. Public because the caller's own mpv-
  // leg timeout shares this horizon: the two halves of the transaction must
  // give up together or the surface would resume presenting while the mpv
  // property write stayed unanswered.
  static constexpr int kTransitionTimeoutSeconds = 5;
  // How many roundtrips a synchronous bootstrap waits for its answer. Ready,
  // then the info burst, then done is three at worst, plus one spare for a
  // compositor that splits them differently.
  static constexpr int kBootstrapRoundtrips = 4;

  static constexpr int kFrameAckTimeoutMs = 500;
  static constexpr int kMaxConsecutiveFrameAckMisses = 5;

 private:
  bool BindGlobals(GdkDisplay* display, std::string* error);
  void BuildImageDescription();
  bool InitEgl(std::string* error);
  void RequestParentCommit();
  void ClearFrameCallback();
  void DetachBuffer();
  void ClearStagedDescription();
  void DiscardTransition();
  void SettleTransition(bool ok);
  void ArmFrameAckWatchdog();
  void CancelFrameAckWatchdog();

  static void HandleFrameDone(void* data, wl_callback* callback, uint32_t time);
  // Interface version 1 only; version 2 and later send ready2 in its place.
  static void HandleImageDescriptionReady(void* data, wp_image_description_v1* desc, uint32_t identity);
  static void HandleImageDescriptionReady2(
      void* data, wp_image_description_v1* desc, uint32_t identity_hi, uint32_t identity_lo);
  static void HandleImageDescriptionFailed(
      void* data, wp_image_description_v1* desc, uint32_t cause, const char* message);

  void ArmTransitionWatchdog();
  void CancelTransitionWatchdog();

  // Creates the preferred-description query. The returned description is
  // ready immediately per the protocol, so get_information follows on
  // ready, and the accumulated fields are committed when the info burst
  // ends with done.
  void BeginPreferredQuery();
  void ClearPreferredQuery();
  void CommitPreferredQuery();

  static void HandlePreferredChanged(void* data, wp_color_management_surface_feedback_v1* feedback, uint32_t identity);
  static void HandlePreferredChanged2(
      void* data, wp_color_management_surface_feedback_v1* feedback, uint32_t identity_hi, uint32_t identity_lo);
  static void HandlePreferredReady(void* data, wp_image_description_v1* desc, uint32_t identity);
  static void HandlePreferredReady2(
      void* data, wp_image_description_v1* desc, uint32_t identity_hi, uint32_t identity_lo);
  static void HandlePreferredFailed(void* data, wp_image_description_v1* desc, uint32_t cause, const char* message);

  // Only tf_named, primaries_named, luminances and target_luminance carry
  // anything used, and icc_file has to close the fd it is handed; the
  // remainder are deliberate no-ops rather than omissions -- every member
  // has to be present, see BuildImageDescription()'s static_assert.
  static void HandleInfoDone(void* data, wp_image_description_info_v1* info);
  static void HandleInfoIccFile(void* data, wp_image_description_info_v1* info, int32_t icc, uint32_t icc_size);
  static void HandleInfoPrimaries(
      void* data, wp_image_description_info_v1* info, int32_t r_x, int32_t r_y, int32_t g_x, int32_t g_y, int32_t b_x,
      int32_t b_y, int32_t w_x, int32_t w_y);
  static void HandleInfoPrimariesNamed(void* data, wp_image_description_info_v1* info, uint32_t primaries);
  static void HandleInfoTfPower(void* data, wp_image_description_info_v1* info, uint32_t eexp);
  static void HandleInfoTfNamed(void* data, wp_image_description_info_v1* info, uint32_t tf);
  static void HandleInfoLuminances(
      void* data, wp_image_description_info_v1* info, uint32_t min_lum, uint32_t max_lum, uint32_t reference_lum);
  static void HandleInfoTargetPrimaries(
      void* data, wp_image_description_info_v1* info, int32_t r_x, int32_t r_y, int32_t g_x, int32_t g_y, int32_t b_x,
      int32_t b_y, int32_t w_x, int32_t w_y);
  static void HandleInfoTargetLuminance(
      void* data, wp_image_description_info_v1* info, uint32_t min_lum, uint32_t max_lum);
  static void HandleInfoTargetMaxCll(void* data, wp_image_description_info_v1* info, uint32_t max_cll);
  static void HandleInfoTargetMaxFall(void* data, wp_image_description_info_v1* info, uint32_t max_fall);

  // The color manager's capability burst. Static members taking the surface
  // as user data, rather than file-locals over BindGlobals' stack, so a
  // burst still in flight when the bootstrap loop gives up is not dispatched
  // into a dead stack frame once GDK's queue picks it up.
  static void HandleManagerIntent(void* data, wp_color_manager_v1* manager, uint32_t intent);
  static void HandleManagerFeature(void* data, wp_color_manager_v1* manager, uint32_t feature);
  static void HandleManagerTransferFunction(void* data, wp_color_manager_v1* manager, uint32_t tf);
  static void HandleManagerPrimaries(void* data, wp_color_manager_v1* manager, uint32_t primaries);
  static void HandleManagerDone(void* data, wp_color_manager_v1* manager);

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
  std::function<void()> on_forced_render_;

  guint frame_ack_source_ = 0;
  int consecutive_frame_acks_missed_ = 0;

  int depth_bits_ = 8;

  wp_color_manager_v1* color_manager_ = nullptr;
  wp_color_management_surface_v1* color_surface_ = nullptr;
  // The description being validated for a staged transition. Never the
  // attached one: set_image_description copies, so the object is destroyed
  // immediately after it is handed over.
  wp_image_description_v1* staged_description_ = nullptr;
  bool transition_staged_ = false;
  uint64_t transition_token_ = 0;
  bool staged_describe_ = false;
  HdrMetadata staged_metadata_;
  std::function<void(uint64_t, bool)> on_transition_settled_;
  guint watchdog_source_ = 0;

  // Feedback lives for the whole surface lifetime so preferred_changed keeps
  // arriving; the description and info objects are transient, created per
  // query and destroyed as soon as their values have been copied out.
  wp_color_management_surface_feedback_v1* color_feedback_ = nullptr;
  wp_image_description_v1* preferred_description_ = nullptr;
  wp_image_description_info_v1* preferred_info_ = nullptr;
  PreferredColorDescription preferred_;
  PreferredColorDescription pending_preferred_;
  std::function<void()> on_preferred_changed_;
  // The committed source description, i.e. what the attached description
  // was built from. Compared against a new request so an identical one is a
  // no-op rather than a needless round-trip through the compositor.
  HdrMetadata metadata_;
  // supports_hdr_ is the aggregate gate; the three below are what the
  // compositor advertised individually, since whether a *given* source can
  // be described depends on its own curve, not on the aggregate.
  bool supports_hdr_ = false;
  bool supports_pq_ = false;
  bool supports_hlg_ = false;
  bool supports_bt2020_ = false;
  // What the compositor will accept in a luminance description. Consulted by
  // PlanHdrLuminance, which turns it plus the source into a legal request set.
  CompositorLuminanceSupport luminance_support_;
  struct ManagerCaps {
    bool parametric = false;
    bool perceptual = false;
    bool pq = false;
    bool hlg = false;
    bool bt2020 = false;
    bool mastering = false;
    bool extended_target_volume = false;
    bool done = false;
  };
  ManagerCaps manager_caps_;
  bool hdr_active_ = false;
};

}  // namespace m3u_tv_mpv_plane

#endif  // FLUTTER_CLIENT_LINUX_WAYLAND_VIDEO_SURFACE_H_
