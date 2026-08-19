#include "desktop_libmpv_backend.h"

#include <dlfcn.h>
#include <gdk/gdk.h>
#include <locale.h>
#ifdef GDK_WINDOWING_WAYLAND
#include <gdk/gdkwayland.h>
#endif
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif
#ifdef HAVE_WAYLAND_MPV_PLANE
#include "wayland_video_surface.h"
#endif

#include <algorithm>
#include <atomic>
#include <cctype>
#include <cstdint>
#include <cstring>
#include <map>
#include <memory>
#include <mutex>
#include <sstream>
#include <string>
#include <thread>
#include <utility>
#include <vector>

namespace {

constexpr char kChannelName[] = "m3u_tv/desktop_libmpv";
constexpr char kEventChannelName[] = "m3u_tv/desktop_libmpv/events";
constexpr char kBackendUnavailableCode[] = "backend_unavailable";
constexpr uint32_t kTextureWidth = 1280;
constexpr uint32_t kTextureHeight = 720;
constexpr int kBytesPerPixel = 4;

using mpv_handle = struct mpv_handle;
struct mpv_node;
struct mpv_node_list;
union mpv_node_union {
  char* string;
  int flag;
  int64_t int64;
  double double_;
  mpv_node_list* list;
  void* ba;
};
struct mpv_node {
  mpv_node_union u;
  int format;
};
struct mpv_node_list {
  int num;
  mpv_node* values;
  char** keys;
};
using mpv_create_fn = mpv_handle* (*)();
using mpv_initialize_fn = int (*)(mpv_handle*);
using mpv_command_fn = int (*)(mpv_handle*, const char**);
using mpv_set_option_string_fn = int (*)(mpv_handle*, const char*, const char*);
using mpv_get_property_fn = int (*)(mpv_handle*, const char*, int, void*);
using mpv_free_fn = void (*)(void*);
using mpv_free_node_contents_fn = void (*)(mpv_node*);
using mpv_terminate_destroy_fn = void (*)(mpv_handle*);
using mpv_observe_property_fn = int (*)(mpv_handle*, uint64_t, const char*, int);
using mpv_unobserve_property_fn = int (*)(mpv_handle*, uint64_t);
using mpv_wakeup_fn = void (*)(mpv_handle*);
using mpv_wait_event_fn = struct mpv_event* (*)(mpv_handle*, double);
using mpv_request_log_messages_fn = int (*)(mpv_handle*, const char*);
using mpv_render_update_fn = void (*)(void*);
using mpv_render_context = struct mpv_render_context;
using mpv_render_context_create_fn = int (*)(mpv_render_context**, mpv_handle*, void*);
using mpv_render_context_set_update_callback_fn = void (*)(mpv_render_context*, mpv_render_update_fn, void*);
using mpv_render_context_render_fn = int (*)(mpv_render_context*, void*);
using mpv_render_context_free_fn = void (*)(mpv_render_context*);

struct mpv_render_param {
  int type;
  void* data;
};

#ifdef HAVE_WAYLAND_MPV_PLANE
// mpv's OpenGL render API (mpv/render_gl.h), hardcoded against the stable
// values documented there -- the same approach already used above for the
// software render API's MPV_RENDER_PARAM_SW_* constants, so no libmpv
// devel headers are required to build this file (only the runtime .so,
// dlopen'd via LibmpvApi below).
constexpr int MPV_RENDER_PARAM_OPENGL_INIT_PARAMS = 2;
constexpr int MPV_RENDER_PARAM_OPENGL_FBO = 3;
constexpr int MPV_RENDER_PARAM_FLIP_Y = 4;
constexpr int MPV_RENDER_PARAM_DEPTH = 5;
constexpr char kMpvRenderApiTypeOpenGl[] = "opengl";

using mpv_opengl_get_proc_address_fn = void* (*)(void* ctx, const char* name);
struct mpv_opengl_init_params {
  mpv_opengl_get_proc_address_fn get_proc_address;
  void* get_proc_address_ctx;
};
struct mpv_opengl_fbo {
  int fbo;
  int w;
  int h;
  int internal_format;
};
#endif  // HAVE_WAYLAND_MPV_PLANE

struct mpv_event {
  int event_id;
  int error;
  uint64_t reply_userdata;
  void* data;
};

struct mpv_event_property {
  const char* name;
  int format;
  void* data;
};

struct mpv_event_end_file {
  int reason;
  int error;
  int64_t playlist_entry_id;
  int64_t playlist_insert_id;
  int playlist_insert_num_entries;
};

constexpr int MPV_EVENT_END_FILE = 7;
constexpr int MPV_END_FILE_REASON_EOF = 0;
constexpr int MPV_END_FILE_REASON_STOP = 2;
constexpr int MPV_END_FILE_REASON_QUIT = 3;
constexpr int MPV_END_FILE_REASON_ERROR = 4;
constexpr int MPV_END_FILE_REASON_REDIRECT = 5;

constexpr int MPV_FORMAT_DOUBLE = 5;
constexpr int MPV_FORMAT_FLAG = 3;
constexpr int MPV_FORMAT_STRING = 1;
constexpr int MPV_FORMAT_INT64 = 4;
constexpr int MPV_FORMAT_NODE = 6;
constexpr int MPV_FORMAT_NODE_ARRAY = 7;
constexpr int MPV_FORMAT_NODE_MAP = 8;

constexpr int MPV_RENDER_PARAM_INVALID = 0;
constexpr int MPV_RENDER_PARAM_API_TYPE = 1;
constexpr int MPV_RENDER_PARAM_X11_DISPLAY = 8;
constexpr int MPV_RENDER_PARAM_WL_DISPLAY = 9;
constexpr int MPV_RENDER_PARAM_SW_SIZE = 17;
constexpr int MPV_RENDER_PARAM_SW_FORMAT = 18;
constexpr int MPV_RENDER_PARAM_SW_STRIDE = 19;
constexpr int MPV_RENDER_PARAM_SW_POINTER = 20;

struct LibmpvApi {
  void* library = nullptr;
  mpv_create_fn create = nullptr;
  mpv_initialize_fn initialize = nullptr;
  mpv_command_fn command = nullptr;
  mpv_set_option_string_fn set_option_string = nullptr;
  mpv_get_property_fn get_property = nullptr;
  mpv_free_fn free = nullptr;
  mpv_free_node_contents_fn free_node_contents = nullptr;
  mpv_terminate_destroy_fn terminate_destroy = nullptr;
  mpv_observe_property_fn observe_property = nullptr;
  mpv_unobserve_property_fn unobserve_property = nullptr;
  mpv_wakeup_fn wakeup = nullptr;
  mpv_wait_event_fn wait_event = nullptr;
  mpv_request_log_messages_fn request_log_messages = nullptr;
  mpv_render_context_create_fn render_context_create = nullptr;
  mpv_render_context_set_update_callback_fn render_context_set_update_callback = nullptr;
  mpv_render_context_render_fn render_context_render = nullptr;
  mpv_render_context_free_fn render_context_free = nullptr;
  std::string library_name;
  std::string error;

  bool client_available() const {
    return library != nullptr && create != nullptr && initialize != nullptr &&
           command != nullptr && set_option_string != nullptr &&
           get_property != nullptr && free != nullptr &&
           free_node_contents != nullptr && terminate_destroy != nullptr &&
           observe_property != nullptr && unobserve_property != nullptr &&
           wakeup != nullptr && wait_event != nullptr;
  }

  bool render_api_available() const {
    return render_context_create != nullptr &&
           render_context_set_update_callback != nullptr &&
           render_context_render != nullptr && render_context_free != nullptr;
  }

  bool available() const { return client_available() && render_api_available(); }
};

struct CopyPixelsContext {
  CopyPixelsContext(LibmpvApi* api, mpv_handle* handle,
                    mpv_render_context* render_context)
      : api(api),
        handle(handle),
        render_context(render_context),
        pixels(kTextureWidth * kTextureHeight * kBytesPerPixel, 0) {}

  void SetUpdateCallback(mpv_render_update_fn callback, void* callback_context) {
    std::lock_guard<std::mutex> lock(mutex);
    if (released || api == nullptr || render_context == nullptr ||
        api->render_context_set_update_callback == nullptr) {
      return;
    }
    api->render_context_set_update_callback(render_context, callback,
                                            callback_context);
  }

  void Retain() { references.fetch_add(1, std::memory_order_relaxed); }

  void Release() {
    if (references.fetch_sub(1, std::memory_order_acq_rel) == 1) delete this;
  }

  gboolean CopyPixels(const uint8_t** buffer, uint32_t* width,
                      uint32_t* height) {
    std::lock_guard<std::mutex> lock(mutex);
    if (released || api == nullptr || render_context == nullptr ||
        api->render_context_render == nullptr) {
      return FALSE;
    }
    int size[] = {static_cast<int>(kTextureWidth),
                  static_cast<int>(kTextureHeight)};
    int stride = static_cast<int>(kTextureWidth * kBytesPerPixel);
    char format[] = "rgba";
    void* pixel_buffer = pixels.data();
    mpv_render_param params[] = {
        {MPV_RENDER_PARAM_SW_SIZE, size},
        {MPV_RENDER_PARAM_SW_FORMAT, format},
        {MPV_RENDER_PARAM_SW_STRIDE, &stride},
        {MPV_RENDER_PARAM_SW_POINTER, pixel_buffer},
        {MPV_RENDER_PARAM_INVALID, nullptr},
    };
    api->render_context_render(render_context, params);
    *buffer = pixels.data();
    *width = kTextureWidth;
    *height = kTextureHeight;
    return TRUE;
  }

  void ReleaseResources() {
    std::lock_guard<std::mutex> lock(mutex);
    if (released) return;
    released = true;
    if (render_context != nullptr && api != nullptr &&
        api->render_context_free != nullptr) {
      api->render_context_free(render_context);
      render_context = nullptr;
    }
    if (handle != nullptr && api != nullptr &&
        api->terminate_destroy != nullptr) {
      api->terminate_destroy(handle);
      handle = nullptr;
    }
    api = nullptr;
  }

  std::mutex mutex;
  LibmpvApi* api = nullptr;
  mpv_handle* handle = nullptr;
  mpv_render_context* render_context = nullptr;
  std::vector<uint8_t> pixels;
  std::atomic<int> references{1};
  bool released = false;
};

struct DisplayInfo {
  std::string window_system = "headless";
  std::string video_api = "software libmpv render API";
  void* x11_display = nullptr;
  void* wayland_display = nullptr;
  bool has_hardware_display = false;
};

typedef struct _MpvTexture MpvTexture;
typedef struct _MpvTextureClass MpvTextureClass;

struct _MpvTexture {
  FlPixelBufferTexture parent_instance;
  CopyPixelsContext* copy_context;
};

struct _MpvTextureClass {
  FlPixelBufferTextureClass parent_class;
};

G_DEFINE_TYPE(MpvTexture, mpv_texture, fl_pixel_buffer_texture_get_type())

GMainContext* g_gtk_main_context = nullptr;

bool DispatchOnGtkMain(GSourceFunc callback, gpointer user_data) {
  if (g_gtk_main_context == nullptr) return false;
  GSource* source = g_idle_source_new();
  g_source_set_callback(source, callback, user_data, nullptr);
  const guint source_id = g_source_attach(source, g_gtk_main_context);
  g_source_unref(source);
  return source_id != 0;
}

struct EventSnapshot {
  int64_t handle;
  int sequence;
  std::string kind;
  double position = 0.0;
  double duration = 0.0;
  bool paused = false;
  bool buffering = false;
  bool eof = false;
  double video_aspect_ratio = 0.0;
  double speed = 0.0;
  std::string aid;
  std::string sid;
  bool has_aid = false;
  bool has_sid = false;
  struct Track {
    std::string id;
    std::string label;
    std::string language;
  };
  std::vector<Track> audio_tracks;
  std::vector<Track> subtitle_tracks;
  bool has_track_lists = false;
  std::string message;
  std::string code;
  bool recoverable = false;
};

struct EventDispatchState {
  explicit EventDispatchState(FlEventChannel* channel)
      : event_channel(FL_EVENT_CHANNEL(g_object_ref(channel))) {}

  ~EventDispatchState() {
    if (event_channel != nullptr) g_object_unref(event_channel);
  }

  void Deactivate() { active.store(false, std::memory_order_release); }

  std::atomic<bool> active{true};
  FlEventChannel* event_channel = nullptr;
};

struct EventDispatch {
  std::shared_ptr<EventDispatchState> state;
  EventSnapshot snapshot;
};

struct EventChannelState {
  explicit EventChannelState(FlEventChannel* channel)
      : event_channel(FL_EVENT_CHANNEL(g_object_ref(channel))) {}

  ~EventChannelState() {
    if (event_channel != nullptr) g_object_unref(event_channel);
  }

  std::shared_ptr<EventDispatchState> CreateDispatchState() const {
    if (!active.load(std::memory_order_acquire) || event_channel == nullptr) {
      return nullptr;
    }
    return std::make_shared<EventDispatchState>(event_channel);
  }

  void Deactivate() { active.store(false, std::memory_order_release); }

 private:
  std::atomic<bool> active{true};
  FlEventChannel* event_channel = nullptr;
};

struct TextureDispatchState {
  TextureDispatchState(FlTextureRegistrar* texture_registrar, FlTexture* texture)
      : texture_registrar(texture_registrar), texture(texture) {}

  void Retain() { references.fetch_add(1, std::memory_order_relaxed); }

  void Release() {
    if (references.fetch_sub(1, std::memory_order_acq_rel) == 1) delete this;
  }

  void QueueFrame() {
    if (!active.load(std::memory_order_acquire)) return;
    bool expected = false;
    if (!frame_pending.compare_exchange_strong(expected, true,
                                               std::memory_order_acq_rel)) {
      return;
    }
    Retain();
    if (!DispatchOnGtkMain(MarkTextureFrameAvailableOnGtkThread, this)) {
      frame_pending.store(false, std::memory_order_release);
      Release();
    }
  }

  void Deactivate() { active.store(false, std::memory_order_release); }

  static gboolean MarkTextureFrameAvailableOnGtkThread(gpointer user_data) {
    auto* state = static_cast<TextureDispatchState*>(user_data);
    if (state->active.load(std::memory_order_acquire) &&
        state->texture_registrar != nullptr && state->texture != nullptr) {
      fl_texture_registrar_mark_texture_frame_available(state->texture_registrar,
                                                        state->texture);
    }
    state->frame_pending.store(false, std::memory_order_release);
    state->Release();
    return G_SOURCE_REMOVE;
  }

  std::atomic<bool> active{true};

 private:
  std::atomic<int> references{1};
  std::atomic<bool> frame_pending{false};
  FlTextureRegistrar* texture_registrar = nullptr;
  FlTexture* texture = nullptr;
};

struct PlayerInstance;
#ifdef HAVE_WAYLAND_MPV_PLANE
// Defined near the other GPU render-path helpers, after this struct.
void TeardownGpuPlane(PlayerInstance* player);
#endif

struct PlayerInstance {
  PlayerInstance(LibmpvApi* api, FlTextureRegistrar* texture_registrar,
                 std::shared_ptr<EventDispatchState> event_dispatch_state,
                 mpv_handle* handle, mpv_render_context* render_context,
                 MpvTexture* texture, int64_t texture_id, int64_t id)
      : api(api),
        texture_registrar(texture_registrar),
        event_dispatch_state(std::move(event_dispatch_state)),
        handle(handle),
        render_context(render_context),
        texture(texture),
        texture_id(texture_id),
        id(id),
        copy_context(new CopyPixelsContext(api, handle, render_context)),
        texture_state(new TextureDispatchState(texture_registrar,
                                               FL_TEXTURE(texture))) {
    texture->copy_context = copy_context;
    copy_context->Retain();
  }

#ifdef HAVE_WAYLAND_MPV_PLANE
  // GPU/Wayland-plane constructor: no Flutter texture is created at all --
  // video reaches the screen through the wl_subsurface `gpu_plane` owns, not
  // through anything Flutter's compositor knows about. See CreateGpuPlane()
  // in Load().
  PlayerInstance(LibmpvApi* api, std::shared_ptr<EventDispatchState> event_dispatch_state,
                 mpv_handle* handle, mpv_render_context* render_context, EGLContext gpu_egl_context,
                 std::unique_ptr<m3u_tv_mpv_plane::WaylandVideoSurface> gpu_plane, int64_t id)
      : api(api),
        event_dispatch_state(std::move(event_dispatch_state)),
        handle(handle),
        render_context(render_context),
        id(id),
        using_gpu_plane(true),
        gpu_egl_context(gpu_egl_context),
        gpu_plane(std::move(gpu_plane)) {}
#endif

  ~PlayerInstance() {
    disposing.store(true);
    if (copy_context != nullptr) {
      copy_context->SetUpdateCallback(nullptr, nullptr);
    }
    if (api != nullptr && api->wakeup != nullptr && handle != nullptr) {
      api->wakeup(handle);
    }
    if (event_thread.joinable()) {
      event_thread.join();
    }
    if (event_dispatch_state != nullptr) {
      event_dispatch_state->Deactivate();
    }
    if (api != nullptr && api->unobserve_property != nullptr && handle != nullptr) {
      api->unobserve_property(handle, 0);
    }
    if (texture_state != nullptr) {
      texture_state->Deactivate();
    }
    if (texture_registrar != nullptr && texture != nullptr) {
      fl_texture_registrar_unregister_texture(texture_registrar,
                                              FL_TEXTURE(texture));
    }
    if (copy_context != nullptr) {
      copy_context->ReleaseResources();
      handle = nullptr;
      render_context = nullptr;
    }
    if (texture != nullptr) {
      g_object_unref(texture);
    }
    if (texture_state != nullptr) {
      texture_state->Release();
      texture_state = nullptr;
    }
    if (copy_context != nullptr) {
      copy_context->Release();
      copy_context = nullptr;
    }
#ifdef HAVE_WAYLAND_MPV_PLANE
    // Defined below, alongside the rest of the GPU render-path helpers: the
    // GPU plane's render_context/EGL context are only ever touched from the
    // GTK main thread (RenderGpuFrame's idle source, and this destructor,
    // which likewise only ever runs there), unlike CopyPixelsContext's
    // mutex-guarded render_context, which the Flutter raster thread's
    // MpvTextureCopyPixels callback can reach concurrently. See
    // TeardownGpuPlane's own comment.
    if (using_gpu_plane) TeardownGpuPlane(this);
#endif
  }

  void StartEventThread();
  void QueueEvent(EventSnapshot snapshot);
  void ReadSnapshotProperties(EventSnapshot* snapshot);
  void ReadTrackLists(EventSnapshot* snapshot);

  LibmpvApi* api = nullptr;
  FlTextureRegistrar* texture_registrar = nullptr;
  std::shared_ptr<EventDispatchState> event_dispatch_state;
  mpv_handle* handle = nullptr;
  mpv_render_context* render_context = nullptr;
  MpvTexture* texture = nullptr;
  int64_t texture_id = 0;
  int64_t id = 0;
  std::thread event_thread;
  std::atomic<bool> disposing{false};
#ifdef HAVE_WAYLAND_MPV_PLANE
  bool using_gpu_plane = false;
  EGLContext gpu_egl_context = EGL_NO_CONTEXT;
  std::unique_ptr<m3u_tv_mpv_plane::WaylandVideoSurface> gpu_plane;
  // Coalesces mpv's render-update callback (fired from an mpv thread) onto a
  // single pending GTK-main-thread idle source. Guards against scheduling a
  // redraw after PlayerInstance starts tearing down.
  std::atomic<bool> gpu_needs_redraw{false};
  std::atomic<bool> gpu_render_scheduled{false};
  std::atomic<guint> gpu_idle_source_id{0};
  // The most recent source HDR metadata applied by ApplyHdrForVideoParams,
  // re-consulted when the compositor's preferred description changes (a
  // monitor move, or the output's own HDR mode being switched under us) so
  // the same source can be re-decided against the new output state without
  // waiting for mpv to report `video-params` again -- which it will not,
  // since the source itself has not changed.
  m3u_tv_mpv_plane::HdrMetadata last_source_hdr;
  // User-facing override, mirrored from the `enableHDR` app setting via the
  // `setHdrEnabled` control method. Feeds HdrInputs::allowed in
  // ApplyHdrForVideoParams; defaults on so playback matches the prior,
  // always-on behavior until the user turns it off.
  bool hdr_user_enabled = true;
#endif
  std::atomic<int> sequence{0};
  CopyPixelsContext* copy_context = nullptr;
  TextureDispatchState* texture_state = nullptr;
};

LibmpvApi g_api;
FlTextureRegistrar* g_texture_registrar = nullptr;
std::shared_ptr<EventChannelState> g_event_channel_state;
int64_t g_next_handle = 1;
std::map<int64_t, std::unique_ptr<PlayerInstance>> g_players;
#ifdef HAVE_WAYLAND_MPV_PLANE
// The Flutter view widget, captured at plugin registration. Needed to create
// the Wayland video plane subsurface (it must be a child of the toplevel
// this view is hosted in) -- see CreateGpuPlane().
FlView* g_flutter_view = nullptr;
#endif

void* LoadSymbol(void* library, const char* name) { return dlsym(library, name); }

LibmpvApi& Api() {
  if (g_api.library != nullptr || !g_api.error.empty()) return g_api;

  const char* names[] = {"libmpv.so.2", "libmpv.so.1", "libmpv.so"};
  std::ostringstream attempted;
  for (const char* name : names) {
    attempted << name << " ";
    dlerror();
    g_api.library = dlopen(name, RTLD_NOW | RTLD_LOCAL);
    if (g_api.library != nullptr) {
      g_api.library_name = name;
      break;
    }
  }
  if (g_api.library == nullptr) {
    const char* error = dlerror();
    g_api.error = std::string("libmpv shared library not found; tried ") +
                  attempted.str() + (error == nullptr ? "" : error);
    return g_api;
  }

  g_api.create = reinterpret_cast<mpv_create_fn>(LoadSymbol(g_api.library, "mpv_create"));
  g_api.initialize = reinterpret_cast<mpv_initialize_fn>(LoadSymbol(g_api.library, "mpv_initialize"));
  g_api.command = reinterpret_cast<mpv_command_fn>(LoadSymbol(g_api.library, "mpv_command"));
  g_api.set_option_string = reinterpret_cast<mpv_set_option_string_fn>(LoadSymbol(g_api.library, "mpv_set_option_string"));
  g_api.get_property = reinterpret_cast<mpv_get_property_fn>(LoadSymbol(g_api.library, "mpv_get_property"));
  g_api.free = reinterpret_cast<mpv_free_fn>(LoadSymbol(g_api.library, "mpv_free"));
  g_api.free_node_contents = reinterpret_cast<mpv_free_node_contents_fn>(
      LoadSymbol(g_api.library, "mpv_free_node_contents"));
  g_api.terminate_destroy = reinterpret_cast<mpv_terminate_destroy_fn>(LoadSymbol(g_api.library, "mpv_terminate_destroy"));
  g_api.observe_property = reinterpret_cast<mpv_observe_property_fn>(LoadSymbol(g_api.library, "mpv_observe_property"));
  g_api.unobserve_property = reinterpret_cast<mpv_unobserve_property_fn>(LoadSymbol(g_api.library, "mpv_unobserve_property"));
  g_api.wakeup = reinterpret_cast<mpv_wakeup_fn>(LoadSymbol(g_api.library, "mpv_wakeup"));
  g_api.wait_event = reinterpret_cast<mpv_wait_event_fn>(LoadSymbol(g_api.library, "mpv_wait_event"));
  g_api.request_log_messages = reinterpret_cast<mpv_request_log_messages_fn>(LoadSymbol(g_api.library, "mpv_request_log_messages"));
  g_api.render_context_create = reinterpret_cast<mpv_render_context_create_fn>(LoadSymbol(g_api.library, "mpv_render_context_create"));
  g_api.render_context_set_update_callback = reinterpret_cast<mpv_render_context_set_update_callback_fn>(LoadSymbol(g_api.library, "mpv_render_context_set_update_callback"));
  g_api.render_context_render = reinterpret_cast<mpv_render_context_render_fn>(LoadSymbol(g_api.library, "mpv_render_context_render"));
  g_api.render_context_free = reinterpret_cast<mpv_render_context_free_fn>(LoadSymbol(g_api.library, "mpv_render_context_free"));

  if (!g_api.client_available()) {
    g_api.error = "libmpv loaded but required client symbols are missing";
  } else if (!g_api.render_api_available()) {
    g_api.error = "libmpv loaded but render API symbols are missing";
  }
  return g_api;
}

DisplayInfo GetDisplayInfo() {
  DisplayInfo info;
  GdkDisplay* display = gdk_display_get_default();
  if (display == nullptr) return info;

  const char* type_name = G_OBJECT_TYPE_NAME(display);
  std::string type = type_name == nullptr ? "unknown" : type_name;
#ifdef GDK_WINDOWING_WAYLAND
  if (GDK_IS_WAYLAND_DISPLAY(display)) {
    info.window_system = "wayland";
    info.video_api = "Wayland display handle + software libmpv texture fallback";
    info.wayland_display = gdk_wayland_display_get_wl_display(display);
    info.has_hardware_display = info.wayland_display != nullptr;
    return info;
  }
#endif
#ifdef GDK_WINDOWING_X11
  if (GDK_IS_X11_DISPLAY(display)) {
    info.window_system = "x11";
    info.video_api = "X11 display handle + software libmpv texture fallback";
    info.x11_display = gdk_x11_display_get_xdisplay(display);
    info.has_hardware_display = info.x11_display != nullptr;
    return info;
  }
#endif
  info.window_system = type;
  info.video_api = "software libmpv texture fallback";
  return info;
}

std::string DisplayDetails(const DisplayInfo& display) {
  std::ostringstream details;
  details << "windowSystem=" << display.window_system
          << "; hardwareDisplayHandle="
          << (display.has_hardware_display ? "available" : "unavailable")
          << "; texture=Flutter pixel buffer";
  return details.str();
}

std::string CurrentNumericLocale() {
  const char* locale = setlocale(LC_NUMERIC, nullptr);
  return locale == nullptr ? "unknown" : locale;
}

std::string MpvCreateNullError(const LibmpvApi& api) {
  std::ostringstream error;
  error << "mpv_create returned null; library="
        << (api.library_name.empty() ? "unknown" : api.library_name)
        << "; LC_NUMERIC=" << CurrentNumericLocale()
        << "; ensure LC_NUMERIC is C or C.UTF-8 before creating libmpv";
  return error.str();
}

FlValue* ProbeResult() {
  LibmpvApi& api = Api();
  const DisplayInfo display = GetDisplayInfo();
  const bool can_play = api.available() && g_texture_registrar != nullptr;

  std::string details = can_play ? "libmpv client/render symbols resolved from " + api.library_name
                                 : api.error;
  if (g_texture_registrar == nullptr) {
    if (!details.empty()) details += "; ";
    details += "Flutter texture registrar unavailable";
  }
  if (!details.empty()) details += "; ";
  details += DisplayDetails(display);

  g_autoptr(FlValue) result = fl_value_new_map();
  fl_value_set_string_take(result, "platform", fl_value_new_string("linux"));
  fl_value_set_string_take(result, "windowSystem", fl_value_new_string(display.window_system.c_str()));
  fl_value_set_string_take(result, "videoApi", fl_value_new_string(display.video_api.c_str()));
  fl_value_set_string_take(result, "ownedSurface", fl_value_new_bool(TRUE));
  fl_value_set_string_take(result, "libmpvAvailable", fl_value_new_bool(api.client_available()));
  fl_value_set_string_take(result, "renderApiAvailable", fl_value_new_bool(api.render_api_available()));
  fl_value_set_string_take(result, "canPlayFixture", fl_value_new_bool(can_play));
  fl_value_set_string_take(result, "fallbackDecision", fl_value_new_string(can_play ? "none" : "server-transcode until libmpv runtime is bundled"));
  fl_value_set_string_take(result, "details", fl_value_new_string(details.c_str()));
  return fl_value_ref(result);
}

std::string StringArg(FlValue* args, const char* key) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) return "";
  FlValue* value = fl_value_lookup_string(args, key);
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_STRING) return "";
  return fl_value_get_string(value);
}

int64_t IntArg(FlValue* args, const char* key) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) return 0;
  FlValue* value = fl_value_lookup_string(args, key);
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_INT) return 0;
  return fl_value_get_int(value);
}

bool BoolArg(FlValue* args, const char* key, bool fallback) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) return fallback;
  FlValue* value = fl_value_lookup_string(args, key);
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_BOOL) return fallback;
  return fl_value_get_bool(value);
}

FlValue* MapArg(FlValue* args, const char* key) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) return nullptr;
  FlValue* value = fl_value_lookup_string(args, key);
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_MAP) return nullptr;
  return value;
}

std::string HeaderString(FlValue* args) {
  FlValue* headers = MapArg(args, "headers");
  if (headers == nullptr) return "";
  std::ostringstream value;
  const size_t size = fl_value_get_length(headers);
  for (size_t i = 0; i < size; ++i) {
    FlValue* key = fl_value_get_map_key(headers, i);
    FlValue* item = fl_value_get_map_value(headers, i);
    if (fl_value_get_type(key) != FL_VALUE_TYPE_STRING ||
        fl_value_get_type(item) != FL_VALUE_TYPE_STRING) {
      continue;
    }
    if (value.tellp() > 0) value << ",";
    value << fl_value_get_string(key) << ": " << fl_value_get_string(item);
  }
  return value.str();
}

#ifdef HAVE_WAYLAND_MPV_PLANE
void* GetOpenGlProcAddress(void* ctx, const char* name) {
  (void)ctx;
  return reinterpret_cast<void*>(eglGetProcAddress(name));
}

// Renders one mpv frame into the plane's EGL surface and presents it. Must
// only be called on the GTK main thread (it makes the plane's EGL context
// current on this thread).
void RenderGpuFrame(PlayerInstance* player) {
  if (player == nullptr || player->disposing.load(std::memory_order_acquire)) return;
  m3u_tv_mpv_plane::WaylandVideoSurface* plane = player->gpu_plane.get();
  if (plane == nullptr || !plane->valid() || !plane->has_size()) return;
  if (plane->frame_pending()) return;  // Present() will no-op; wait for the ack.

  if (!eglMakeCurrent(plane->egl_display(), plane->egl_surface(), plane->egl_surface(), player->gpu_egl_context)) {
    g_warning("MPV video plane: failed to activate EGL context for render: 0x%x", eglGetError());
    return;
  }

  player->gpu_needs_redraw.store(false, std::memory_order_release);

  mpv_opengl_fbo fbo{};
  fbo.fbo = 0;  // the plane's own default framebuffer
  fbo.w = plane->width();
  fbo.h = plane->height();
  fbo.internal_format = plane->depth_bits() >= 10 ? 0x8059 /* GL_RGB10_A2 */ : 0x8058 /* GL_RGBA8 */;
  int flip_y = 1;
  int depth = plane->depth_bits();
  mpv_render_param params[] = {
      {MPV_RENDER_PARAM_OPENGL_FBO, &fbo},
      {MPV_RENDER_PARAM_FLIP_Y, &flip_y},
      {MPV_RENDER_PARAM_DEPTH, &depth},
      {MPV_RENDER_PARAM_INVALID, nullptr},
  };
  if (player->api != nullptr && player->api->render_context_render != nullptr) {
    player->api->render_context_render(player->render_context, params);
  }
  plane->Present();
}

gboolean RenderGpuFrameIdle(gpointer data) {
  auto* player = static_cast<PlayerInstance*>(data);
  player->gpu_idle_source_id.store(0, std::memory_order_release);
  player->gpu_render_scheduled.store(false, std::memory_order_release);
  if (!player->disposing.load(std::memory_order_acquire) && player->gpu_needs_redraw.load(std::memory_order_acquire)) {
    RenderGpuFrame(player);
  }
  return G_SOURCE_REMOVE;
}

// Coalesces a redraw request onto a single pending GTK-main-thread idle
// source. Safe to call from any thread (mpv's render-update callback may
// fire from an mpv-internal thread; the plane's own frame-ack callback
// always runs on the GTK main thread already).
void ScheduleGpuRender(PlayerInstance* player) {
  if (player == nullptr || player->disposing.load(std::memory_order_acquire)) return;
  player->gpu_needs_redraw.store(true, std::memory_order_release);
  bool expected = false;
  if (!player->gpu_render_scheduled.compare_exchange_strong(expected, true, std::memory_order_acq_rel)) {
    return;  // Already scheduled; it will pick up the latest gpu_needs_redraw.
  }
  const guint source_id = g_idle_add(RenderGpuFrameIdle, player);
  player->gpu_idle_source_id.store(source_id, std::memory_order_release);
}

// mpv's OpenGL render-update callback. May be invoked from an mpv-internal
// thread per the render API's documented contract.
void OnMpvRenderUpdateGpu(void* ctx) { ScheduleGpuRender(static_cast<PlayerInstance*>(ctx)); }

// The GPU plane has no CopyPixelsContext-style mutex-guarded wrapper around
// render_context_set_update_callback -- unlike the software path, nothing on
// the Flutter raster thread ever touches this render_context (see
// TeardownGpuPlane's comment), so there is no concurrent caller to guard
// against. Kept as its own function purely so the raw API call has one
// obvious call site.
void AttachGpuRenderCallback(LibmpvApi& api, mpv_render_context* render_context, PlayerInstance* player) {
  api.render_context_set_update_callback(render_context, OnMpvRenderUpdateGpu, player);
}

// Creates the isolated EGL context and mpv OpenGL render context bound to
// `plane`. Deliberately not shared with Flutter's own GL context -- see
// wayland_video_surface.h. Returns false and fills `error` on any failure.
bool CreateGpuRenderContext(LibmpvApi& api, mpv_handle* handle, m3u_tv_mpv_plane::WaylandVideoSurface& plane,
                            EGLContext* out_context, mpv_render_context** out_render, std::string* error) {
  if (!eglBindAPI(EGL_OPENGL_ES_API)) {
    if (error) *error = "Failed to bind OpenGL ES API for the video plane";
    return false;
  }

  EGLContext context = EGL_NO_CONTEXT;
  for (const EGLint client_version : {3, 2}) {
    const EGLint attribs[] = {EGL_CONTEXT_CLIENT_VERSION, client_version, EGL_NONE};
    context = eglCreateContext(plane.egl_display(), plane.egl_config(), EGL_NO_CONTEXT, attribs);
    if (context != EGL_NO_CONTEXT) break;
  }
  if (context == EGL_NO_CONTEXT) {
    if (error) *error = "Failed to create the video-plane EGL context";
    return false;
  }

  if (!eglMakeCurrent(plane.egl_display(), plane.egl_surface(), plane.egl_surface(), context)) {
    eglDestroyContext(plane.egl_display(), context);
    if (error) *error = "Failed to activate the video-plane EGL context";
    return false;
  }
  // The plane paces itself with its own frame-ack callback; the default
  // swap interval would otherwise throttle eglSwapBuffers on the
  // compositor's frame callback, which an occluded surface never receives.
  eglSwapInterval(plane.egl_display(), 0);

  mpv_opengl_init_params gl_init_params{};
  gl_init_params.get_proc_address = GetOpenGlProcAddress;
  gl_init_params.get_proc_address_ctx = nullptr;
  mpv_render_param params[] = {
      {MPV_RENDER_PARAM_API_TYPE, const_cast<char*>(kMpvRenderApiTypeOpenGl)},
      {MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, &gl_init_params},
      {MPV_RENDER_PARAM_INVALID, nullptr},
  };

  mpv_render_context* render_context = nullptr;
  const int rc = api.render_context_create(&render_context, handle, params);
  if (rc < 0 || render_context == nullptr) {
    eglMakeCurrent(plane.egl_display(), EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    eglDestroyContext(plane.egl_display(), context);
    if (error) *error = "mpv_render_context_create failed for the video plane";
    return false;
  }

  *out_context = context;
  *out_render = render_context;
  return true;
}

// Tears down a GPU-plane PlayerInstance's render_context/EGL context/Wayland
// plane, called once from ~PlayerInstance. Unlike CopyPixelsContext's
// mutex-guarded equivalent (needed because the raster thread's
// MpvTextureCopyPixels can call into it concurrently with the GTK main
// thread), nothing here needs a lock: RenderGpuFrame only ever runs from a
// GTK-main-thread idle source, and this destructor path only ever runs on
// the GTK main thread too, so the two can never overlap.
void TeardownGpuPlane(PlayerInstance* player) {
  // Stop new render-update callbacks before anything else: once this
  // returns, OnMpvRenderUpdateGpu can no longer schedule a fresh idle source
  // referencing this (soon to be destroyed) instance.
  if (player->render_context != nullptr && player->api != nullptr &&
      player->api->render_context_set_update_callback != nullptr) {
    player->api->render_context_set_update_callback(player->render_context, nullptr, nullptr);
  }
  const guint pending_source = player->gpu_idle_source_id.exchange(0);
  if (pending_source != 0) g_source_remove(pending_source);

  // mpv_render_context_free must run while its GL context is current; the
  // plane's own Destroy() below then tears down the EGL surface and Wayland
  // objects the context was current *against*.
  if (player->gpu_plane != nullptr && player->gpu_plane->valid() && player->gpu_egl_context != EGL_NO_CONTEXT) {
    eglMakeCurrent(player->gpu_plane->egl_display(), player->gpu_plane->egl_surface(),
                   player->gpu_plane->egl_surface(), player->gpu_egl_context);
  }
  if (player->render_context != nullptr && player->api != nullptr && player->api->render_context_free != nullptr) {
    player->api->render_context_free(player->render_context);
    player->render_context = nullptr;
  }
  if (player->gpu_plane != nullptr) {
    EGLDisplay display = player->gpu_plane->egl_display();
    if (display != EGL_NO_DISPLAY) eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    if (player->gpu_egl_context != EGL_NO_CONTEXT) eglDestroyContext(display, player->gpu_egl_context);
    player->gpu_egl_context = EGL_NO_CONTEXT;
    player->gpu_plane->Destroy();
    player->gpu_plane.reset();
  }
  if (player->handle != nullptr && player->api != nullptr && player->api->terminate_destroy != nullptr) {
    player->api->terminate_destroy(player->handle);
    player->handle = nullptr;
  }
}

// mpv's reply userdata for the runner's own `video-params` observation, used
// to intercept HDR-relevant source changes without disturbing the generic
// PLAYBACK_RESTART snapshot rebuild every other observed property triggers.
// Adapted from Plezy's `kVideoParamsUserdata` (mpv_player.cc).
constexpr uint64_t kVideoParamsHdrUserdata = UINT64_MAX;

// Reads the fields the HDR decision needs out of a `video-params` node,
// directly into hdr_metadata.h's `HdrMetadata` -- adapted from Plezy's
// `video_params.h`, but folded into this file (rather than kept as its own
// header) because it has to operate on *this* file's local, dlopen-friendly
// `mpv_node` layout rather than the real `<mpv/client.h>` one: this backend
// deliberately avoids depending on libmpv devel headers at build time (see
// the comment beside MPV_RENDER_PARAM_OPENGL_INIT_PARAMS above), and the two
// struct layouts, while ABI-compatible, are not the same C++ type.
//
// A luminance the source did not state stays absent (zero) rather than
// becoming a zero-valued claim -- mpv omits the field entirely rather than
// reporting a zero, and zero is exactly how HdrMetadata spells "not stated".
m3u_tv_mpv_plane::HdrMetadata ParseVideoParamsHdrMetadata(const mpv_node* params) {
  m3u_tv_mpv_plane::HdrMetadata metadata;
  if (params == nullptr || params->format != MPV_FORMAT_NODE_MAP || params->u.list == nullptr) return metadata;
  const mpv_node_list& entries = *params->u.list;
  if (entries.keys == nullptr || entries.values == nullptr) return metadata;

  auto as_double = [](const mpv_node& value, double* out) {
    if (value.format == MPV_FORMAT_DOUBLE) {
      *out = value.u.double_;
      return true;
    }
    if (value.format == MPV_FORMAT_INT64) {
      *out = static_cast<double>(value.u.int64);
      return true;
    }
    return false;
  };
  auto as_positive_uint32 = [&as_double](const mpv_node& value, uint32_t* out) {
    double parsed = 0.0;
    if (as_double(value, &parsed) && parsed > 0.0) *out = static_cast<uint32_t>(parsed);
  };

  for (int index = 0; index < entries.num; ++index) {
    const char* key = entries.keys[index];
    if (key == nullptr) continue;
    const mpv_node& value = entries.values[index];
    if (std::strcmp(key, "gamma") == 0) {
      if (value.format == MPV_FORMAT_STRING && value.u.string != nullptr) {
        if (std::strcmp(value.u.string, "pq") == 0) {
          metadata.transfer = m3u_tv_mpv_plane::SourceTransfer::kPq;
        } else if (std::strcmp(value.u.string, "hlg") == 0) {
          metadata.transfer = m3u_tv_mpv_plane::SourceTransfer::kHlg;
        }
      }
    } else if (std::strcmp(key, "primaries") == 0) {
      if (value.format == MPV_FORMAT_STRING && value.u.string != nullptr &&
          std::strcmp(value.u.string, "bt.2020") == 0) {
        metadata.primaries = m3u_tv_mpv_plane::SourcePrimaries::kBt2020;
      }
    } else if (std::strcmp(key, "max-cll") == 0) {
      as_positive_uint32(value, &metadata.max_cll);
    } else if (std::strcmp(key, "max-fall") == 0) {
      as_positive_uint32(value, &metadata.max_fall);
    } else if (std::strcmp(key, "max-luma") == 0) {
      as_positive_uint32(value, &metadata.max_luminance);
    } else if (std::strcmp(key, "min-luma") == 0) {
      // The mastering floor is the one luminance a source may legitimately
      // state as zero, so it is taken on its own terms.
      double parsed = 0.0;
      if (as_double(value, &parsed) && parsed >= 0.0) metadata.min_luminance = parsed;
    }
  }
  return metadata;
}

// Switches mpv's output color-space properties to match `transfer`/
// `target_peak_nits`, synchronously via the same `mpv_command(["set", ...])`
// pattern Control() already uses for every other runtime property. Adapted
// from the *values* Plezy's MpvPlayer::SetHdrOutput applies (mpv_player.cc);
// not its async property-sequence-with-rollback machinery, which exists
// there to arbitrate rapidly overlapping user-driven HDR toggle requests.
// This app has no such toggle -- HDR is applied automatically whenever
// DecideHdr says so -- so a single serialized synchronous set is equivalent
// and far simpler; mpv_command is documented as blocking, unlike
// mpv_command_async.
void ApplyMpvOutputColorProperties(
    PlayerInstance* player, m3u_tv_mpv_plane::SourceTransfer transfer, uint32_t target_peak_nits) {
  if (player == nullptr || player->api == nullptr || player->api->command == nullptr || player->handle == nullptr) {
    return;
  }
  const bool enabled = transfer != m3u_tv_mpv_plane::SourceTransfer::kSdr;
  const bool tone_map_here =
      target_peak_nits >= 10 && target_peak_nits <= m3u_tv_mpv_plane::kPqMaxLuminanceNits;
  const std::string peak = tone_map_here ? std::to_string(target_peak_nits) : std::string("auto");
  const char* primaries = enabled ? "bt.2020" : "auto";
  const char* curve = transfer == m3u_tv_mpv_plane::SourceTransfer::kHlg
                          ? "hlg"
                          : (transfer == m3u_tv_mpv_plane::SourceTransfer::kPq ? "pq" : (tone_map_here ? "srgb" : "auto"));
  // mobius only while mpv is doing the tone-mapping itself for an undescribed
  // SDR target; anywhere else auto is the honest answer (see the reasoning in
  // Plezy's mpv_player.cc beside this same table of values).
  const char* tone_mapping = (tone_map_here && !enabled) ? "mobius" : "auto";

  g_message("MPV: output color target peak=%s prim=%s trc=%s tone-mapping=%s", peak.c_str(), primaries, curve, tone_mapping);
  const char* trc_command[] = {"set", "target-trc", curve, nullptr};
  player->api->command(player->handle, trc_command);
  const char* prim_command[] = {"set", "target-prim", primaries, nullptr};
  player->api->command(player->handle, prim_command);
  const char* tone_mapping_command[] = {"set", "tone-mapping", tone_mapping, nullptr};
  player->api->command(player->handle, tone_mapping_command);
  const char* peak_command[] = {"set", "target-peak", peak.c_str(), nullptr};
  player->api->command(player->handle, peak_command);
}

// Runs the HDR decision (hdr_metadata.h's DecideHdr) for `source` against
// `player`'s Wayland plane and applies it: stages an image-description
// transition on the plane, switches mpv's output color space once it
// settles, then commits the transition so the first buffer rendered in the
// new color space is the one the compositor is told carries it. Must only
// be called on the GTK main thread.
//
// `allowed` mirrors the user-facing HDR toggle (player->hdr_user_enabled,
// set via the `setHdrEnabled` control method) -- off forces `describe` to
// false in DecideHdr, which routes the source back through the SDR path
// below exactly like an output that cannot carry HDR at all.
void ApplyHdrForVideoParams(int64_t player_id, const m3u_tv_mpv_plane::HdrMetadata& source) {
  auto it = g_players.find(player_id);
  if (it == g_players.end()) return;
  PlayerInstance* player = it->second.get();
  if (!player->using_gpu_plane || player->gpu_plane == nullptr) return;
  m3u_tv_mpv_plane::WaylandVideoSurface* plane = player->gpu_plane.get();
  player->last_source_hdr = source;

  m3u_tv_mpv_plane::HdrInputs inputs;
  inputs.allowed = player->hdr_user_enabled;
  inputs.client_can_describe = plane->supports_hdr();
  inputs.output_is_hdr = plane->output_is_hdr();
  inputs.source_describable = plane->CanDescribeSource(source);
  // The compositor developers' recommended mode: mpv tone-maps to the
  // display's real peak (learned from the compositor's preferred
  // description) and declares that same peak, leaving the compositor an
  // identity transform.
  inputs.requested = m3u_tv_mpv_plane::HdrToneMapping::kPlayer;
  inputs.display_peak_nits = plane->preferred().max_luminance;
  inputs.sdr_reference_nits = plane->preferred().reference_luminance;

  const m3u_tv_mpv_plane::HdrDecision decision = m3u_tv_mpv_plane::DecideHdr(inputs, source);
  const m3u_tv_mpv_plane::HdrMetadata described = decision.tone_map_in_player
      ? m3u_tv_mpv_plane::DescribeTonemappedTo(source, decision.target_peak_nits)
      : source;
  const m3u_tv_mpv_plane::SourceTransfer transfer =
      decision.describe ? described.transfer : m3u_tv_mpv_plane::SourceTransfer::kSdr;

  plane->BeginHdrTransition(
      decision.describe, described, [player_id, decision, transfer](uint64_t token, bool staged) {
        auto inner_it = g_players.find(player_id);
        if (inner_it == g_players.end()) return;
        PlayerInstance* inner_player = inner_it->second.get();
        if (!inner_player->using_gpu_plane || inner_player->gpu_plane == nullptr) return;
        m3u_tv_mpv_plane::WaylandVideoSurface* inner_plane = inner_player->gpu_plane.get();
        if (!staged) {
          inner_plane->AbortHdrTransition(token);
          ScheduleGpuRender(inner_player);
          return;
        }
        ApplyMpvOutputColorProperties(inner_player, transfer, decision.target_peak_nits);
        if (inner_plane->CommitHdrTransition(token)) ScheduleGpuRender(inner_player);
      });
}

gboolean ApplyHdrForVideoParamsIdle(gpointer data) {
  auto* dispatch = static_cast<std::pair<int64_t, m3u_tv_mpv_plane::HdrMetadata>*>(data);
  ApplyHdrForVideoParams(dispatch->first, dispatch->second);
  delete dispatch;
  return G_SOURCE_REMOVE;
}

// Marshals an mpv-thread `video-params` observation onto the GTK main
// thread, where the plane and mpv's output properties may be touched.
void DispatchHdrUpdate(int64_t player_id, const m3u_tv_mpv_plane::HdrMetadata& source) {
  auto* dispatch = new std::pair<int64_t, m3u_tv_mpv_plane::HdrMetadata>(player_id, source);
  if (!DispatchOnGtkMain(ApplyHdrForVideoParamsIdle, dispatch)) delete dispatch;
}
#endif  // HAVE_WAYLAND_MPV_PLANE

// Issues an mpv `sub-add` command for each entry of the `externalSubtitles`
// list argument (see `lib/playback/player_adapter.dart`'s
// `PlaybackSource.externalSubtitles`), matching the sub-add/sub-auto=fuzzy
// support already present on the macOS/iOS/tvOS/Android native mpv backends.
void AddExternalSubtitles(LibmpvApi& api, mpv_handle* handle, FlValue* args) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) return;
  FlValue* subtitles = fl_value_lookup_string(args, "externalSubtitles");
  if (subtitles == nullptr || fl_value_get_type(subtitles) != FL_VALUE_TYPE_LIST) return;

  const size_t count = fl_value_get_length(subtitles);
  for (size_t i = 0; i < count; ++i) {
    FlValue* entry = fl_value_get_list_value(subtitles, i);
    const std::string uri = StringArg(entry, "uri");
    if (uri.empty()) continue;
    const std::string title = StringArg(entry, "title");
    const std::string language = StringArg(entry, "language");
    std::vector<const char*> sub_args = {"sub-add", uri.c_str(), "auto"};
    if (!title.empty()) {
      sub_args.push_back(title.c_str());
      if (!language.empty()) sub_args.push_back(language.c_str());
    }
    sub_args.push_back(nullptr);
    api.command(handle, sub_args.data());
  }
}

FlMethodResponse* LoadFailure(const char* code, const std::string& error) {
  g_autoptr(FlValue) result = fl_value_new_map();
  fl_value_set_string_take(result, "ok", fl_value_new_bool(FALSE));
  fl_value_set_string_take(result, "code", fl_value_new_string(code));
  fl_value_set_string_take(result, "error", fl_value_new_string(error.c_str()));
  return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

gboolean MpvTextureCopyPixels(FlPixelBufferTexture* texture,
                               const uint8_t** buffer, uint32_t* width,
                               uint32_t* height, GError** error) {
  (void)error;
  MpvTexture* self = reinterpret_cast<MpvTexture*>(texture);
  CopyPixelsContext* context = self->copy_context;
  if (context == nullptr) return FALSE;
  context->Retain();
  const gboolean copied = context->CopyPixels(buffer, width, height);
  context->Release();
  return copied;
}

void mpv_texture_finalize(GObject* object) {
  MpvTexture* self = reinterpret_cast<MpvTexture*>(object);
  if (self->copy_context != nullptr) {
    self->copy_context->Release();
    self->copy_context = nullptr;
  }
  G_OBJECT_CLASS(mpv_texture_parent_class)->finalize(object);
}

void mpv_texture_class_init(MpvTextureClass* klass) {
  FL_PIXEL_BUFFER_TEXTURE_CLASS(klass)->copy_pixels = MpvTextureCopyPixels;
  G_OBJECT_CLASS(klass)->finalize = mpv_texture_finalize;
}

void mpv_texture_init(MpvTexture* self) { self->copy_context = nullptr; }

bool DoubleProperty(PlayerInstance* player, const char* name, double* value) {
  if (player == nullptr || player->api == nullptr ||
      player->api->get_property == nullptr) {
    return false;
  }
  double current = 0.0;
  const int rc = player->api->get_property(
      player->handle, name, MPV_FORMAT_DOUBLE, &current);
  if (rc < 0 || current <= 0.0) return false;
  *value = current;
  return true;
}

bool FlagProperty(PlayerInstance* player, const char* name, bool* value) {
  if (player == nullptr || player->api == nullptr ||
      player->api->get_property == nullptr) {
    return false;
  }
  int current = 0;
  const int rc = player->api->get_property(
      player->handle, name, MPV_FORMAT_FLAG, &current);
  if (rc < 0) return false;
  *value = current != 0;
  return true;
}

bool StringProperty(PlayerInstance* player, const char* name,
                    std::string* value) {
  if (player == nullptr || player->api == nullptr ||
      player->api->get_property == nullptr || player->api->free == nullptr) {
    return false;
  }
  char* current = nullptr;
  const int rc = player->api->get_property(
      player->handle, name, MPV_FORMAT_STRING, &current);
  if (rc < 0 || current == nullptr) return false;
  *value = current;
  player->api->free(current);
  return true;
}

FlValue* VideoAspectRatioResult(PlayerInstance* player) {
  g_autoptr(FlValue) result = fl_value_new_map();
  fl_value_set_string_take(result, "ok", fl_value_new_bool(TRUE));

  double aspect = 0.0;
  if (DoubleProperty(player, "video-params/aspect", &aspect)) {
    fl_value_set_string_take(result, "videoAspectRatio",
                             fl_value_new_float(aspect));
  }

  double width = 0.0;
  double height = 0.0;
  if (DoubleProperty(player, "dwidth", &width) &&
      DoubleProperty(player, "dheight", &height)) {
    fl_value_set_string_take(result, "videoWidth", fl_value_new_float(width));
    fl_value_set_string_take(result, "videoHeight", fl_value_new_float(height));
    if (aspect <= 0.0) {
      fl_value_set_string_take(result, "videoAspectRatio",
                               fl_value_new_float(width / height));
    }
  }
  return fl_value_ref(result);
}

void RenderUpdate(void* data) {
  auto* texture_state = static_cast<TextureDispatchState*>(data);
  if (texture_state != nullptr) texture_state->QueueFrame();
}

FlValue* BuildEventValue(const EventSnapshot& snapshot) {
  g_autoptr(FlValue) event = fl_value_new_map();
  fl_value_set_string_take(event, "schemaVersion", fl_value_new_int(2));
  fl_value_set_string_take(event, "handle", fl_value_new_int(snapshot.handle));
  fl_value_set_string_take(event, "sequence", fl_value_new_int(snapshot.sequence));
  fl_value_set_string_take(event, "kind", fl_value_new_string(snapshot.kind.c_str()));
  if (snapshot.position > 0.0) {
    fl_value_set_string_take(event, "positionMs", fl_value_new_int(static_cast<int64_t>(snapshot.position * 1000.0)));
  }
  if (snapshot.duration > 0.0) {
    fl_value_set_string_take(event, "durationMs", fl_value_new_int(static_cast<int64_t>(snapshot.duration * 1000.0)));
  }
  fl_value_set_string_take(event, "paused", fl_value_new_bool(snapshot.paused));
  fl_value_set_string_take(event, "buffering", fl_value_new_bool(snapshot.buffering));
  fl_value_set_string_take(event, "eof", fl_value_new_bool(snapshot.eof));
  if (snapshot.video_aspect_ratio > 0.0) {
    fl_value_set_string_take(event, "videoAspectRatio", fl_value_new_float(snapshot.video_aspect_ratio));
  }
  if (snapshot.speed > 0.0) {
    fl_value_set_string_take(event, "speed", fl_value_new_float(snapshot.speed));
  }
  if (snapshot.has_aid) {
    fl_value_set_string_take(event, "aid", fl_value_new_string(snapshot.aid.c_str()));
  }
  if (snapshot.has_sid) {
    fl_value_set_string_take(event, "sid", fl_value_new_string(snapshot.sid.c_str()));
  }
  if (snapshot.has_track_lists) {
    auto build_tracks = [](const std::vector<EventSnapshot::Track>& tracks) {
      FlValue* values = fl_value_new_list();
      for (const EventSnapshot::Track& track : tracks) {
        FlValue* value = fl_value_new_map();
        fl_value_set_string_take(value, "id", fl_value_new_string(track.id.c_str()));
        fl_value_set_string_take(value, "label", fl_value_new_string(track.label.c_str()));
        if (!track.language.empty()) {
          fl_value_set_string_take(value, "language",
                                   fl_value_new_string(track.language.c_str()));
        }
        fl_value_append_take(values, value);
      }
      return values;
    };
    fl_value_set_string_take(event, "audioTracks",
                             build_tracks(snapshot.audio_tracks));
    fl_value_set_string_take(event, "subtitleTracks",
                             build_tracks(snapshot.subtitle_tracks));
  }
  if (!snapshot.message.empty()) {
    fl_value_set_string_take(event, "message", fl_value_new_string(snapshot.message.c_str()));
  }
  if (!snapshot.code.empty()) {
    fl_value_set_string_take(event, "code", fl_value_new_string(snapshot.code.c_str()));
  }
  fl_value_set_string_take(event, "recoverable", fl_value_new_bool(snapshot.recoverable));
  return fl_value_ref(event);
}

static gboolean SendEventSnapshotOnGtkThread(gpointer user_data) {
  std::unique_ptr<EventDispatch> dispatch(static_cast<EventDispatch*>(user_data));
  const std::shared_ptr<EventDispatchState>& state = dispatch->state;
  if (!state->active.load(std::memory_order_acquire) ||
      state->event_channel == nullptr) {
    return G_SOURCE_REMOVE;
  }

  g_autoptr(FlValue) event = BuildEventValue(dispatch->snapshot);
  g_autoptr(GError) error = nullptr;
  fl_event_channel_send(state->event_channel, event, nullptr, &error);
  if (error != nullptr) {
    g_warning("Failed to send event: %s", error->message);
  }
  return G_SOURCE_REMOVE;
}

void PlayerInstance::QueueEvent(EventSnapshot snapshot) {
  if (disposing.load(std::memory_order_acquire) ||
      event_dispatch_state == nullptr ||
      !event_dispatch_state->active.load(std::memory_order_acquire)) {
    return;
  }
  auto* dispatch = new EventDispatch{event_dispatch_state, std::move(snapshot)};
  if (!DispatchOnGtkMain(SendEventSnapshotOnGtkThread, dispatch)) {
    delete dispatch;
  }
}

void PlayerInstance::ReadSnapshotProperties(EventSnapshot* snapshot) {
  snapshot->position = 0.0;
  snapshot->duration = 0.0;
  snapshot->paused = false;
  snapshot->buffering = false;
  snapshot->eof = false;
  snapshot->video_aspect_ratio = 0.0;
  snapshot->speed = 0.0;
  snapshot->aid.clear();
  snapshot->sid.clear();
  snapshot->has_aid = false;
  snapshot->has_sid = false;

  DoubleProperty(this, "time-pos", &snapshot->position);
  DoubleProperty(this, "duration", &snapshot->duration);
  FlagProperty(this, "pause", &snapshot->paused);
  bool paused_for_cache = false;
  FlagProperty(this, "paused-for-cache", &paused_for_cache);
  snapshot->buffering = paused_for_cache;
  FlagProperty(this, "eof-reached", &snapshot->eof);
  DoubleProperty(this, "speed", &snapshot->speed);

  double aspect = 0.0;
  if (DoubleProperty(this, "video-params/aspect", &aspect) && aspect > 0.0) {
    snapshot->video_aspect_ratio = aspect;
  } else {
    double width = 0.0;
    double height = 0.0;
    if (DoubleProperty(this, "dwidth", &width) && DoubleProperty(this, "dheight", &height) && height > 0.0) {
      snapshot->video_aspect_ratio = width / height;
    }
  }

  snapshot->has_aid = StringProperty(this, "aid", &snapshot->aid);
  snapshot->has_sid = StringProperty(this, "sid", &snapshot->sid);
}

std::string NormalizeTrackString(std::string value) {
  const auto first = std::find_if_not(
      value.begin(), value.end(),
      [](unsigned char character) { return std::isspace(character) != 0; });
  const auto last = std::find_if_not(
      value.rbegin(), value.rend(),
      [](unsigned char character) { return std::isspace(character) != 0; })
                        .base();
  return first < last ? std::string(first, last) : "";
}

const mpv_node* MapNodeValue(const mpv_node& node, const char* key) {
  if (node.format != MPV_FORMAT_NODE_MAP || node.u.list == nullptr ||
      node.u.list->keys == nullptr || node.u.list->values == nullptr) {
    return nullptr;
  }
  for (int index = 0; index < node.u.list->num; ++index) {
    if (node.u.list->keys[index] != nullptr &&
        std::strcmp(node.u.list->keys[index], key) == 0) {
      return &node.u.list->values[index];
    }
  }
  return nullptr;
}

std::string TrackNodeString(const mpv_node* node) {
  if (node == nullptr) return "";
  if (node->format == MPV_FORMAT_STRING && node->u.string != nullptr) {
    return NormalizeTrackString(node->u.string);
  }
  if (node->format == MPV_FORMAT_INT64) {
    return std::to_string(node->u.int64);
  }
  return "";
}

void PlayerInstance::ReadTrackLists(EventSnapshot* snapshot) {
  snapshot->audio_tracks.clear();
  snapshot->subtitle_tracks.clear();
  snapshot->has_track_lists = false;
  if (api == nullptr || api->get_property == nullptr ||
      api->free_node_contents == nullptr) {
    return;
  }

  mpv_node node{};
  if (api->get_property(handle, "track-list", MPV_FORMAT_NODE, &node) < 0) {
    return;
  }
  snapshot->has_track_lists = true;
  if (node.format == MPV_FORMAT_NODE_ARRAY && node.u.list != nullptr &&
      node.u.list->values != nullptr) {
    for (int index = 0; index < node.u.list->num; ++index) {
      const mpv_node& item = node.u.list->values[index];
      const std::string type = TrackNodeString(MapNodeValue(item, "type"));
      const std::string id = TrackNodeString(MapNodeValue(item, "id"));
      if (id.empty() || (type != "audio" && type != "sub")) continue;
      const std::string language =
          TrackNodeString(MapNodeValue(item, "lang"));
      const std::string label = TrackNodeString(MapNodeValue(item, "title"));
      const std::string normalized_label = label.empty() ? language : label;
      EventSnapshot::Track track{
          id, normalized_label.empty() ? id : normalized_label, language};
      if (type == "audio") {
        snapshot->audio_tracks.push_back(std::move(track));
      } else if (type == "sub") {
        snapshot->subtitle_tracks.push_back(std::move(track));
      }
    }
  }
  api->free_node_contents(&node);
}

void PlayerInstance::StartEventThread() {
  event_thread = std::thread([this]() {
    if (api == nullptr || api->observe_property == nullptr) return;

    // Observe relevant properties.
    api->observe_property(handle, 0, "time-pos", MPV_FORMAT_DOUBLE);
    api->observe_property(handle, 0, "duration", MPV_FORMAT_DOUBLE);
    api->observe_property(handle, 0, "pause", MPV_FORMAT_FLAG);
    api->observe_property(handle, 0, "paused-for-cache", MPV_FORMAT_FLAG);
    api->observe_property(handle, 0, "eof-reached", MPV_FORMAT_FLAG);
    api->observe_property(handle, 0, "speed", MPV_FORMAT_DOUBLE);
    api->observe_property(handle, 0, "video-params/aspect", MPV_FORMAT_DOUBLE);
    api->observe_property(handle, 0, "dwidth", MPV_FORMAT_DOUBLE);
    api->observe_property(handle, 0, "dheight", MPV_FORMAT_DOUBLE);
    api->observe_property(handle, 0, "aid", MPV_FORMAT_STRING);
    api->observe_property(handle, 0, "sid", MPV_FORMAT_STRING);
#ifdef HAVE_WAYLAND_MPV_PLANE
    // Only the GPU/Wayland-plane path can describe HDR to the compositor; the
    // software pixel-buffer path has no plane to describe it to.
    if (using_gpu_plane) {
      api->observe_property(handle, kVideoParamsHdrUserdata, "video-params", MPV_FORMAT_NODE);
    }
#endif

    while (!disposing.load()) {
      mpv_event* ev = api->wait_event(handle, 0.05);
      if (ev == nullptr) continue;

      if (ev->event_id == 0) {  // MPV_EVENT_NONE
        continue;
      }

      EventSnapshot snapshot;
      snapshot.handle = id;

      // Check for queue overflow.
      if (ev->event_id == 24) {  // MPV_EVENT_QUEUE_OVERFLOW
        snapshot.sequence = sequence.fetch_add(1);
        snapshot.kind = "ERROR";
        snapshot.message = "mpv event queue overflow";
        snapshot.code = "event-queue-overflow";
        snapshot.recoverable = true;
        QueueEvent(snapshot);
        continue;
      }

      // Property change events.
      if (ev->event_id == 22) {  // MPV_EVENT_PROPERTY_CHANGE
#ifdef HAVE_WAYLAND_MPV_PLANE
        if (ev->reply_userdata == kVideoParamsHdrUserdata) {
          const auto* property = static_cast<const mpv_event_property*>(ev->data);
          if (property != nullptr && property->format == MPV_FORMAT_NODE && property->data != nullptr) {
            DispatchHdrUpdate(id, ParseVideoParamsHdrMetadata(static_cast<const mpv_node*>(property->data)));
          }
          continue;
        }
#endif
        snapshot.sequence = sequence.fetch_add(1);
        snapshot.kind = "PLAYBACK_RESTART";
        ReadSnapshotProperties(&snapshot);
        QueueEvent(snapshot);
        continue;
      }

      // Map lifecycle events.
      switch (ev->event_id) {
        case 6:   // MPV_EVENT_START_FILE
          snapshot.sequence = sequence.fetch_add(1);
          snapshot.kind = "START_FILE";
          ReadSnapshotProperties(&snapshot);
          QueueEvent(snapshot);
          break;
        case 8:   // MPV_EVENT_FILE_LOADED
          snapshot.sequence = sequence.fetch_add(1);
          snapshot.kind = "FILE_LOADED";
          ReadSnapshotProperties(&snapshot);
          ReadTrackLists(&snapshot);
          QueueEvent(snapshot);
          break;
        case 21:  // MPV_EVENT_PLAYBACK_RESTART
          snapshot.sequence = sequence.fetch_add(1);
          snapshot.kind = "PLAYBACK_RESTART";
          ReadSnapshotProperties(&snapshot);
          QueueEvent(snapshot);
          break;
        case 17:  // MPV_EVENT_VIDEO_RECONFIG
          snapshot.sequence = sequence.fetch_add(1);
          snapshot.kind = "VIDEO_RECONFIG";
          ReadSnapshotProperties(&snapshot);
          QueueEvent(snapshot);
          break;
        case MPV_EVENT_END_FILE: {
          snapshot.sequence = sequence.fetch_add(1);
          const auto* end_file = static_cast<const mpv_event_end_file*>(ev->data);
          const int end_file_reason =
              end_file == nullptr ? -1 : end_file->reason;
          switch (end_file_reason) {
            case MPV_END_FILE_REASON_EOF:
              snapshot.kind = "END_FILE";
              break;
            case MPV_END_FILE_REASON_STOP:
              snapshot.kind = "STOP";
              break;
            case MPV_END_FILE_REASON_QUIT:
              snapshot.kind = "QUIT";
              break;
            case MPV_END_FILE_REASON_ERROR:
              snapshot.kind = "ERROR";
              snapshot.message = "libmpv end-file error " +
                                 std::to_string(end_file->error);
              snapshot.code = "mpv-end-file-error";
              snapshot.recoverable = true;
              break;
            case MPV_END_FILE_REASON_REDIRECT:
              continue;
            default:
              snapshot.kind = "ERROR";
              snapshot.message = "unknown libmpv end-file reason " +
                                 std::to_string(end_file_reason);
              snapshot.code = "mpv-end-file-unknown-reason";
              snapshot.recoverable = true;
              break;
          }
          ReadSnapshotProperties(&snapshot);
          QueueEvent(snapshot);
          break;
        }
        case 1:   // MPV_EVENT_SHUTDOWN
          snapshot.sequence = sequence.fetch_add(1);
          snapshot.kind = "SHUTDOWN";
          ReadSnapshotProperties(&snapshot);
          QueueEvent(snapshot);
          disposing.store(true);
          break;
        default:
          // Ignore unknown events to avoid treating them as errors.
          break;
      }
    }
  });
}

FlMethodResponse* Load(FlValue* args) {
  LibmpvApi& api = Api();
  if (!api.available()) {
    return LoadFailure(kBackendUnavailableCode, api.error);
  }
  if (g_texture_registrar == nullptr) {
    return LoadFailure(kBackendUnavailableCode, "Flutter texture registrar unavailable");
  }
  const std::shared_ptr<EventDispatchState> event_dispatch_state =
      g_event_channel_state == nullptr
          ? nullptr
          : g_event_channel_state->CreateDispatchState();
  if (event_dispatch_state == nullptr) {
    return LoadFailure(kBackendUnavailableCode, "Flutter event channel unavailable");
  }

  setlocale(LC_NUMERIC, "C");
  mpv_handle* handle = api.create();
  if (handle == nullptr) {
    return LoadFailure("desktop-libmpv-load-failed", MpvCreateNullError(api));
  }

  api.set_option_string(handle, "terminal", "no");
  api.set_option_string(handle, "config", "no");
  api.set_option_string(handle, "vo", "libmpv");
  api.set_option_string(handle, "hwdec", "auto-safe");
  api.set_option_string(handle, "idle", "yes");
  api.set_option_string(handle, "keepaspect", "no");
  api.set_option_string(handle, "sub-auto", "fuzzy");
  // This app only ever plays direct/proxy/server URLs, never generic web
  // pages, and never bundles a youtube-dl/yt-dlp binary on any platform --
  // mpv's built-in ytdl_hook script would otherwise try (and fail to find)
  // one on every URL load, surfacing as an opaque "ytdl_hook: youtube-dl
  // failed: not found or not enough permissions" end-file error even for
  // plain local/network media.
  api.set_option_string(handle, "ytdl", "no");
  std::string user_agent = StringArg(args, "userAgent");
  if (!user_agent.empty()) api.set_option_string(handle, "user-agent", user_agent.c_str());
  std::string headers = HeaderString(args);
  if (!headers.empty()) api.set_option_string(handle, "http-header-fields", headers.c_str());

  int rc = api.initialize(handle);
  if (rc < 0) {
    api.terminate_destroy(handle);
    return LoadFailure("desktop-libmpv-load-failed", "mpv_initialize failed");
  }

#ifdef HAVE_WAYLAND_MPV_PLANE
  // GPU path: a Wayland subsurface driven by mpv's OpenGL render API,
  // bypassing Flutter's texture bridge entirely (see wayland_video_surface.h
  // for why -- Flutter's Linux embedder has no platform-view API, and its
  // FlTextureGL is capped to an 8-bit RGBA format). Falls through to the
  // proven software pixel-buffer path below on X11, or on any failure.
  if (g_flutter_view != nullptr &&
      m3u_tv_mpv_plane::WaylandVideoSurface::IsSupported(gtk_widget_get_display(GTK_WIDGET(g_flutter_view)))) {
    auto plane = std::make_unique<m3u_tv_mpv_plane::WaylandVideoSurface>();
    std::string plane_error;
    if (plane->Create(GTK_WIDGET(g_flutter_view), &plane_error)) {
      EGLContext gpu_context = EGL_NO_CONTEXT;
      mpv_render_context* gpu_render_context = nullptr;
      std::string render_error;
      if (CreateGpuRenderContext(api, handle, *plane, &gpu_context, &gpu_render_context, &render_error)) {
        const int64_t id = g_next_handle++;
        auto player = std::make_unique<PlayerInstance>(&api, event_dispatch_state, handle, gpu_render_context,
                                                        gpu_context, std::move(plane), id);
        AttachGpuRenderCallback(api, gpu_render_context, player.get());
        player->gpu_plane->SetFrameCallback([raw = player.get()]() { ScheduleGpuRender(raw); });
        // Resumes presenting after the transition watchdog abandons a
        // colour change the compositor went silent on -- nothing else would
        // prompt a re-render in that case (see WaylandVideoSurface's own
        // comment on SetForcedRenderCallback).
        player->gpu_plane->SetForcedRenderCallback([raw = player.get()]() { ScheduleGpuRender(raw); });
        // Re-decides HDR for the same source when the compositor's preferred
        // description changes under us (a monitor move, or HDR being
        // switched on/off at the OS level) -- looked up by id, not a raw
        // capture, since this can fire long after Load() returns.
        player->gpu_plane->SetPreferredChangedCallback([id]() {
          auto it = g_players.find(id);
          if (it == g_players.end()) return;
          ApplyHdrForVideoParams(id, it->second->last_source_hdr);
        });
        player->StartEventThread();

        std::string uri = StringArg(args, "uri");
        const int64_t start_position_ms = IntArg(args, "startPositionMs");
        // Set via the `set` command, not smuggled into `loadfile`'s argv:
        // `loadfile <url> [<flags> [<index> [<options>]]]` has an integer
        // `<index>` slot BEFORE `<options>`, so a string like "start=90.5"
        // placed right after "replace" lands in the index slot, not the
        // options slot. Some mpv builds tolerate this; a stricter one
        // rejects it outright with a generic "mpv loadfile command failed".
        if (start_position_ms > 0) {
          const std::string start_value = std::to_string(static_cast<double>(start_position_ms) / 1000.0);
          const char* set_start_args[] = {"set", "start", start_value.c_str(), nullptr};
          api.command(handle, set_start_args);
        }
        const char* load_args[] = {"loadfile", uri.c_str(), "replace", nullptr};
        rc = api.command(handle, load_args);
        if (rc < 0) {
          return LoadFailure("desktop-libmpv-load-failed", "mpv loadfile command failed");
        }
        AddExternalSubtitles(api, handle, args);
        player->gpu_plane->SetVisible(true);

        g_autoptr(FlValue) result = fl_value_new_map();
        fl_value_set_string_take(result, "ok", fl_value_new_bool(TRUE));
        fl_value_set_string_take(result, "handle", fl_value_new_int(id));
        fl_value_set_string_take(result, "usesNativePlane", fl_value_new_bool(TRUE));
        fl_value_set_string_take(result, "display",
                                 fl_value_new_string("Wayland GPU video plane (OpenGL render API)"));
        g_players[id] = std::move(player);
        return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
      }
      g_warning("MPV video plane: GPU render context unavailable (%s); falling back to the software texture path",
               render_error.c_str());
      plane->Destroy();
    } else {
      g_message("MPV video plane: %s; falling back to the software texture path", plane_error.c_str());
    }
  }
#endif  // HAVE_WAYLAND_MPV_PLANE

  const char* api_type = "sw";
  const DisplayInfo display = GetDisplayInfo();
  std::vector<mpv_render_param> create_params;
  create_params.push_back({MPV_RENDER_PARAM_API_TYPE, const_cast<char*>(api_type)});
  if (display.wayland_display != nullptr) {
    create_params.push_back({MPV_RENDER_PARAM_WL_DISPLAY, display.wayland_display});
  }
  if (display.x11_display != nullptr) {
    create_params.push_back({MPV_RENDER_PARAM_X11_DISPLAY, display.x11_display});
  }
  create_params.push_back({MPV_RENDER_PARAM_INVALID, nullptr});

  mpv_render_context* render_context = nullptr;
  rc = api.render_context_create(&render_context, handle, create_params.data());
  if (rc < 0 || render_context == nullptr) {
    api.terminate_destroy(handle);
    return LoadFailure("desktop-libmpv-load-failed", "mpv_render_context_create failed");
  }

  MpvTexture* texture = reinterpret_cast<MpvTexture*>(g_object_new(mpv_texture_get_type(), nullptr));
  if (texture == nullptr) {
    api.render_context_free(render_context);
    api.terminate_destroy(handle);
    return LoadFailure("desktop-libmpv-load-failed", "Flutter pixel buffer texture allocation failed");
  }
  if (!fl_texture_registrar_register_texture(g_texture_registrar, FL_TEXTURE(texture))) {
    g_object_unref(texture);
    api.render_context_free(render_context);
    api.terminate_destroy(handle);
    return LoadFailure("desktop-libmpv-load-failed", "Flutter texture registration failed");
  }
  const int64_t texture_id = fl_texture_get_id(FL_TEXTURE(texture));

  const int64_t id = g_next_handle++;
  auto player = std::make_unique<PlayerInstance>(&api, g_texture_registrar,
                                                 event_dispatch_state, handle,
                                                 render_context, texture,
                                                 texture_id, id);
  player->copy_context->SetUpdateCallback(RenderUpdate, player->texture_state);
  player->StartEventThread();

  std::string uri = StringArg(args, "uri");
  const int64_t start_position_ms = IntArg(args, "startPositionMs");
  // See the matching comment on the GPU-path load above.
  if (start_position_ms > 0) {
    const std::string start_value = std::to_string(static_cast<double>(start_position_ms) / 1000.0);
    const char* set_start_args[] = {"set", "start", start_value.c_str(), nullptr};
    api.command(handle, set_start_args);
  }
  const char* load_args[] = {"loadfile", uri.c_str(), "replace", nullptr};
  rc = api.command(handle, load_args);
  if (rc < 0) {
    return LoadFailure("desktop-libmpv-load-failed", "mpv loadfile command failed");
  }
  AddExternalSubtitles(api, handle, args);

  g_players[id] = std::move(player);
  g_autoptr(FlValue) result = fl_value_new_map();
  fl_value_set_string_take(result, "ok", fl_value_new_bool(TRUE));
  fl_value_set_string_take(result, "handle", fl_value_new_int(id));
  fl_value_set_string_take(result, "textureId", fl_value_new_int(texture_id));
  fl_value_set_string_take(result, "display", fl_value_new_string(DisplayDetails(display).c_str()));
  return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

FlMethodResponse* Control(const gchar* method, FlValue* args) {
  const int64_t id = IntArg(args, "handle");
  auto it = g_players.find(id);
  if (it == g_players.end()) return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  PlayerInstance* player = it->second.get();
#ifdef HAVE_WAYLAND_MPV_PLANE
  if (g_strcmp0(method, "setVideoRect") == 0) {
    // Reported by Dart on every layout of the widget hosting this backend
    // (see native_video_surface.dart's NativePlaneVideoSurface); a no-op for
    // players still on the software texture path.
    if (player->using_gpu_plane && player->gpu_plane != nullptr) {
      const int32_t x = static_cast<int32_t>(IntArg(args, "x"));
      const int32_t y = static_cast<int32_t>(IntArg(args, "y"));
      const int32_t width = static_cast<int32_t>(IntArg(args, "width"));
      const int32_t height = static_cast<int32_t>(IntArg(args, "height"));
      const int32_t scale = static_cast<int32_t>(IntArg(args, "scale"));
      player->gpu_plane->SetRect(x, y, width, height, scale > 0 ? scale : 1);
      ScheduleGpuRender(player);
    }
    return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  }
#endif
  if (g_strcmp0(method, "play") == 0) {
    const char* command[] = {"set", "pause", "no", nullptr};
    player->api->command(player->handle, command);
  } else if (g_strcmp0(method, "pause") == 0) {
    const char* command[] = {"set", "pause", "yes", nullptr};
    player->api->command(player->handle, command);
  } else if (g_strcmp0(method, "seek") == 0) {
    const double seconds = static_cast<double>(IntArg(args, "positionMs")) / 1000.0;
    const std::string value = std::to_string(seconds);
    const char* command[] = {"seek", value.c_str(), "absolute", nullptr};
    player->api->command(player->handle, command);
  } else if (g_strcmp0(method, "stop") == 0) {
    const char* command[] = {"stop", nullptr};
    player->api->command(player->handle, command);
    EventSnapshot snapshot;
    snapshot.handle = player->id;
    snapshot.sequence = player->sequence.fetch_add(1);
    snapshot.kind = "STOP";
    player->ReadSnapshotProperties(&snapshot);
    player->QueueEvent(snapshot);
  } else if (g_strcmp0(method, "quit") == 0) {
    const char* command[] = {"quit", nullptr};
    player->api->command(player->handle, command);
    EventSnapshot snapshot;
    snapshot.handle = player->id;
    snapshot.sequence = player->sequence.fetch_add(1);
    snapshot.kind = "QUIT";
    player->ReadSnapshotProperties(&snapshot);
    player->QueueEvent(snapshot);
  } else if (g_strcmp0(method, "setAudioTrack") == 0) {
    const std::string track = StringArg(args, "trackId");
    const char* command[] = {"set", "aid", track.empty() ? "no" : track.c_str(), nullptr};
    player->api->command(player->handle, command);
    EventSnapshot snapshot;
    snapshot.handle = player->id;
    snapshot.sequence = player->sequence.fetch_add(1);
    snapshot.kind = "PLAYBACK_RESTART";
    player->ReadSnapshotProperties(&snapshot);
    player->ReadTrackLists(&snapshot);
    player->QueueEvent(snapshot);
  } else if (g_strcmp0(method, "setSubtitleTrack") == 0) {
    const std::string track = StringArg(args, "trackId");
    const char* command[] = {"set", "sid", track.empty() ? "no" : track.c_str(), nullptr};
    player->api->command(player->handle, command);
    EventSnapshot snapshot;
    snapshot.handle = player->id;
    snapshot.sequence = player->sequence.fetch_add(1);
    snapshot.kind = "PLAYBACK_RESTART";
    player->ReadSnapshotProperties(&snapshot);
    player->ReadTrackLists(&snapshot);
    player->QueueEvent(snapshot);
  } else if (g_strcmp0(method, "setPlaybackSpeed") == 0) {
    FlValue* value = args == nullptr ? nullptr : fl_value_lookup_string(args, "speed");
    const double speed = value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_FLOAT
                             ? fl_value_get_float(value)
                             : 1.0;
    const std::string speed_value = std::to_string(speed);
    const char* command[] = {"set", "speed", speed_value.c_str(), nullptr};
    player->api->command(player->handle, command);
  } else if (g_strcmp0(method, "setVolume") == 0) {
    FlValue* value = args == nullptr ? nullptr : fl_value_lookup_string(args, "volume");
    const double volume = value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_FLOAT
                               ? fl_value_get_float(value)
                               : 100.0;
    const std::string volume_value = std::to_string(volume);
    const char* command[] = {"set", "volume", volume_value.c_str(), nullptr};
    player->api->command(player->handle, command);
  } else if (g_strcmp0(method, "setHdrEnabled") == 0) {
#ifdef HAVE_WAYLAND_MPV_PLANE
    player->hdr_user_enabled = BoolArg(args, "enabled", true);
    if (player->using_gpu_plane) {
      ApplyHdrForVideoParams(player->id, player->last_source_hdr);
    }
#endif
  } else if (g_strcmp0(method, "getVideoAspectRatio") == 0) {
    g_autoptr(FlValue) result = VideoAspectRatioResult(player);
    return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (g_strcmp0(method, "dispose") == 0) {
    g_players.erase(it);
  }
  return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
}

void MethodCallHandler(FlMethodChannel* channel, FlMethodCall* method_call,
                       gpointer user_data) {
  (void)channel;
  (void)user_data;
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);
  g_autoptr(FlMethodResponse) response = nullptr;
  if (g_strcmp0(method, "probe") == 0) {
    g_autoptr(FlValue) result = ProbeResult();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (g_strcmp0(method, "load") == 0) {
    response = Load(args);
  } else {
    response = Control(method, args);
  }
  fl_method_call_respond(method_call, response, nullptr);
}

static FlMethodErrorResponse* EventChannelListen(FlEventChannel* channel,
                                                  FlValue* args,
                                                  gpointer user_data) {
  (void)channel;
  (void)args;
  (void)user_data;
  // Events are sent from the event thread; no setup needed here.
  return nullptr;
}

static FlMethodErrorResponse* EventChannelCancel(FlEventChannel* channel,
                                                  FlValue* args,
                                                  gpointer user_data) {
  (void)channel;
  (void)args;
  (void)user_data;
  return nullptr;
}

}  // namespace

void desktop_libmpv_backend_shutdown() {
  if (g_event_channel_state != nullptr) {
    g_event_channel_state->Deactivate();
  }
  g_players.clear();
  g_event_channel_state.reset();
  g_texture_registrar = nullptr;
#ifdef HAVE_WAYLAND_MPV_PLANE
  g_flutter_view = nullptr;
#endif
  if (g_gtk_main_context != nullptr) {
    g_main_context_unref(g_gtk_main_context);
    g_gtk_main_context = nullptr;
  }
}

void desktop_libmpv_backend_register(FlPluginRegistry* registry) {
  FlPluginRegistrar* registrar = fl_plugin_registry_get_registrar_for_plugin(
      registry, "DesktopLibmpvBackend");
  g_texture_registrar = fl_plugin_registrar_get_texture_registrar(registrar);
#ifdef HAVE_WAYLAND_MPV_PLANE
  g_flutter_view = fl_plugin_registrar_get_view(registrar);
#endif

  if (g_gtk_main_context == nullptr) {
    g_gtk_main_context = g_main_context_default();
    if (g_gtk_main_context != nullptr) {
      g_main_context_ref(g_gtk_main_context);
    }
  }

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();

  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar), kChannelName,
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, MethodCallHandler, nullptr,
                                            nullptr);

  g_autoptr(FlEventChannel) event_channel = fl_event_channel_new(
      fl_plugin_registrar_get_messenger(registrar), kEventChannelName,
      FL_METHOD_CODEC(codec));
  g_event_channel_state = std::make_shared<EventChannelState>(event_channel);
  fl_event_channel_set_stream_handlers(event_channel, EventChannelListen,
                                       EventChannelCancel, nullptr, nullptr);
}
