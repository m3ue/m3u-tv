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

struct mpv_event {
  int event_id;
  int error;
  uint64_t reply_userdata;
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
  std::atomic<int> sequence{0};
  CopyPixelsContext* copy_context = nullptr;
  TextureDispatchState* texture_state = nullptr;
};

LibmpvApi g_api;
FlTextureRegistrar* g_texture_registrar = nullptr;
std::shared_ptr<EventChannelState> g_event_channel_state;
int64_t g_next_handle = 1;
std::map<int64_t, std::unique_ptr<PlayerInstance>> g_players;

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
  std::string user_agent = StringArg(args, "userAgent");
  if (!user_agent.empty()) api.set_option_string(handle, "user-agent", user_agent.c_str());
  std::string headers = HeaderString(args);
  if (!headers.empty()) api.set_option_string(handle, "http-header-fields", headers.c_str());

  int rc = api.initialize(handle);
  if (rc < 0) {
    api.terminate_destroy(handle);
    return LoadFailure("desktop-libmpv-load-failed", "mpv_initialize failed");
  }

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
  std::string start_option;
  if (start_position_ms > 0) {
    const double seconds = static_cast<double>(start_position_ms) / 1000.0;
    start_option = "start=" + std::to_string(seconds);
  }
  const char* load_args[] = {"loadfile", uri.c_str(), "replace",
                             start_option.empty() ? nullptr : start_option.c_str(),
                             nullptr};
  rc = api.command(handle, load_args);
  if (rc < 0) {
    return LoadFailure("desktop-libmpv-load-failed", "mpv loadfile command failed");
  }

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
  if (g_gtk_main_context != nullptr) {
    g_main_context_unref(g_gtk_main_context);
    g_gtk_main_context = nullptr;
  }
}

void desktop_libmpv_backend_register(FlPluginRegistry* registry) {
  FlPluginRegistrar* registrar = fl_plugin_registry_get_registrar_for_plugin(
      registry, "DesktopLibmpvBackend");
  g_texture_registrar = fl_plugin_registrar_get_texture_registrar(registrar);

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
