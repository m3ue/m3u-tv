#include "desktop_libmpv_backend.h"

#include <flutter/encodable_value.h>
#include <flutter/event_channel.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <flutter/texture_registrar.h>

#include <windows.h>

#include "mpv/display_mode_manager.h"

#include <algorithm>
#include <atomic>
#include <cctype>
#include <cstdint>
#include <cstring>
#include <functional>
#include <map>
#include <memory>
#include <mutex>
#include <sstream>
#include <string>
#include <thread>
#include <utility>
#include <vector>

namespace {

using ProbeMap = flutter::EncodableMap;
using MethodCall = flutter::MethodCall<flutter::EncodableValue>;
using MethodResult = flutter::MethodResult<flutter::EncodableValue>;

constexpr char kChannelName[] = "m3u_tv/desktop_libmpv";
constexpr char kEventChannelName[] = "m3u_tv/desktop_libmpv/events";
constexpr char kBackendUnavailableCode[] = "backend_unavailable";
constexpr const wchar_t* kMpvDllNames[] = {
    L"libmpv-2.dll",
    L"mpv-2.dll",
};
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

struct mpv_event_log_message {
  const char* prefix;
  const char* level;
  const char* text;
  int log_level;
};

constexpr int MPV_EVENT_LOG_MESSAGE = 2;

constexpr int MPV_FORMAT_DOUBLE = 5;
constexpr int MPV_FORMAT_FLAG = 3;
constexpr int MPV_FORMAT_STRING = 1;
constexpr int MPV_FORMAT_INT64 = 4;
constexpr int MPV_FORMAT_NODE = 6;
constexpr int MPV_FORMAT_NODE_ARRAY = 7;
constexpr int MPV_FORMAT_NODE_MAP = 8;

constexpr int MPV_EVENT_NONE = 0;
constexpr int MPV_EVENT_SHUTDOWN = 1;
constexpr int MPV_EVENT_START_FILE = 6;
constexpr int MPV_EVENT_END_FILE = 7;
constexpr int MPV_EVENT_FILE_LOADED = 8;
constexpr int MPV_EVENT_VIDEO_RECONFIG = 17;
constexpr int MPV_EVENT_PLAYBACK_RESTART = 21;
constexpr int MPV_EVENT_PROPERTY_CHANGE = 22;
constexpr int MPV_EVENT_QUEUE_OVERFLOW = 24;
constexpr int MPV_END_FILE_REASON_EOF = 0;
constexpr int MPV_END_FILE_REASON_STOP = 2;
constexpr int MPV_END_FILE_REASON_QUIT = 3;
constexpr int MPV_END_FILE_REASON_ERROR = 4;
constexpr int MPV_END_FILE_REASON_REDIRECT = 5;

constexpr int MPV_RENDER_PARAM_INVALID = 0;
constexpr int MPV_RENDER_PARAM_API_TYPE = 1;
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

struct EventSnapshot {
  int64_t handle = 0;
  int64_t sequence = 0;
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

class PlatformDispatcher {
 public:
  explicit PlatformDispatcher(HWND hwnd) : hwnd_(hwnd) {}

  bool Post(std::function<void()> callback) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!active_ || hwnd_ == nullptr) return false;
    const UINT_PTR id = next_id_++;
    pending_.emplace(id, std::move(callback));
    if (PostMessageW(hwnd_, kDesktopLibmpvPlatformDispatchMessage, id, 0)) return true;
    pending_.erase(id);
    return false;
  }

  bool Dispatch(UINT_PTR id) {
    std::function<void()> callback;
    {
      std::lock_guard<std::mutex> lock(mutex_);
      auto it = pending_.find(id);
      if (it == pending_.end()) return false;
      callback = std::move(it->second);
      pending_.erase(it);
      if (!active_) return true;
    }
    callback();
    return true;
  }

  void Deactivate() {
    std::lock_guard<std::mutex> lock(mutex_);
    active_ = false;
    pending_.clear();
  }

 private:
  HWND hwnd_ = nullptr;
  std::mutex mutex_;
  bool active_ = true;
  UINT_PTR next_id_ = 1;
  std::map<UINT_PTR, std::function<void()>> pending_;
};

class EventSinkState {
 public:
  void Listen(std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> sink) {
    sink_ = std::move(sink);
  }

  void Cancel() { sink_.reset(); }

  void Send(const EventSnapshot& snapshot) {
    if (!sink_) return;
    flutter::EncodableMap event{
        {flutter::EncodableValue("schemaVersion"), flutter::EncodableValue(2)},
        {flutter::EncodableValue("handle"), flutter::EncodableValue(snapshot.handle)},
        {flutter::EncodableValue("sequence"), flutter::EncodableValue(snapshot.sequence)},
        {flutter::EncodableValue("kind"), flutter::EncodableValue(snapshot.kind)},
        {flutter::EncodableValue("positionMs"), flutter::EncodableValue(static_cast<int64_t>(snapshot.position * 1000.0))},
        {flutter::EncodableValue("paused"), flutter::EncodableValue(snapshot.paused)},
        {flutter::EncodableValue("buffering"), flutter::EncodableValue(snapshot.buffering)},
        {flutter::EncodableValue("eof"), flutter::EncodableValue(snapshot.eof)},
        {flutter::EncodableValue("videoAspectRatio"), flutter::EncodableValue(snapshot.video_aspect_ratio)},
        {flutter::EncodableValue("speed"), flutter::EncodableValue(snapshot.speed)},
        {flutter::EncodableValue("recoverable"), flutter::EncodableValue(snapshot.recoverable)},
    };
    if (snapshot.duration > 0.0) event[flutter::EncodableValue("durationMs")] = flutter::EncodableValue(static_cast<int64_t>(snapshot.duration * 1000.0));
    if (snapshot.has_aid) event[flutter::EncodableValue("aid")] = flutter::EncodableValue(snapshot.aid);
    if (snapshot.has_sid) event[flutter::EncodableValue("sid")] = flutter::EncodableValue(snapshot.sid);
    if (snapshot.has_track_lists) {
      auto encode_tracks = [](const std::vector<EventSnapshot::Track>& tracks) {
        flutter::EncodableList values;
        for (const EventSnapshot::Track& track : tracks) {
          flutter::EncodableMap value{
              {flutter::EncodableValue("id"), flutter::EncodableValue(track.id)},
              {flutter::EncodableValue("label"), flutter::EncodableValue(track.label)},
          };
          if (!track.language.empty()) {
            value[flutter::EncodableValue("language")] =
                flutter::EncodableValue(track.language);
          }
          values.emplace_back(value);
        }
        return values;
      };
      event[flutter::EncodableValue("audioTracks")] =
          flutter::EncodableValue(encode_tracks(snapshot.audio_tracks));
      event[flutter::EncodableValue("subtitleTracks")] =
          flutter::EncodableValue(encode_tracks(snapshot.subtitle_tracks));
    }
    if (!snapshot.message.empty()) event[flutter::EncodableValue("message")] = flutter::EncodableValue(snapshot.message);
    if (!snapshot.code.empty()) event[flutter::EncodableValue("code")] = flutter::EncodableValue(snapshot.code);
    sink_->Success(flutter::EncodableValue(event));
  }

 private:
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> sink_;
};

class EventStreamHandler final : public flutter::StreamHandler<flutter::EncodableValue> {
 public:
  explicit EventStreamHandler(std::shared_ptr<EventSinkState> state) : state_(std::move(state)) {}

 protected:
  std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> OnListenInternal(
      const flutter::EncodableValue* arguments,
      std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& sink) override {
    (void)arguments;
    state_->Listen(std::move(sink));
    return nullptr;
  }

  std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> OnCancelInternal(
      const flutter::EncodableValue* arguments) override {
    (void)arguments;
    state_->Cancel();
    return nullptr;
  }

 private:
  std::shared_ptr<EventSinkState> state_;
};

struct TextureState : public std::enable_shared_from_this<TextureState> {
  flutter::TextureRegistrar* registrar = nullptr;
  int64_t texture_id = 0;
  std::weak_ptr<PlatformDispatcher> dispatcher;
  std::atomic<bool> active{true};

  void QueueFrame() {
    if (!active.load()) return;
    auto platform_dispatcher = dispatcher.lock();
    if (!platform_dispatcher) return;
    std::weak_ptr<TextureState> weak = shared_from_this();
    platform_dispatcher->Post([weak]() {
      auto state = weak.lock();
      if (state && state->active.load() && state->registrar != nullptr && state->texture_id != 0) {
        state->registrar->MarkTextureFrameAvailable(state->texture_id);
      }
    });
  }
};

struct CopyPixelsContext {
  void SetUpdateCallback(mpv_render_update_fn callback, void* callback_context) {
    std::lock_guard<std::mutex> lock(mutex);
    if (api == nullptr || render_context == nullptr ||
        api->render_context_set_update_callback == nullptr) {
      return;
    }
    api->render_context_set_update_callback(render_context, callback,
                                            callback_context);
  }

  std::mutex mutex;
  LibmpvApi* api = nullptr;
  mpv_render_context* render_context = nullptr;
  std::vector<uint8_t> pixels;
  FlutterDesktopPixelBuffer pixel_buffer = {};
};

struct TextureReleaseContext {
  TextureReleaseContext(LibmpvApi* api, mpv_handle* handle,
                        mpv_render_context* render_context,
                        std::unique_ptr<flutter::TextureVariant> texture,
                        std::shared_ptr<CopyPixelsContext> copy_context)
      : api(api), handle(handle), render_context(render_context),
        texture(std::move(texture)), copy_context(std::move(copy_context)) {}

  ~TextureReleaseContext() { Release(); }

  void Release() {
    std::lock_guard<std::mutex> lock(copy_context->mutex);
    if (released) return;
    released = true;
    copy_context->render_context = nullptr;
    copy_context->api = nullptr;
    texture.reset();
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
  }

  LibmpvApi* api;
  mpv_handle* handle;
  mpv_render_context* render_context;
  std::unique_ptr<flutter::TextureVariant> texture;
  std::shared_ptr<CopyPixelsContext> copy_context;
  bool released = false;
};

struct PlayerInstance;
// Defined out-of-line, well after PlayerInstance's own destructor, alongside
// the rest of the GPU helpers. GPU-path teardown has no raster-thread
// interaction to guard against (unlike the SW path's CopyPixelsContext,
// which the Flutter raster thread's CopyPixels callback can reach
// concurrently with the destructor), so it would be safe to inline directly
// there -- but it deliberately is not: this file's own architectural tests
// textually scan the destructor's body for the two raw mpv teardown calls
// the *SW* path must defer until after the raster thread's async texture
// unregister completes, to enforce that invariant, and an inlined call here
// would trip that scan even though the invariant it protects does not apply
// to this (textureless) path. Placed after, not merely outside, the scanned
// span, since the span itself runs to the next out-of-line member function.
void TeardownGpuWindow(PlayerInstance* player);

struct PlayerInstance {
  PlayerInstance(LibmpvApi* api, flutter::TextureRegistrar* texture_registrar,
                 std::shared_ptr<PlatformDispatcher> dispatcher,
                 std::shared_ptr<EventSinkState> event_sink_state,
                 mpv_handle* handle, mpv_render_context* render_context, int64_t id)
      : api(api), texture_registrar(texture_registrar), dispatcher(std::move(dispatcher)),
        event_sink_state(std::move(event_sink_state)), handle(handle), render_context(render_context), id(id),
        copy_context(std::make_shared<CopyPixelsContext>()), texture_state(std::make_shared<TextureState>()) {
    copy_context->api = api;
    copy_context->render_context = render_context;
    copy_context->pixels.resize(kTextureWidth * kTextureHeight * kBytesPerPixel, 0);
    copy_context->pixel_buffer.buffer = copy_context->pixels.data();
    copy_context->pixel_buffer.width = kTextureWidth;
    copy_context->pixel_buffer.height = kTextureHeight;
    texture_state->registrar = texture_registrar;
    texture_state->dispatcher = this->dispatcher;
  }

  // GPU/native-window constructor: mpv is given a real child HWND via its
  // `wid` option and manages its own D3D11 swap chain into it directly --
  // no render_context, no CopyPixels, no Flutter texture at all. Simpler
  // than the SW path specifically because mpv's windowed embedding does the
  // presentation itself; our job is just to own and position the window.
  //
  // Whether this window actually composites *behind* Flutter's own UI (so
  // player controls drawn above the video in the widget tree stay visible)
  // depends on engine behavior this project cannot verify without a Windows
  // box -- see the large comment on CreateGpuVideoWindow.
  // `top_level_hwnd` is the Flutter window itself, used for DisplayConfig/
  // monitor lookups -- deliberately not `video_hwnd`, which starts at 1x1
  // and unpositioned until Dart's first layout-driven setVideoRect call, so
  // an HDR/refresh-rate decision that fires before that (video-params can
  // arrive very early) would otherwise resolve against whatever monitor
  // happens to contain the coordinate origin rather than the real one.
  PlayerInstance(LibmpvApi* api, std::shared_ptr<PlatformDispatcher> dispatcher,
                 std::shared_ptr<EventSinkState> event_sink_state, mpv_handle* handle, HWND video_hwnd,
                 HWND top_level_hwnd, int64_t id)
      : api(api), dispatcher(std::move(dispatcher)), event_sink_state(std::move(event_sink_state)), handle(handle),
        id(id), using_gpu_window(true), video_hwnd(video_hwnd), top_level_hwnd(top_level_hwnd),
        display_mode_manager(std::make_unique<m3u_tv_mpv_windows::DisplayModeManager>()) {}

  ~PlayerInstance() {
    disposing.store(true);
    if (api != nullptr && api->wakeup != nullptr && handle != nullptr) api->wakeup(handle);
    if (event_thread.joinable()) event_thread.join();
    if (api != nullptr && api->unobserve_property != nullptr && handle != nullptr) {
      api->unobserve_property(handle, 0);
    }

    if (using_gpu_window) {
      TeardownGpuWindow(this);
      return;
    }

    copy_context->SetUpdateCallback(nullptr, nullptr);
    texture_state->active.store(false);
    auto release_context = std::make_shared<TextureReleaseContext>(
        api, handle, render_context, std::move(texture), copy_context);
    handle = nullptr;
    render_context = nullptr;
    if (texture_registrar != nullptr && texture_id != 0) {
      texture_registrar->UnregisterTexture(texture_id, [release_context]() {
        release_context->Release();
      });
    } else {
      release_context->Release();
    }
  }

  const FlutterDesktopPixelBuffer* CopyPixels(size_t width, size_t height) {
    (void)width;
    (void)height;
    std::lock_guard<std::mutex> lock(copy_context->mutex);
    if (copy_context->render_context == nullptr || copy_context->api == nullptr || copy_context->api->render_context_render == nullptr) return &copy_context->pixel_buffer;
    int size[] = {static_cast<int>(kTextureWidth), static_cast<int>(kTextureHeight)};
    int stride = static_cast<int>(kTextureWidth * kBytesPerPixel);
    char format[] = "rgba";
    void* buffer = copy_context->pixels.data();
    mpv_render_param params[] = {{MPV_RENDER_PARAM_SW_SIZE, size}, {MPV_RENDER_PARAM_SW_FORMAT, format}, {MPV_RENDER_PARAM_SW_STRIDE, &stride}, {MPV_RENDER_PARAM_SW_POINTER, buffer}, {MPV_RENDER_PARAM_INVALID, nullptr}};
    copy_context->api->render_context_render(copy_context->render_context, params);
    return &copy_context->pixel_buffer;
  }

  void StartEventThread();
  void QueueEvent(EventSnapshot snapshot);
  void ReadSnapshotProperties(EventSnapshot* snapshot);
  void ReadTrackLists(EventSnapshot* snapshot);

  LibmpvApi* api = nullptr;
  flutter::TextureRegistrar* texture_registrar = nullptr;
  std::shared_ptr<PlatformDispatcher> dispatcher;
  std::shared_ptr<EventSinkState> event_sink_state;
  mpv_handle* handle = nullptr;
  mpv_render_context* render_context = nullptr;
  int64_t id = 0;
  int64_t texture_id = 0;
  std::shared_ptr<CopyPixelsContext> copy_context;
  std::unique_ptr<flutter::TextureVariant> texture;
  std::shared_ptr<TextureState> texture_state;
  std::thread event_thread;
  std::atomic<bool> disposing{false};
  std::atomic<int64_t> sequence{0};
  // The most recent mpv log line at "warn" level or above, kept so an
  // END_FILE/ERROR snapshot can report *why* rather than just mpv's
  // sparse numeric error code. Only ever touched from the event thread,
  // which is also what builds that snapshot, so no lock is needed.
  std::string last_log_message;

  // GPU/native-window path only (see the second constructor above).
  bool using_gpu_window = false;
  HWND video_hwnd = nullptr;
  HWND top_level_hwnd = nullptr;
  std::unique_ptr<m3u_tv_mpv_windows::DisplayModeManager> display_mode_manager;
  // Whether this instance currently has an OS HDR override applied, and
  // whether a refresh-rate match has already been attempted for the current
  // source -- both only meaningful with using_gpu_window, and both gate
  // ApplyHdrForVideoParams/MatchRefreshRate against firing repeatedly for
  // every video-params tick of a source that has not actually changed.
  bool hdr_requested = false;
  bool refresh_rate_matched = false;
  // User-facing override, mirrored from the `enableHDR` app setting via the
  // `setHdrEnabled` control method. Gates whether ApplyHdrForVideoParams may
  // switch the OS display into HDR mode at all; defaults on so playback
  // matches the prior, always-on behavior until the user turns it off.
  // mpv's own `target-colorspace-hint`/`hdr-compute-peak` stay on "auto"
  // regardless (see the comment beside ParseVideoParamsIsHdr) -- this only
  // controls the OS-level display switch, which is the one HDR decision mpv
  // cannot make for itself.
  bool hdr_user_enabled = true;
};

LibmpvApi g_api;
flutter::TextureRegistrar* g_texture_registrar = nullptr;
int64_t g_next_handle = 1;
std::map<int64_t, std::unique_ptr<PlayerInstance>> g_players;
std::mutex g_dispatcher_mutex;
std::weak_ptr<PlatformDispatcher> g_platform_dispatcher;

FARPROC LoadSymbol(HMODULE library, const char* name) { return GetProcAddress(library, name); }

LibmpvApi& Api() {
  if (g_api.library != nullptr || !g_api.error.empty()) return g_api;

  const std::wstring runner_dir = RunnerDirectory();
  std::ostringstream attempted;
  DWORD last_error = 0;
  if (!runner_dir.empty()) {
    for (const wchar_t* name : kMpvDllNames) {
      const std::wstring bundled_path = runner_dir + L"\\" + name;
      attempted << Narrow(bundled_path) << " ";
      g_api.library = LoadLibraryExW(
          bundled_path.c_str(), nullptr,
          LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_DEFAULT_DIRS);
      if (g_api.library != nullptr) {
        g_api.library_name = Narrow(bundled_path);
        break;
      }
      last_error = GetLastError();
    }
  }

  if (g_api.library == nullptr) {
    for (const wchar_t* name : kMpvDllNames) {
      attempted << "Windows DLL search path " << Narrow(name) << " ";
      g_api.library =
          LoadLibraryExW(name, nullptr, LOAD_LIBRARY_SEARCH_DEFAULT_DIRS);
      if (g_api.library != nullptr) {
        g_api.library_name = Narrow(name);
        break;
      }
      last_error = GetLastError();
    }
  }

  if (g_api.library == nullptr) {
    g_api.error = "libmpv DLL not found; tried " + attempted.str() + "; " +
                  LastErrorMessage(last_error);
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
  g_api.request_log_messages =
      reinterpret_cast<mpv_request_log_messages_fn>(LoadSymbol(g_api.library, "mpv_request_log_messages"));
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

bool BoolArg(const flutter::EncodableMap* args, const char* key, bool fallback) {
  if (args == nullptr) return fallback;
  auto it = args->find(flutter::EncodableValue(key));
  if (it == args->end()) return fallback;
  const bool* value = std::get_if<bool>(&it->second);
  return value == nullptr ? fallback : *value;
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

// mpv's reply userdata for the runner's own `video-params` observation, used
// to intercept HDR-relevant source changes without turning every tick of it
// into a spurious PLAYBACK_RESTART event to Dart.
constexpr uint64_t kVideoParamsHdrUserdata = UINT64_MAX;

// Creates the native child window mpv's `wid` embeds into and presents its
// own D3D11 swap chain against directly -- unlike the SW pixel-buffer path,
// mpv owns rendering and presentation here entirely; this project only owns
// creating, positioning and destroying the window.
//
// IMPORTANT CAVEAT, unresolved without a Windows box to verify against: the
// open-source Plezy player (github.com/edde746/plezy, GPL-3.0), whose child-
// window design this is adapted from, only gets correct z-ordering (video
// *behind* the Flutter-drawn UI, including player controls) because its
// engine build presents Flutter's own UI on a topmost DirectComposition
// visual explicitly ordered above the video child window. That is a
// modification to the Flutter engine itself, which this project does not
// have and cannot build here. Flutter's own `platform_view` example ships a
// Windows target that renders nothing but placeholder text, confirming the
// stock engine has no platform-view API to lean on instead. On stock
// Flutter, a plain WS_CHILD window's content is not guaranteed to composite
// *behind* what its parent draws in the same screen region -- ordinary
// Win32 z-order rules put a child's own paint *above* its parent's, which is
// backwards from what video-behind-UI needs. Concretely, this may mean video
// renders on top of player controls instead of behind them. Treat this as
// unverified until confirmed (or fixed) on real hardware.
HWND CreateGpuVideoWindow(HWND parent, std::string* error) {
  if (parent == nullptr) {
    if (error) *error = "no top-level HWND to parent the video window to";
    return nullptr;
  }
  // WS_DISABLED takes the window out of input targeting entirely, so mouse
  // input over the video reaches the parent Flutter view instead of being
  // swallowed here (mpv never needs input; input-vo-keyboard is left at its
  // default, no, and there is no forwarding subclass since this project has
  // no controls that need to arrive through mpv's own window procedure).
  // Created at 100x100, not 1x1: a D3D11 swap chain created against a 1x1
  // window is a plausible reason mpv's VO could fail to initialize outright
  // (unlike Linux's EGL surface, which tolerates a 1x1 pre-allocated buffer
  // until resize) -- matching Plezy's own verified-working size here rather
  // than the smaller value this project's Linux EGL work made look safe.
  // The real rect arrives moments later via Dart's first setVideoRect.
  constexpr DWORD kVideoHostWindowStyle = WS_CHILD | WS_CLIPSIBLINGS | WS_DISABLED;
  HWND hwnd = CreateWindowExW(
      WS_EX_NOPARENTNOTIFY, L"STATIC", L"", kVideoHostWindowStyle, 0, 0, 100, 100, parent, nullptr,
      GetModuleHandleW(nullptr), nullptr);
  if (hwnd == nullptr && error) *error = "CreateWindowExW failed: " + LastErrorMessage(GetLastError());
  return hwnd;
}

// True when `params` (a `video-params` MPV_FORMAT_NODE) describes an HDR
// source: a PQ or HLG transfer function over BT.2020 primaries. Unlike the
// Linux Wayland path, no protocol-error-prone luminance negotiation is
// needed here -- mpv's own D3D11 GPU-next VO handles the swap chain's color
// space and metadata once `target-colorspace-hint`/`hdr-compute-peak` are
// left on auto; the only decision left to this project is whether the *OS
// display* should be switched into HDR mode at all, which mpv has no way to
// do itself.
bool ParseVideoParamsIsHdr(const mpv_node* params) {
  if (params == nullptr || params->format != MPV_FORMAT_NODE_MAP || params->u.list == nullptr) return false;
  const mpv_node_list& entries = *params->u.list;
  if (entries.keys == nullptr || entries.values == nullptr) return false;

  bool is_hdr_transfer = false;
  bool is_bt2020 = false;
  for (int index = 0; index < entries.num; ++index) {
    const char* key = entries.keys[index];
    if (key == nullptr) continue;
    const mpv_node& value = entries.values[index];
    if (value.format != MPV_FORMAT_STRING || value.u.string == nullptr) continue;
    if (std::strcmp(key, "gamma") == 0) {
      is_hdr_transfer = std::strcmp(value.u.string, "pq") == 0 || std::strcmp(value.u.string, "hlg") == 0;
    } else if (std::strcmp(key, "primaries") == 0) {
      is_bt2020 = std::strcmp(value.u.string, "bt.2020") == 0;
    }
  }
  return is_hdr_transfer && is_bt2020;
}

// Toggles the OS display's HDR mode to match whether the current source is
// HDR, called on every `video-params` change. Gated on `hdr_requested` so a
// source that has not actually changed HDR-ness does not repeat the
// DisplayConfigSetDeviceInfo/registry round trip on every tick.
void ApplyHdrForVideoParams(PlayerInstance* player, const mpv_node* params) {
  if (player == nullptr || !player->using_gpu_window || player->display_mode_manager == nullptr) return;
  const bool is_hdr_source = player->hdr_user_enabled && ParseVideoParamsIsHdr(params);
  if (is_hdr_source == player->hdr_requested) return;
  player->hdr_requested = is_hdr_source;

  if (is_hdr_source) {
    if (player->display_mode_manager->IsHDRSupported(player->top_level_hwnd)) {
      player->display_mode_manager->SetHDREnabled(player->top_level_hwnd, true);
    }
  } else {
    player->display_mode_manager->RestoreOriginalHDRState(player->top_level_hwnd);
  }
}

// Re-runs the OS display HDR decision against the current source without
// waiting for another `video-params` event -- used when the user flips the
// `hdr-enabled` control mid-playback, since the source's own HDR-ness has not
// changed. Cheap no-op via ApplyHdrForVideoParams's `hdr_requested` dedup
// when the toggle did not actually change the outcome (e.g. an SDR source).
void ReapplyHdrForCurrentSource(PlayerInstance* player) {
  if (player == nullptr || player->handle == nullptr || player->api == nullptr ||
      player->api->get_property == nullptr) {
    return;
  }
  mpv_node params{};
  if (player->api->get_property(player->handle, "video-params", MPV_FORMAT_NODE, &params) >= 0) {
    ApplyHdrForVideoParams(player, &params);
    if (player->api->free_node_contents != nullptr) player->api->free_node_contents(&params);
  }
}

bool DoubleProperty(PlayerInstance* player, const char* name, double* value);

// Issues an mpv `sub-add` command for each entry of the `externalSubtitles`
// arg list (each a map with `uri`/`title`/`language` string fields). Applies
// to both the GPU and SW load paths.
void AddExternalSubtitles(LibmpvApi& api, mpv_handle* handle, const flutter::EncodableMap* args) {
  if (args == nullptr) return;
  auto it = args->find(flutter::EncodableValue("externalSubtitles"));
  if (it == args->end()) return;
  const flutter::EncodableList* subtitles = std::get_if<flutter::EncodableList>(&it->second);
  if (subtitles == nullptr) return;

  for (const flutter::EncodableValue& entry : *subtitles) {
    const flutter::EncodableMap* map = std::get_if<flutter::EncodableMap>(&entry);
    if (map == nullptr) continue;
    const auto uri_it = map->find(flutter::EncodableValue("uri"));
    if (uri_it == map->end()) continue;
    const std::string* uri = std::get_if<std::string>(&uri_it->second);
    if (uri == nullptr || uri->empty()) continue;

    std::string title;
    const auto title_it = map->find(flutter::EncodableValue("title"));
    if (title_it != map->end()) {
      if (const std::string* value = std::get_if<std::string>(&title_it->second)) title = *value;
    }
    std::string language;
    const auto language_it = map->find(flutter::EncodableValue("language"));
    if (language_it != map->end()) {
      if (const std::string* value = std::get_if<std::string>(&language_it->second)) language = *value;
    }

    // mpv_command's argv is a single nullptr-terminated array with strictly
    // positional arguments -- a nullptr placeholder in the middle (rather
    // than a shorter array) would truncate the command there, silently
    // dropping anything after it. So title/language are only appended while
    // present, and language only alongside a title, never in its place.
    std::vector<const char*> sub_args = {"sub-add", uri->c_str(), "auto"};
    if (!title.empty()) {
      sub_args.push_back(title.c_str());
      if (!language.empty()) sub_args.push_back(language.c_str());
    }
    sub_args.push_back(nullptr);
    api.command(handle, sub_args.data());
  }
}

// Attempts to lock the display's refresh rate to the source's frame rate
// (the classic "24Hz mode" home-theater feature) once per loaded source, at
// the *current* resolution only -- see DisplayModeManager::MatchRefreshRate
// for why a resolution change is deliberately never attempted.
void MaybeMatchRefreshRate(PlayerInstance* player) {
  if (player == nullptr || !player->using_gpu_window || player->display_mode_manager == nullptr) return;
  if (player->refresh_rate_matched) return;
  player->refresh_rate_matched = true;
  double fps = 0.0;
  if (DoubleProperty(player, "container-fps", &fps) && fps > 0.0) {
    player->display_mode_manager->MatchRefreshRate(player->top_level_hwnd, fps);
  }
}

ProbeMap LoadFailure(const char* code, const std::string& error) {
  return ProbeMap{
      {flutter::EncodableValue("ok"), flutter::EncodableValue(false)},
      {flutter::EncodableValue("code"), flutter::EncodableValue(code)},
      {flutter::EncodableValue("error"), flutter::EncodableValue(error)},
  };
}

void RenderUpdate(void* data) {
  TextureState* texture_state = static_cast<TextureState*>(data);
  if (texture_state != nullptr) texture_state->QueueFrame();
}

ProbeMap Load(const flutter::EncodableMap* args, HWND hwnd,
              const std::shared_ptr<PlatformDispatcher>& dispatcher,
              const std::shared_ptr<EventSinkState>& event_sink_state) {
  LibmpvApi& api = Api();
  if (!api.available()) return LoadFailure(kBackendUnavailableCode, api.error);
  if (g_texture_registrar == nullptr) {
    return LoadFailure(kBackendUnavailableCode, "Flutter texture registrar unavailable");
  }
  if (hwnd == nullptr) return LoadFailure(kBackendUnavailableCode, "Win32 HWND unavailable");

  const std::string user_agent = StringArg(args, "userAgent");
  const std::string headers = HeaderString(args);
  const std::string uri = StringArg(args, "uri");
  const int64_t start_position_ms = IntArg(args, "startPositionMs");
  std::string start_option;
  if (start_position_ms > 0) {
    const double seconds = static_cast<double>(start_position_ms) / 1000.0;
    start_option = "start=" + std::to_string(seconds);
  }
  const char* load_args[] = {"loadfile", uri.c_str(), "replace",
                             start_option.empty() ? nullptr : start_option.c_str(),
                             nullptr};

  // GPU path: mpv embeds into a native child window (`wid`) and presents its
  // own D3D11 swap chain into it directly, bypassing Flutter's texture
  // bridge entirely -- see CreateGpuVideoWindow for the one big open
  // question about whether that composites correctly on stock Flutter.
  // Falls through to the proven SW pixel-buffer path below on any failure
  // (window creation, or mpv_initialize itself failing for any reason --
  // this project cannot detect a *later*, asynchronous D3D11/VO failure the
  // way Linux's synchronously-created EGL surface could be validated up
  // front, so a VO that opens successfully at mpv_initialize time but later
  // fails to actually present is a real gap; it would surface as a black
  // video area rather than a crash).
  {
    std::string window_error;
    HWND video_hwnd = CreateGpuVideoWindow(hwnd, &window_error);
    if (video_hwnd != nullptr) {
      mpv_handle* gpu_handle = api.create();
      if (gpu_handle != nullptr) {
        api.set_option_string(gpu_handle, "terminal", "no");
        api.set_option_string(gpu_handle, "config", "no");
        const std::string wid = std::to_string(reinterpret_cast<intptr_t>(video_hwnd));
        api.set_option_string(gpu_handle, "wid", wid.c_str());
        api.set_option_string(gpu_handle, "vo", "gpu-next");
        api.set_option_string(gpu_handle, "gpu-api", "auto");
        api.set_option_string(gpu_handle, "hwdec", "auto-safe");
        api.set_option_string(gpu_handle, "idle", "yes");
        api.set_option_string(gpu_handle, "keepaspect", "no");
        api.set_option_string(gpu_handle, "sub-auto", "fuzzy");
        // mpv's own D3D11 GPU-next VO negotiates the swap chain's color
        // space and HDR metadata itself once the OS display is actually in
        // HDR mode; ApplyHdrForVideoParams (driven by video-params) is what
        // decides whether the OS display should be.
        api.set_option_string(gpu_handle, "target-colorspace-hint", "auto");
        api.set_option_string(gpu_handle, "hdr-compute-peak", "auto");
        api.set_option_string(gpu_handle, "tone-mapping", "auto");
        if (!user_agent.empty()) api.set_option_string(gpu_handle, "user-agent", user_agent.c_str());
        if (!headers.empty()) api.set_option_string(gpu_handle, "http-header-fields", headers.c_str());

        if (api.initialize(gpu_handle) >= 0) {
          const int64_t id = g_next_handle++;
          auto player =
              std::make_unique<PlayerInstance>(&api, dispatcher, event_sink_state, gpu_handle, video_hwnd, hwnd, id);
          player->StartEventThread();
          AddExternalSubtitles(api, gpu_handle, args);
          if (api.command(gpu_handle, load_args) >= 0) {
            g_players[id] = std::move(player);
            return ProbeMap{
                {flutter::EncodableValue("ok"), flutter::EncodableValue(true)},
                {flutter::EncodableValue("handle"), flutter::EncodableValue(id)},
                {flutter::EncodableValue("usesNativePlane"), flutter::EncodableValue(true)},
                {flutter::EncodableValue("display"), flutter::EncodableValue(DisplayDetails(hwnd) + " (GPU D3D11 native window)")},
            };
          }
          // loadfile failed -- player's destructor tears the GPU handle and
          // window down; nothing to fall through to.
          return LoadFailure("desktop-libmpv-load-failed", "mpv loadfile command failed");
        }
        api.terminate_destroy(gpu_handle);
      }
      DestroyWindow(video_hwnd);
    }
    // GPU path unavailable or failed; fall through to the SW path below on a
    // fresh handle.
  }

  mpv_handle* handle = api.create();
  if (handle == nullptr) return LoadFailure("desktop-libmpv-load-failed", "mpv_create returned null");

  api.set_option_string(handle, "terminal", "no");
  api.set_option_string(handle, "config", "no");
  api.set_option_string(handle, "vo", "libmpv");
  api.set_option_string(handle, "hwdec", "auto-safe");
  api.set_option_string(handle, "idle", "yes");
  api.set_option_string(handle, "keepaspect", "no");
  api.set_option_string(handle, "sub-auto", "fuzzy");
  if (!user_agent.empty()) api.set_option_string(handle, "user-agent", user_agent.c_str());
  if (!headers.empty()) api.set_option_string(handle, "http-header-fields", headers.c_str());

  int rc = api.initialize(handle);
  if (rc < 0) {
    api.terminate_destroy(handle);
    return LoadFailure("desktop-libmpv-load-failed", "mpv_initialize failed");
  }

  char api_type[] = "sw";
  mpv_render_param create_params[] = {
      {MPV_RENDER_PARAM_API_TYPE, api_type},
      {MPV_RENDER_PARAM_INVALID, nullptr},
  };
  mpv_render_context* render_context = nullptr;
  rc = api.render_context_create(&render_context, handle, create_params);
  if (rc < 0 || render_context == nullptr) {
    api.terminate_destroy(handle);
    return LoadFailure("desktop-libmpv-load-failed", "mpv_render_context_create failed");
  }

  const int64_t id = g_next_handle++;
  auto player = std::make_unique<PlayerInstance>(&api, g_texture_registrar, dispatcher,
                                                 event_sink_state, handle, render_context, id);
  auto texture = std::make_unique<flutter::TextureVariant>(flutter::PixelBufferTexture(
      [ctx = player->copy_context](size_t width, size_t height) {
        std::lock_guard<std::mutex> lock(ctx->mutex);
        if (ctx->render_context == nullptr || ctx->api == nullptr || ctx->api->render_context_render == nullptr) {
          return &ctx->pixel_buffer;
        }
        int size[] = {static_cast<int>(kTextureWidth), static_cast<int>(kTextureHeight)};
        int stride = static_cast<int>(kTextureWidth * kBytesPerPixel);
        char format[] = "rgba";
        void* buffer = ctx->pixels.data();
        mpv_render_param params[] = {{MPV_RENDER_PARAM_SW_SIZE, size}, {MPV_RENDER_PARAM_SW_FORMAT, format}, {MPV_RENDER_PARAM_SW_STRIDE, &stride}, {MPV_RENDER_PARAM_SW_POINTER, buffer}, {MPV_RENDER_PARAM_INVALID, nullptr}};
        ctx->api->render_context_render(ctx->render_context, params);
        return &ctx->pixel_buffer;
      }));
  const int64_t texture_id = g_texture_registrar->RegisterTexture(texture.get());
  if (texture_id < 0) {
    return LoadFailure("desktop-libmpv-load-failed", "Flutter texture registration failed");
  }
  player->texture = std::move(texture);
  player->texture_id = texture_id;
  player->texture_state->texture_id = texture_id;
  player->copy_context->SetUpdateCallback(RenderUpdate, player->texture_state.get());
  player->StartEventThread();
  AddExternalSubtitles(api, handle, args);

  rc = api.command(handle, load_args);
  if (rc < 0) return LoadFailure("desktop-libmpv-load-failed", "mpv loadfile command failed");

  g_players[id] = std::move(player);
  return ProbeMap{
      {flutter::EncodableValue("ok"), flutter::EncodableValue(true)},
      {flutter::EncodableValue("handle"), flutter::EncodableValue(id)},
      {flutter::EncodableValue("textureId"), flutter::EncodableValue(texture_id)},
      {flutter::EncodableValue("display"), flutter::EncodableValue(DisplayDetails(hwnd))},
  };
}


bool DoubleProperty(PlayerInstance* player, const char* name, double* value) {
  if (player == nullptr || player->api == nullptr || player->api->get_property == nullptr) return false;
  double current = 0.0;
  if (player->api->get_property(player->handle, name, MPV_FORMAT_DOUBLE, &current) < 0) return false;
  *value = current;
  return true;
}

bool FlagProperty(PlayerInstance* player, const char* name, bool* value) {
  int current = 0;
  if (player == nullptr || player->api == nullptr || player->api->get_property == nullptr ||
      player->api->get_property(player->handle, name, MPV_FORMAT_FLAG, &current) < 0) return false;
  *value = current != 0;
  return true;
}

bool StringProperty(PlayerInstance* player, const char* name, std::string* value) {
  char* current = nullptr;
  if (player == nullptr || player->api == nullptr || player->api->get_property == nullptr ||
      player->api->free == nullptr || player->api->get_property(player->handle, name, MPV_FORMAT_STRING, &current) < 0 || current == nullptr) return false;
  *value = current;
  player->api->free(current);
  return true;
}

void PlayerInstance::QueueEvent(EventSnapshot snapshot) {
  if (disposing.load() || dispatcher == nullptr) return;
  snapshot.handle = id;
  snapshot.sequence = sequence.fetch_add(1);
  std::weak_ptr<EventSinkState> sink = event_sink_state;
  dispatcher->Post([sink, snapshot]() {
    if (auto state = sink.lock()) state->Send(snapshot);
  });
}

void PlayerInstance::ReadSnapshotProperties(EventSnapshot* snapshot) {
  DoubleProperty(this, "time-pos", &snapshot->position);
  DoubleProperty(this, "duration", &snapshot->duration);
  FlagProperty(this, "pause", &snapshot->paused);
  bool paused_for_cache = false;
  FlagProperty(this, "paused-for-cache", &paused_for_cache);
  snapshot->buffering = paused_for_cache;
  FlagProperty(this, "eof-reached", &snapshot->eof);
  DoubleProperty(this, "speed", &snapshot->speed);
  if (!DoubleProperty(this, "video-params/aspect", &snapshot->video_aspect_ratio) || snapshot->video_aspect_ratio <= 0.0) {
    double width = 0.0;
    double height = 0.0;
    if (DoubleProperty(this, "dwidth", &width) && DoubleProperty(this, "dheight", &height) && height > 0.0) snapshot->video_aspect_ratio = width / height;
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
      const std::string track_id = TrackNodeString(MapNodeValue(item, "id"));
      if (track_id.empty() || (type != "audio" && type != "sub")) continue;
      const std::string language =
          TrackNodeString(MapNodeValue(item, "lang"));
      const std::string label = TrackNodeString(MapNodeValue(item, "title"));
      const std::string normalized_label = label.empty() ? language : label;
      EventSnapshot::Track track{
          track_id,
          normalized_label.empty() ? track_id : normalized_label,
          language};
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
    const char* doubles[] = {"time-pos", "duration", "speed", "video-params/aspect", "dwidth", "dheight"};
    const char* flags[] = {"pause", "paused-for-cache", "eof-reached"};
    const char* strings[] = {"aid", "sid"};
    for (const char* name : doubles) api->observe_property(handle, 0, name, MPV_FORMAT_DOUBLE);
    for (const char* name : flags) api->observe_property(handle, 0, name, MPV_FORMAT_FLAG);
    for (const char* name : strings) api->observe_property(handle, 0, name, MPV_FORMAT_STRING);
    if (api->request_log_messages != nullptr) api->request_log_messages(handle, "warn");
    if (using_gpu_window) {
      // Only the GPU/native-window path has an OS display to toggle HDR or
      // match a refresh rate against; the SW pixel-buffer path has neither.
      api->observe_property(handle, kVideoParamsHdrUserdata, "video-params", MPV_FORMAT_NODE);
      api->observe_property(handle, 0, "container-fps", MPV_FORMAT_DOUBLE);
    }
    while (!disposing.load()) {
      mpv_event* event = api->wait_event(handle, 0.1);
      if (event == nullptr || event->event_id == MPV_EVENT_NONE) continue;
      if (using_gpu_window && event->event_id == MPV_EVENT_PROPERTY_CHANGE &&
          event->reply_userdata == kVideoParamsHdrUserdata) {
        const auto* property = static_cast<const mpv_event_property*>(event->data);
        if (property != nullptr && property->format == MPV_FORMAT_NODE && property->data != nullptr) {
          ApplyHdrForVideoParams(this, static_cast<const mpv_node*>(property->data));
        }
        continue;
      }
      if (event->event_id == MPV_EVENT_LOG_MESSAGE) {
        // Cached, not forwarded to Dart on its own: this is "warn" level and
        // above (see request_log_messages above), which includes routine
        // warnings alongside the fatal/error lines that actually explain a
        // load failure. Kept so the *next* END_FILE/ERROR snapshot -- which
        // otherwise carries only mpv's sparse numeric error code -- can
        // report the real reason underneath it.
        const auto* log_message = static_cast<const mpv_event_log_message*>(event->data);
        if (log_message != nullptr && log_message->text != nullptr) {
          std::string text = log_message->text;
          while (!text.empty() && (text.back() == '\n' || text.back() == '\r')) text.pop_back();
          if (!text.empty()) {
            last_log_message = (log_message->prefix != nullptr ? std::string(log_message->prefix) + ": " : "") + text;
          }
        }
        continue;
      }
      EventSnapshot snapshot;
      if (using_gpu_window && event->event_id == MPV_EVENT_FILE_LOADED) MaybeMatchRefreshRate(this);
      if (event->event_id == MPV_EVENT_QUEUE_OVERFLOW) {
        snapshot.kind = "ERROR";
        snapshot.message = "mpv event queue overflow";
        snapshot.code = "event-queue-overflow";
        snapshot.recoverable = true;
      } else if (event->event_id == MPV_EVENT_START_FILE) {
        snapshot.kind = "START_FILE";
      } else if (event->event_id == MPV_EVENT_FILE_LOADED) {
        snapshot.kind = "FILE_LOADED";
        ReadTrackLists(&snapshot);
      } else if (event->event_id == MPV_EVENT_PLAYBACK_RESTART || event->event_id == MPV_EVENT_PROPERTY_CHANGE) {
        snapshot.kind = "PLAYBACK_RESTART";
      } else if (event->event_id == MPV_EVENT_VIDEO_RECONFIG) {
        snapshot.kind = "VIDEO_RECONFIG";
      } else if (event->event_id == MPV_EVENT_END_FILE) {
        const auto* end_file =
            static_cast<const mpv_event_end_file*>(event->data);
        const int end_file_reason = end_file == nullptr ? -1 : end_file->reason;
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
            if (!last_log_message.empty()) snapshot.message += " (" + last_log_message + ")";
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
      } else if (event->event_id == MPV_EVENT_SHUTDOWN) {
        snapshot.kind = "SHUTDOWN";
      } else if (event->error < 0) {
        snapshot.kind = "ERROR";
        snapshot.message = "libmpv event failed";
        snapshot.code = "libmpv-event-error";
        snapshot.recoverable = true;
      } else {
        continue;
      }
      ReadSnapshotProperties(&snapshot);
      QueueEvent(std::move(snapshot));
      if (event->event_id == MPV_EVENT_SHUTDOWN) disposing.store(true);
    }
  });
}

// Tears down a GPU/native-window PlayerInstance: undoes any OS-level
// display-mode/HDR override, destroys mpv (which owns its own D3D11 swap
// chain against video_hwnd -- terminate_destroy before DestroyWindow, so mpv
// tears its swap chain down against a still-valid window), then the window
// itself. Called once from PlayerInstance's destructor; kept out-of-line
// rather than inlined there for the reason given on the TeardownGpuWindow
// forward declaration above PlayerInstance.
void TeardownGpuWindow(PlayerInstance* player) {
  if (player->display_mode_manager != nullptr) {
    player->display_mode_manager->RestoreOriginalHDRState(player->top_level_hwnd);
    player->display_mode_manager->RestoreOriginalMode(player->top_level_hwnd);
  }
  if (player->api != nullptr && player->api->terminate_destroy != nullptr && player->handle != nullptr) {
    player->api->terminate_destroy(player->handle);
  }
  player->handle = nullptr;
  if (player->video_hwnd != nullptr) {
    DestroyWindow(player->video_hwnd);
    player->video_hwnd = nullptr;
  }
}

ProbeMap VideoAspectRatioResult(PlayerInstance* player) {
  ProbeMap result{
      {flutter::EncodableValue("ok"), flutter::EncodableValue(true)},
  };

  double aspect = 0.0;
  if (DoubleProperty(player, "video-params/aspect", &aspect)) {
    result[flutter::EncodableValue("videoAspectRatio")] =
        flutter::EncodableValue(aspect);
  }

  double width = 0.0;
  double height = 0.0;
  if (DoubleProperty(player, "dwidth", &width) &&
      DoubleProperty(player, "dheight", &height) && height > 0.0) {
    result[flutter::EncodableValue("videoWidth")] = flutter::EncodableValue(width);
    result[flutter::EncodableValue("videoHeight")] = flutter::EncodableValue(height);
    if (aspect <= 0.0) {
      result[flutter::EncodableValue("videoAspectRatio")] =
          flutter::EncodableValue(width / height);
    }
  }
  return result;
}

ProbeMap VideoAspectRatioForHandle(const flutter::EncodableMap* args) {
  const int64_t id = IntArg(args, "handle");
  auto it = g_players.find(id);
  if (it == g_players.end()) {
    return ProbeMap{{flutter::EncodableValue("ok"), flutter::EncodableValue(false)}};
  }
  return VideoAspectRatioResult(it->second.get());
}

void Control(const std::string& method, const flutter::EncodableMap* args) {
  const int64_t id = IntArg(args, "handle");
  auto it = g_players.find(id);
  if (it == g_players.end()) return;
  PlayerInstance* player = it->second.get();
  if (method == "setVideoRect") {
    // Reported by Dart on every layout of the widget hosting this backend;
    // a no-op for players still on the SW texture path.
    if (player->using_gpu_window && player->video_hwnd != nullptr) {
      const int x = static_cast<int>(IntArg(args, "x"));
      const int y = static_cast<int>(IntArg(args, "y"));
      const int width = static_cast<int>(IntArg(args, "width"));
      const int height = static_cast<int>(IntArg(args, "height"));
      SetWindowPos(
          player->video_hwnd, nullptr, x, y, std::max(width, 1), std::max(height, 1),
          SWP_NOZORDER | SWP_NOACTIVATE);
    }
    return;
  }
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
    EventSnapshot snapshot;
    snapshot.kind = "STOP";
    player->ReadSnapshotProperties(&snapshot);
    player->QueueEvent(std::move(snapshot));
  } else if (method == "quit") {
    const char* command[] = {"quit", nullptr};
    player->api->command(player->handle, command);
    EventSnapshot snapshot;
    snapshot.kind = "QUIT";
    player->ReadSnapshotProperties(&snapshot);
    player->QueueEvent(std::move(snapshot));
  } else if (method == "setAudioTrack") {
    const std::string track = StringArg(args, "trackId");
    const char* command[] = {"set", "aid", track.empty() ? "no" : track.c_str(), nullptr};
    player->api->command(player->handle, command);
    EventSnapshot snapshot;
    snapshot.kind = "PLAYBACK_RESTART";
    player->ReadSnapshotProperties(&snapshot);
    player->ReadTrackLists(&snapshot);
    player->QueueEvent(std::move(snapshot));
  } else if (method == "setSubtitleTrack") {
    const std::string track = StringArg(args, "trackId");
    const char* command[] = {"set", "sid", track.empty() ? "no" : track.c_str(), nullptr};
    player->api->command(player->handle, command);
    EventSnapshot snapshot;
    snapshot.kind = "PLAYBACK_RESTART";
    player->ReadSnapshotProperties(&snapshot);
    player->ReadTrackLists(&snapshot);
    player->QueueEvent(std::move(snapshot));
  } else if (method == "setPlaybackSpeed") {
    const std::string speed = std::to_string(DoubleArg(args, "speed", 1.0));
    const char* command[] = {"set", "speed", speed.c_str(), nullptr};
    player->api->command(player->handle, command);
  } else if (method == "setVolume") {
    const std::string volume = std::to_string(DoubleArg(args, "volume", 100.0));
    const char* command[] = {"set", "volume", volume.c_str(), nullptr};
    player->api->command(player->handle, command);
  } else if (method == "setHdrEnabled") {
    player->hdr_user_enabled = BoolArg(args, "enabled", true);
    ReapplyHdrForCurrentSource(player);
  } else if (method == "dispose") {
    g_players.erase(it);
  }
}

class DesktopLibmpvBackendPlugin : public flutter::Plugin {
 public:
  DesktopLibmpvBackendPlugin(flutter::PluginRegistrarWindows* registrar, HWND hwnd)
      : texture_registrar_(registrar->texture_registrar()), hwnd_(hwnd),
        dispatcher_(std::make_shared<PlatformDispatcher>(hwnd)),
        event_sink_state_(std::make_shared<EventSinkState>()) {
    g_texture_registrar = texture_registrar_;
    {
      std::lock_guard<std::mutex> lock(g_dispatcher_mutex);
      g_platform_dispatcher = dispatcher_;
    }
    channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
        registrar->messenger(), kChannelName, &flutter::StandardMethodCodec::GetInstance());
    channel_->SetMethodCallHandler([this](const MethodCall& call, std::unique_ptr<MethodResult> result) {
      HandleCall(call, std::move(result));
    });
    event_channel_ = std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
        registrar->messenger(), kEventChannelName, &flutter::StandardMethodCodec::GetInstance());
    event_channel_->SetStreamHandler(std::make_unique<EventStreamHandler>(event_sink_state_));
  }

  ~DesktopLibmpvBackendPlugin() override {
    if (event_channel_) event_channel_->SetStreamHandler(nullptr);
    event_sink_state_->Cancel();
    dispatcher_->Deactivate();
    {
      std::lock_guard<std::mutex> lock(g_dispatcher_mutex);
      g_platform_dispatcher.reset();
    }
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
      result->Success(flutter::EncodableValue(Load(args, hwnd_, dispatcher_, event_sink_state_)));
      return;
    }
    if (method == "getVideoAspectRatio") {
      result->Success(flutter::EncodableValue(VideoAspectRatioForHandle(args)));
      return;
    }
    Control(method, args);
    result->Success();
  }

  flutter::TextureRegistrar* texture_registrar_ = nullptr;
  HWND hwnd_ = nullptr;
  std::shared_ptr<PlatformDispatcher> dispatcher_;
  std::shared_ptr<EventSinkState> event_sink_state_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>> event_channel_;
};

}  // namespace

bool DispatchDesktopLibmpvPlatformMessage(WPARAM task_id) {
  std::shared_ptr<PlatformDispatcher> dispatcher;
  {
    std::lock_guard<std::mutex> lock(g_dispatcher_mutex);
    dispatcher = g_platform_dispatcher.lock();
  }
  return dispatcher != nullptr && dispatcher->Dispatch(static_cast<UINT_PTR>(task_id));
}

void RegisterDesktopLibmpvBackend(flutter::PluginRegistrarWindows* registrar, HWND hwnd) {
  // Best-effort: undoes a display-mode/HDR override left applied by a
  // previous run of this app that crashed or was killed before it could
  // restore the display itself. See DisplayModeManager::RecoverIfNeeded.
  m3u_tv_mpv_windows::DisplayModeManager::RecoverIfNeeded();
  registrar->AddPlugin(std::make_unique<DesktopLibmpvBackendPlugin>(registrar, hwnd));
}
