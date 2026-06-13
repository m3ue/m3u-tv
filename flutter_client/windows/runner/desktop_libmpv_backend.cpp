#include "desktop_libmpv_backend.h"

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <flutter/texture_registrar.h>

#include <windows.h>

#include <cstdint>
#include <map>
#include <memory>
#include <mutex>
#include <sstream>
#include <string>
#include <utility>
#include <vector>

namespace {

using ProbeMap = flutter::EncodableMap;
using MethodCall = flutter::MethodCall<flutter::EncodableValue>;
using MethodResult = flutter::MethodResult<flutter::EncodableValue>;

constexpr char kChannelName[] = "m3u_tv/desktop_libmpv";
constexpr char kBackendUnavailableCode[] = "backend_unavailable";
constexpr wchar_t kMpvDll[] = L"mpv-2.dll";
constexpr uint32_t kTextureWidth = 1280;
constexpr uint32_t kTextureHeight = 720;
constexpr int kBytesPerPixel = 4;

using mpv_handle = struct mpv_handle;
using mpv_create_fn = mpv_handle* (*)();
using mpv_initialize_fn = int (*)(mpv_handle*);
using mpv_command_fn = int (*)(mpv_handle*, const char**);
using mpv_set_option_string_fn = int (*)(mpv_handle*, const char*, const char*);
using mpv_terminate_destroy_fn = void (*)(mpv_handle*);
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

constexpr int MPV_RENDER_PARAM_INVALID = 0;
constexpr int MPV_RENDER_PARAM_API_TYPE = 1;
constexpr int MPV_RENDER_PARAM_ADVANCED_CONTROL = 10;
constexpr int MPV_RENDER_PARAM_SW_SIZE = 17;
constexpr int MPV_RENDER_PARAM_SW_FORMAT = 18;
constexpr int MPV_RENDER_PARAM_SW_STRIDE = 19;
constexpr int MPV_RENDER_PARAM_SW_POINTER = 20;

std::string Narrow(const std::wstring& value) {
  if (value.empty()) return "";
  const int size = WideCharToMultiByte(CP_UTF8, 0, value.c_str(), -1, nullptr, 0, nullptr, nullptr);
  if (size <= 0) return "";
  std::string result(static_cast<size_t>(size - 1), '\0');
  WideCharToMultiByte(CP_UTF8, 0, value.c_str(), -1, result.data(), size, nullptr, nullptr);
  return result;
}

std::wstring RunnerDirectory() {
  wchar_t path[MAX_PATH];
  const DWORD length = GetModuleFileNameW(nullptr, path, MAX_PATH);
  if (length == 0 || length == MAX_PATH) return L"";
  std::wstring value(path, length);
  const size_t slash = value.find_last_of(L"\\/");
  if (slash == std::wstring::npos) return L"";
  return value.substr(0, slash);
}

std::string LastErrorMessage(DWORD error_code) {
  if (error_code == 0) return "no Windows error detail";
  LPWSTR message = nullptr;
  const DWORD length = FormatMessageW(
      FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
      nullptr, error_code, MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
      reinterpret_cast<LPWSTR>(&message), 0, nullptr);
  if (length == 0 || message == nullptr) return "GetLastError=" + std::to_string(error_code);
  std::wstring wide(message, length);
  LocalFree(message);
  while (!wide.empty() && (wide.back() == L'\r' || wide.back() == L'\n' || wide.back() == L'.' || wide.back() == L' ')) {
    wide.pop_back();
  }
  return Narrow(wide) + " (GetLastError=" + std::to_string(error_code) + ")";
}

struct LibmpvApi {
  HMODULE library = nullptr;
  mpv_create_fn create = nullptr;
  mpv_initialize_fn initialize = nullptr;
  mpv_command_fn command = nullptr;
  mpv_set_option_string_fn set_option_string = nullptr;
  mpv_terminate_destroy_fn terminate_destroy = nullptr;
  mpv_render_context_create_fn render_context_create = nullptr;
  mpv_render_context_set_update_callback_fn render_context_set_update_callback = nullptr;
  mpv_render_context_render_fn render_context_render = nullptr;
  mpv_render_context_free_fn render_context_free = nullptr;
  std::string library_name;
  std::string error;

  bool client_available() const {
    return library != nullptr && create != nullptr && initialize != nullptr &&
           command != nullptr && set_option_string != nullptr &&
           terminate_destroy != nullptr;
  }

  bool render_api_available() const {
    return render_context_create != nullptr &&
           render_context_set_update_callback != nullptr &&
           render_context_render != nullptr && render_context_free != nullptr;
  }

  bool available() const { return client_available() && render_api_available(); }
};

struct PlayerInstance {
  PlayerInstance(LibmpvApi* api, flutter::TextureRegistrar* texture_registrar,
                 mpv_handle* handle, mpv_render_context* render_context)
      : api(api),
        texture_registrar(texture_registrar),
        handle(handle),
        render_context(render_context),
        pixels(kTextureWidth * kTextureHeight * kBytesPerPixel, 0) {
    pixel_buffer.buffer = pixels.data();
    pixel_buffer.width = kTextureWidth;
    pixel_buffer.height = kTextureHeight;
  }

  ~PlayerInstance() {
    if (texture_registrar != nullptr && texture_id != 0) {
      texture_registrar->UnregisterTexture(texture_id);
    }
    if (render_context != nullptr && api != nullptr && api->render_context_free != nullptr) {
      api->render_context_free(render_context);
    }
    if (handle != nullptr && api != nullptr && api->terminate_destroy != nullptr) {
      api->terminate_destroy(handle);
    }
  }

  const FlutterDesktopPixelBuffer* CopyPixels(size_t width, size_t height) {
    (void)width;
    (void)height;
    std::lock_guard<std::mutex> lock(mutex);
    if (render_context == nullptr || api == nullptr || api->render_context_render == nullptr) {
      return &pixel_buffer;
    }
    int size[] = {static_cast<int>(kTextureWidth), static_cast<int>(kTextureHeight)};
    int stride = static_cast<int>(kTextureWidth * kBytesPerPixel);
    char format[] = "rgba";
    void* buffer = pixels.data();
    mpv_render_param params[] = {
        {MPV_RENDER_PARAM_SW_SIZE, size},
        {MPV_RENDER_PARAM_SW_FORMAT, format},
        {MPV_RENDER_PARAM_SW_STRIDE, &stride},
        {MPV_RENDER_PARAM_SW_POINTER, buffer},
        {MPV_RENDER_PARAM_INVALID, nullptr},
    };
    api->render_context_render(render_context, params);
    return &pixel_buffer;
  }

  LibmpvApi* api = nullptr;
  flutter::TextureRegistrar* texture_registrar = nullptr;
  mpv_handle* handle = nullptr;
  mpv_render_context* render_context = nullptr;
  int64_t texture_id = 0;
  std::vector<uint8_t> pixels;
  FlutterDesktopPixelBuffer pixel_buffer = {};
  std::unique_ptr<flutter::TextureVariant> texture;
  std::mutex mutex;
};

LibmpvApi g_api;
flutter::TextureRegistrar* g_texture_registrar = nullptr;
int64_t g_next_handle = 1;
std::map<int64_t, std::unique_ptr<PlayerInstance>> g_players;

FARPROC LoadSymbol(HMODULE library, const char* name) { return GetProcAddress(library, name); }

LibmpvApi& Api() {
  if (g_api.library != nullptr || !g_api.error.empty()) return g_api;

  const std::wstring runner_dir = RunnerDirectory();
  std::wstring bundled_path;
  if (!runner_dir.empty()) bundled_path = runner_dir + L"\\" + kMpvDll;

  std::ostringstream attempted;
  DWORD last_error = 0;
  if (!bundled_path.empty()) {
    attempted << Narrow(bundled_path) << " ";
    g_api.library = LoadLibraryExW(
        bundled_path.c_str(), nullptr,
        LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_DEFAULT_DIRS);
    if (g_api.library == nullptr) last_error = GetLastError();
  }

  if (g_api.library == nullptr) {
    attempted << "Windows DLL search path " << Narrow(kMpvDll);
    g_api.library = LoadLibraryExW(kMpvDll, nullptr, LOAD_LIBRARY_SEARCH_DEFAULT_DIRS);
    if (g_api.library == nullptr) last_error = GetLastError();
  }

  if (g_api.library == nullptr) {
    g_api.error = "mpv-2.dll not found; tried runner directory and Windows DLL search path; " +
                  LastErrorMessage(last_error);
    return g_api;
  }

  g_api.library_name = !bundled_path.empty() ? Narrow(bundled_path) : Narrow(kMpvDll);
  g_api.create = reinterpret_cast<mpv_create_fn>(LoadSymbol(g_api.library, "mpv_create"));
  g_api.initialize = reinterpret_cast<mpv_initialize_fn>(LoadSymbol(g_api.library, "mpv_initialize"));
  g_api.command = reinterpret_cast<mpv_command_fn>(LoadSymbol(g_api.library, "mpv_command"));
  g_api.set_option_string = reinterpret_cast<mpv_set_option_string_fn>(LoadSymbol(g_api.library, "mpv_set_option_string"));
  g_api.terminate_destroy = reinterpret_cast<mpv_terminate_destroy_fn>(LoadSymbol(g_api.library, "mpv_terminate_destroy"));
  g_api.render_context_create = reinterpret_cast<mpv_render_context_create_fn>(LoadSymbol(g_api.library, "mpv_render_context_create"));
  g_api.render_context_set_update_callback = reinterpret_cast<mpv_render_context_set_update_callback_fn>(LoadSymbol(g_api.library, "mpv_render_context_set_update_callback"));
  g_api.render_context_render = reinterpret_cast<mpv_render_context_render_fn>(LoadSymbol(g_api.library, "mpv_render_context_render"));
  g_api.render_context_free = reinterpret_cast<mpv_render_context_free_fn>(LoadSymbol(g_api.library, "mpv_render_context_free"));

  if (!g_api.client_available()) {
    g_api.error = "mpv-2.dll loaded but required libmpv client symbols are missing";
  } else if (!g_api.render_api_available()) {
    g_api.error = "mpv-2.dll loaded but libmpv render API symbols are missing";
  }
  return g_api;
}

std::string DisplayDetails(HWND hwnd) {
  std::ostringstream details;
  details << "windowSystem=win32-hwnd; hwnd=" << (hwnd == nullptr ? "unavailable" : "available")
          << "; texture=Flutter pixel buffer; render=libmpv software API";
  return details.str();
}

ProbeMap Probe(HWND hwnd) {
  LibmpvApi& api = Api();
  const bool can_play = api.available() && g_texture_registrar != nullptr && hwnd != nullptr;
  std::string details = can_play ? "mpv-2.dll client/render symbols resolved from " + api.library_name
                                 : api.error;
  if (g_texture_registrar == nullptr) {
    if (!details.empty()) details += "; ";
    details += "Flutter texture registrar unavailable";
  }
  if (!details.empty()) details += "; ";
  details += DisplayDetails(hwnd);

  return ProbeMap{
      {flutter::EncodableValue("platform"), flutter::EncodableValue("windows")},
      {flutter::EncodableValue("windowSystem"), flutter::EncodableValue("win32-hwnd")},
      {flutter::EncodableValue("videoApi"), flutter::EncodableValue("Flutter pixel buffer texture using libmpv software render API")},
      {flutter::EncodableValue("ownedSurface"), flutter::EncodableValue(hwnd != nullptr)},
      {flutter::EncodableValue("libmpvAvailable"), flutter::EncodableValue(api.client_available())},
      {flutter::EncodableValue("renderApiAvailable"), flutter::EncodableValue(api.render_api_available())},
      {flutter::EncodableValue("canPlayFixture"), flutter::EncodableValue(can_play)},
      {flutter::EncodableValue("fallbackDecision"), flutter::EncodableValue(can_play ? "none" : "server-transcode until mpv-2.dll is bundled")},
      {flutter::EncodableValue("details"), flutter::EncodableValue(details)},
  };
}

std::string StringArg(const flutter::EncodableMap* args, const char* key) {
  if (args == nullptr) return "";
  auto it = args->find(flutter::EncodableValue(key));
  if (it == args->end()) return "";
  const std::string* value = std::get_if<std::string>(&it->second);
  return value == nullptr ? "" : *value;
}

int64_t IntArg(const flutter::EncodableMap* args, const char* key) {
  if (args == nullptr) return 0;
  auto it = args->find(flutter::EncodableValue(key));
  if (it == args->end()) return 0;
  if (const int32_t* value = std::get_if<int32_t>(&it->second)) return *value;
  if (const int64_t* value = std::get_if<int64_t>(&it->second)) return *value;
  return 0;
}

double DoubleArg(const flutter::EncodableMap* args, const char* key, double fallback) {
  if (args == nullptr) return fallback;
  auto it = args->find(flutter::EncodableValue(key));
  if (it == args->end()) return fallback;
  if (const double* value = std::get_if<double>(&it->second)) return *value;
  if (const int32_t* value = std::get_if<int32_t>(&it->second)) return static_cast<double>(*value);
  if (const int64_t* value = std::get_if<int64_t>(&it->second)) return static_cast<double>(*value);
  return fallback;
}

std::string HeaderString(const flutter::EncodableMap* args) {
  if (args == nullptr) return "";
  auto it = args->find(flutter::EncodableValue("headers"));
  if (it == args->end()) return "";
  const flutter::EncodableMap* headers = std::get_if<flutter::EncodableMap>(&it->second);
  if (headers == nullptr) return "";
  std::ostringstream value;
  for (const auto& pair : *headers) {
    const std::string* key = std::get_if<std::string>(&pair.first);
    const std::string* item = std::get_if<std::string>(&pair.second);
    if (key == nullptr || item == nullptr) continue;
    if (value.tellp() > 0) value << ",";
    value << *key << ": " << *item;
  }
  return value.str();
}

ProbeMap LoadFailure(const char* code, const std::string& error) {
  return ProbeMap{
      {flutter::EncodableValue("ok"), flutter::EncodableValue(false)},
      {flutter::EncodableValue("code"), flutter::EncodableValue(code)},
      {flutter::EncodableValue("error"), flutter::EncodableValue(error)},
  };
}

void RenderUpdate(void* data) {
  PlayerInstance* player = static_cast<PlayerInstance*>(data);
  if (player == nullptr || player->texture_registrar == nullptr || player->texture_id == 0) return;
  player->texture_registrar->MarkTextureFrameAvailable(player->texture_id);
}

ProbeMap Load(const flutter::EncodableMap* args, HWND hwnd) {
  LibmpvApi& api = Api();
  if (!api.available()) return LoadFailure(kBackendUnavailableCode, api.error);
  if (g_texture_registrar == nullptr) {
    return LoadFailure(kBackendUnavailableCode, "Flutter texture registrar unavailable");
  }
  if (hwnd == nullptr) return LoadFailure(kBackendUnavailableCode, "Win32 HWND unavailable");

  mpv_handle* handle = api.create();
  if (handle == nullptr) return LoadFailure("desktop-libmpv-load-failed", "mpv_create returned null");

  api.set_option_string(handle, "terminal", "no");
  api.set_option_string(handle, "config", "no");
  api.set_option_string(handle, "vo", "libmpv");
  api.set_option_string(handle, "hwdec", "auto-safe");
  api.set_option_string(handle, "idle", "yes");
  const std::string user_agent = StringArg(args, "userAgent");
  if (!user_agent.empty()) api.set_option_string(handle, "user-agent", user_agent.c_str());
  const std::string headers = HeaderString(args);
  if (!headers.empty()) api.set_option_string(handle, "http-header-fields", headers.c_str());

  int rc = api.initialize(handle);
  if (rc < 0) {
    api.terminate_destroy(handle);
    return LoadFailure("desktop-libmpv-load-failed", "mpv_initialize failed");
  }

  char api_type[] = "sw";
  int advanced_control = 1;
  mpv_render_param create_params[] = {
      {MPV_RENDER_PARAM_API_TYPE, api_type},
      {MPV_RENDER_PARAM_ADVANCED_CONTROL, &advanced_control},
      {MPV_RENDER_PARAM_INVALID, nullptr},
  };
  mpv_render_context* render_context = nullptr;
  rc = api.render_context_create(&render_context, handle, create_params);
  if (rc < 0 || render_context == nullptr) {
    api.terminate_destroy(handle);
    return LoadFailure("desktop-libmpv-load-failed", "mpv_render_context_create failed");
  }

  auto player = std::make_unique<PlayerInstance>(&api, g_texture_registrar, handle, render_context);
  auto texture = std::make_unique<flutter::TextureVariant>(flutter::PixelBufferTexture(
      [raw_player = player.get()](size_t width, size_t height) {
        return raw_player->CopyPixels(width, height);
      }));
  const int64_t texture_id = g_texture_registrar->RegisterTexture(texture.get());
  if (texture_id < 0) {
    return LoadFailure("desktop-libmpv-load-failed", "Flutter texture registration failed");
  }
  player->texture = std::move(texture);
  player->texture_id = texture_id;
  api.render_context_set_update_callback(render_context, RenderUpdate, player.get());

  const std::string uri = StringArg(args, "uri");
  const char* load_args[] = {"loadfile", uri.c_str(), "replace", nullptr};
  rc = api.command(handle, load_args);
  if (rc < 0) return LoadFailure("desktop-libmpv-load-failed", "mpv loadfile command failed");

  const int64_t id = g_next_handle++;
  g_players[id] = std::move(player);
  return ProbeMap{
      {flutter::EncodableValue("ok"), flutter::EncodableValue(true)},
      {flutter::EncodableValue("handle"), flutter::EncodableValue(id)},
      {flutter::EncodableValue("textureId"), flutter::EncodableValue(texture_id)},
      {flutter::EncodableValue("display"), flutter::EncodableValue(DisplayDetails(hwnd))},
  };
}

void Control(const std::string& method, const flutter::EncodableMap* args) {
  const int64_t id = IntArg(args, "handle");
  auto it = g_players.find(id);
  if (it == g_players.end()) return;
  PlayerInstance* player = it->second.get();
  if (method == "play") {
    const char* command[] = {"set", "pause", "no", nullptr};
    player->api->command(player->handle, command);
  } else if (method == "pause") {
    const char* command[] = {"set", "pause", "yes", nullptr};
    player->api->command(player->handle, command);
  } else if (method == "seek") {
    const double seconds = static_cast<double>(IntArg(args, "positionMs")) / 1000.0;
    const std::string value = std::to_string(seconds);
    const char* command[] = {"seek", value.c_str(), "absolute", nullptr};
    player->api->command(player->handle, command);
  } else if (method == "stop") {
    const char* command[] = {"stop", nullptr};
    player->api->command(player->handle, command);
  } else if (method == "setAudioTrack") {
    const std::string track = StringArg(args, "trackId");
    const char* command[] = {"set", "aid", track.empty() ? "no" : track.c_str(), nullptr};
    player->api->command(player->handle, command);
  } else if (method == "setSubtitleTrack") {
    const std::string track = StringArg(args, "trackId");
    const char* command[] = {"set", "sid", track.empty() ? "no" : track.c_str(), nullptr};
    player->api->command(player->handle, command);
  } else if (method == "setPlaybackSpeed") {
    const std::string speed = std::to_string(DoubleArg(args, "speed", 1.0));
    const char* command[] = {"set", "speed", speed.c_str(), nullptr};
    player->api->command(player->handle, command);
  } else if (method == "dispose") {
    g_players.erase(it);
  }
}

class DesktopLibmpvBackendPlugin : public flutter::Plugin {
 public:
  DesktopLibmpvBackendPlugin(flutter::PluginRegistrarWindows* registrar, HWND hwnd)
      : texture_registrar_(registrar->texture_registrar()), hwnd_(hwnd) {
    g_texture_registrar = texture_registrar_;
    channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
        registrar->messenger(), kChannelName, &flutter::StandardMethodCodec::GetInstance());
    channel_->SetMethodCallHandler([this](const MethodCall& call, std::unique_ptr<MethodResult> result) {
      HandleCall(call, std::move(result));
    });
  }

  ~DesktopLibmpvBackendPlugin() override {
    g_players.clear();
    if (g_texture_registrar == texture_registrar_) g_texture_registrar = nullptr;
  }

 private:
  void HandleCall(const MethodCall& call, std::unique_ptr<MethodResult> result) {
    const std::string& method = call.method_name();
    const flutter::EncodableMap* args = nullptr;
    if (call.arguments() != nullptr) {
      args = std::get_if<flutter::EncodableMap>(call.arguments());
    }
    if (method == "probe") {
      result->Success(flutter::EncodableValue(Probe(hwnd_)));
      return;
    }
    if (method == "load") {
      result->Success(flutter::EncodableValue(Load(args, hwnd_)));
      return;
    }
    Control(method, args);
    result->Success();
  }

  flutter::TextureRegistrar* texture_registrar_ = nullptr;
  HWND hwnd_ = nullptr;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

}

void RegisterDesktopLibmpvBackend(flutter::PluginRegistrarWindows* registrar, HWND hwnd) {
  registrar->AddPlugin(std::make_unique<DesktopLibmpvBackendPlugin>(registrar, hwnd));
}
