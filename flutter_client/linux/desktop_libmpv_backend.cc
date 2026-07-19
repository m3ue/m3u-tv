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
#include <cstdint>
#include <cstring>
#include <map>
#include <memory>
#include <sstream>
#include <string>
#include <thread>
#include <vector>

namespace {

constexpr char kChannelName[] = "m3u_tv/desktop_libmpv";
constexpr char kEventChannelName[] = "m3u_tv/desktop_libmpv/events";
constexpr char kBackendUnavailableCode[] = "backend_unavailable";
constexpr uint32_t kTextureWidth = 1280;
constexpr uint32_t kTextureHeight = 720;
constexpr int kBytesPerPixel = 4;

using mpv_handle = struct mpv_handle;
using mpv_create_fn = mpv_handle* (*)();
using mpv_initialize_fn = int (*)(mpv_handle*);
using mpv_command_fn = int (*)(mpv_handle*, const char**);
using mpv_set_option_string_fn = int (*)(mpv_handle*, const char*, const char*);
using mpv_get_property_fn = int (*)(mpv_handle*, const char*, int, void*);
using mpv_free_fn = void (*)(void*);
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

constexpr int MPV_FORMAT_DOUBLE = 5;
constexpr int MPV_FORMAT_FLAG = 3;
constexpr int MPV_FORMAT_STRING = 1;

constexpr int MPV_RENDER_PARAM_INVALID = 0;
constexpr int MPV_RENDER_PARAM_API_TYPE = 1;
constexpr int MPV_RENDER_PARAM_X11_DISPLAY = 8;
constexpr int MPV_RENDER_PARAM_WL_DISPLAY = 9;
constexpr int MPV_RENDER_PARAM_ADVANCED_CONTROL = 10;
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
           get_property != nullptr && free != nullptr && terminate_destroy != nullptr &&
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

struct DisplayInfo {
  std::string window_system = "headless";
  std::string video_api = "software libmpv render API";
  void* x11_display = nullptr;
  void* wayland_display = nullptr;
  bool has_hardware_display = false;
};

struct PlayerInstance;
typedef struct _MpvTexture MpvTexture;
typedef struct _MpvTextureClass MpvTextureClass;

struct _MpvTexture {
  FlPixelBufferTexture parent_instance;
  PlayerInstance* player;
};

struct _MpvTextureClass {
  FlPixelBufferTextureClass parent_class;
};

G_DEFINE_TYPE(MpvTexture, mpv_texture, fl_pixel_buffer_texture_get_type())

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
  std::string message;
  std::string code;
  bool recoverable = false;
};

struct PlayerInstance {
  PlayerInstance(LibmpvApi* api, FlTextureRegistrar* texture_registrar,
                 FlEventChannel* event_channel,
                 mpv_handle* handle, mpv_render_context* render_context,
                 MpvTexture* texture, int64_t texture_id, int64_t id)
      : api(api),
        texture_registrar(texture_registrar),
        event_channel(event_channel),
        handle(handle),
        render_context(render_context),
        texture(texture),
        texture_id(texture_id),
        id(id),
        pixels(kTextureWidth * kTextureHeight * kBytesPerPixel, 0) {}

  ~PlayerInstance() {
    disposing.store(true);
    if (api != nullptr && api->wakeup != nullptr) {
      api->wakeup(handle);
    }
    if (event_thread.joinable()) {
      event_thread.join();
    }
    if (api != nullptr && api->unobserve_property != nullptr && handle != nullptr) {
      api->unobserve_property(handle, 0);
    }
    if (texture_registrar != nullptr && texture != nullptr) {
      fl_texture_registrar_unregister_texture(texture_registrar,
                                              FL_TEXTURE(texture));
    }
    if (texture != nullptr) g_object_unref(texture);
    if (render_context != nullptr && api != nullptr &&
        api->render_context_free != nullptr) {
      api->render_context_free(render_context);
    }
    if (handle != nullptr && api != nullptr && api->terminate_destroy != nullptr) {
      api->terminate_destroy(handle);
    }
  }

  void StartEventThread();
  void BuildAndSendEvent(const EventSnapshot& snapshot);
  void ReadSnapshotProperties(EventSnapshot* snapshot);

  LibmpvApi* api = nullptr;
  FlTextureRegistrar* texture_registrar = nullptr;
  FlEventChannel* event_channel = nullptr;
  mpv_handle* handle = nullptr;
  mpv_render_context* render_context = nullptr;
  MpvTexture* texture = nullptr;
  int64_t texture_id = 0;
  int64_t id = 0;
  std::vector<uint8_t> pixels;
  std::thread event_thread;
  std::atomic<bool> disposing{false};
  std::atomic<int> sequence{0};
};

LibmpvApi g_api;
FlTextureRegistrar* g_texture_registrar = nullptr;
FlEventChannel* g_event_channel = nullptr;
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

void RenderTexture(PlayerInstance* player) {
  if (player == nullptr || player->render_context == nullptr) return;
  int size[] = {static_cast<int>(kTextureWidth), static_cast<int>(kTextureHeight)};
  int stride = static_cast<int>(kTextureWidth * kBytesPerPixel);
  char format[] = "rgba";
  void* buffer = player->pixels.data();
  mpv_render_param params[] = {
      {MPV_RENDER_PARAM_SW_SIZE, size},
      {MPV_RENDER_PARAM_SW_FORMAT, format},
      {MPV_RENDER_PARAM_SW_STRIDE, &stride},
      {MPV_RENDER_PARAM_SW_POINTER, buffer},
      {MPV_RENDER_PARAM_INVALID, nullptr},
  };
  player->api->render_context_render(player->render_context, params);
}

gboolean MpvTextureCopyPixels(FlPixelBufferTexture* texture,
                               const uint8_t** buffer, uint32_t* width,
                               uint32_t* height, GError** error) {
  (void)error;
  MpvTexture* self = reinterpret_cast<MpvTexture*>(texture);
  PlayerInstance* player = self->player;
  if (player == nullptr) return FALSE;
  RenderTexture(player);
  *buffer = player->pixels.data();
  *width = kTextureWidth;
  *height = kTextureHeight;
  return TRUE;
}

void mpv_texture_class_init(MpvTextureClass* klass) {
  FL_PIXEL_BUFFER_TEXTURE_CLASS(klass)->copy_pixels = MpvTextureCopyPixels;
}

void mpv_texture_init(MpvTexture* self) { self->player = nullptr; }

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

std::string StringProperty(PlayerInstance* player, const char* name) {
  if (player == nullptr || player->api == nullptr ||
      player->api->get_property == nullptr) {
    return "";
  }
  char* current = nullptr;
  const int rc = player->api->get_property(
      player->handle, name, MPV_FORMAT_STRING, &current);
  if (rc < 0 || current == nullptr || player->api->free == nullptr) return "";
  std::string result(current);
  player->api->free(current);
  return result;
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
  PlayerInstance* player = static_cast<PlayerInstance*>(data);
  if (player == nullptr || player->texture_registrar == nullptr ||
      player->texture == nullptr) {
    return;
  }
  fl_texture_registrar_mark_texture_frame_available(player->texture_registrar,
                                                    FL_TEXTURE(player->texture));
}

static void SendEventOnGtkThread(gpointer user_data) {
  FlValue* event = static_cast<FlValue*>(user_data);
  if (g_event_channel != nullptr) {
    g_autoptr(GError) error = nullptr;
    fl_event_channel_send(g_event_channel, event, nullptr, &error);
    if (error != nullptr) {
      g_warning("Failed to send event: %s", error->message);
    }
  }
  fl_value_unref(event);
}

void PlayerInstance::BuildAndSendEvent(const EventSnapshot& snapshot) {
  g_autoptr(FlValue) event = fl_value_new_map();
  fl_value_set_string_take(event, "schemaVersion", fl_value_new_int(1));
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
  if (!snapshot.aid.empty()) {
    fl_value_set_string_take(event, "aid", fl_value_new_string(snapshot.aid.c_str()));
  }
  if (!snapshot.sid.empty()) {
    fl_value_set_string_take(event, "sid", fl_value_new_string(snapshot.sid.c_str()));
  }
  if (!snapshot.message.empty()) {
    fl_value_set_string_take(event, "message", fl_value_new_string(snapshot.message.c_str()));
  }
  if (!snapshot.code.empty()) {
    fl_value_set_string_take(event, "code", fl_value_new_string(snapshot.code.c_str()));
  }
  fl_value_set_string_take(event, "recoverable", fl_value_new_bool(snapshot.recoverable));

  // Pass to GTK main thread for actual send.
  fl_value_ref(event);
  g_main_context_invoke(nullptr, SendEventOnGtkThread, event);
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

  DoubleProperty(this, "time-pos", &snapshot->position);
  DoubleProperty(this, "duration", &snapshot->duration);
  FlagProperty(this, "pause", &snapshot->paused);
  bool paused_for_cache = false;
  double cache_buffering_state = 0.0;
  FlagProperty(this, "paused-for-cache", &paused_for_cache);
  DoubleProperty(this, "cache-buffering-state", &cache_buffering_state);
  snapshot->buffering = paused_for_cache || cache_buffering_state > 0.0;
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

  snapshot->aid = StringProperty(this, "aid");
  snapshot->sid = StringProperty(this, "sid");
}

void PlayerInstance::StartEventThread() {
  event_thread = std::thread([this]() {
    if (api == nullptr || api->observe_property == nullptr) return;

    // Observe relevant properties.
    api->observe_property(handle, 0, "time-pos", MPV_FORMAT_DOUBLE);
    api->observe_property(handle, 0, "duration", MPV_FORMAT_DOUBLE);
    api->observe_property(handle, 0, "pause", MPV_FORMAT_FLAG);
    api->observe_property(handle, 0, "paused-for-cache", MPV_FORMAT_FLAG);
    api->observe_property(handle, 0, "cache-buffering-state", MPV_FORMAT_DOUBLE);
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
        BuildAndSendEvent(snapshot);
        continue;
      }

      // Property change events.
      if (ev->event_id == 22) {  // MPV_EVENT_PROPERTY_CHANGE
        snapshot.sequence = sequence.fetch_add(1);
        snapshot.kind = "PLAYBACK_RESTART";
        ReadSnapshotProperties(&snapshot);
        BuildAndSendEvent(snapshot);
        continue;
      }

      // Map lifecycle events.
      switch (ev->event_id) {
        case 6:   // MPV_EVENT_START_FILE
          snapshot.sequence = sequence.fetch_add(1);
          snapshot.kind = "START_FILE";
          ReadSnapshotProperties(&snapshot);
          BuildAndSendEvent(snapshot);
          break;
        case 8:   // MPV_EVENT_FILE_LOADED
          snapshot.sequence = sequence.fetch_add(1);
          snapshot.kind = "FILE_LOADED";
          ReadSnapshotProperties(&snapshot);
          BuildAndSendEvent(snapshot);
          break;
        case 21:  // MPV_EVENT_PLAYBACK_RESTART
          snapshot.sequence = sequence.fetch_add(1);
          snapshot.kind = "PLAYBACK_RESTART";
          ReadSnapshotProperties(&snapshot);
          BuildAndSendEvent(snapshot);
          break;
        case 17:  // MPV_EVENT_VIDEO_RECONFIG
          snapshot.sequence = sequence.fetch_add(1);
          snapshot.kind = "VIDEO_RECONFIG";
          ReadSnapshotProperties(&snapshot);
          BuildAndSendEvent(snapshot);
          break;
        case 7:   // MPV_EVENT_END_FILE
          snapshot.sequence = sequence.fetch_add(1);
          snapshot.kind = "END_FILE";
          ReadSnapshotProperties(&snapshot);
          BuildAndSendEvent(snapshot);
          break;
        case 1:   // MPV_EVENT_SHUTDOWN
          snapshot.sequence = sequence.fetch_add(1);
          snapshot.kind = "SHUTDOWN";
          ReadSnapshotProperties(&snapshot);
          BuildAndSendEvent(snapshot);
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
  int advanced_control = 1;
  const DisplayInfo display = GetDisplayInfo();
  std::vector<mpv_render_param> create_params;
  create_params.push_back({MPV_RENDER_PARAM_API_TYPE, const_cast<char*>(api_type)});
  create_params.push_back({MPV_RENDER_PARAM_ADVANCED_CONTROL, &advanced_control});
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
  auto player = std::make_unique<PlayerInstance>(&api, g_texture_registrar, g_event_channel,
                                                 handle, render_context, texture, texture_id, id);
  texture->player = player.get();
  api.render_context_set_update_callback(render_context, RenderUpdate, player.get());
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
    player->BuildAndSendEvent(snapshot);
  } else if (g_strcmp0(method, "quit") == 0) {
    const char* command[] = {"quit", nullptr};
    player->api->command(player->handle, command);
    EventSnapshot snapshot;
    snapshot.handle = player->id;
    snapshot.sequence = player->sequence.fetch_add(1);
    snapshot.kind = "QUIT";
    player->ReadSnapshotProperties(&snapshot);
    player->BuildAndSendEvent(snapshot);
  } else if (g_strcmp0(method, "setAudioTrack") == 0) {
    const std::string track = StringArg(args, "trackId");
    const char* command[] = {"set", "aid", track.empty() ? "no" : track.c_str(), nullptr};
    player->api->command(player->handle, command);
  } else if (g_strcmp0(method, "setSubtitleTrack") == 0) {
    const std::string track = StringArg(args, "trackId");
    const char* command[] = {"set", "sid", track.empty() ? "no" : track.c_str(), nullptr};
    player->api->command(player->handle, command);
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

void desktop_libmpv_backend_register(FlPluginRegistry* registry) {
  FlPluginRegistrar* registrar = fl_plugin_registry_get_registrar_for_plugin(
      registry, "DesktopLibmpvBackend");
  g_texture_registrar = fl_plugin_registrar_get_texture_registrar(registrar);

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();

  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar), kChannelName,
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, MethodCallHandler, nullptr,
                                            nullptr);

  g_event_channel = fl_event_channel_new(
      fl_plugin_registrar_get_messenger(registrar), kEventChannelName,
      FL_METHOD_CODEC(codec));
  fl_event_channel_set_stream_handlers(g_event_channel, EventChannelListen,
                                       EventChannelCancel, nullptr, nullptr);
}
