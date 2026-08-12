#include "desktop_libmpv_backend.h"

#import <CoreVideo/CoreVideo.h>
#import <FlutterMacOS/FlutterMacOS.h>
#import <Libmpv/mpv/client.h>
#import <Libmpv/mpv/render.h>

#include <algorithm>
#include <atomic>
#include <cctype>
#include <clocale>
#include <csignal>
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

// macOS links directly against the real MPVKit XCFramework headers (unlike
// Linux, which dlopen()s the system libmpv.so and hand-declares the client
// API, and Windows, which LoadLibraryExW()s a bundled mpv-2.dll). No symbol
// resolution table is needed here; mpv_* calls below bind at link time.

namespace {

NSString* const kChannelName = @"m3u_tv/desktop_libmpv";
NSString* const kEventChannelName = @"m3u_tv/desktop_libmpv/events";
constexpr char kBackendUnavailableCode[] = "backend_unavailable";
constexpr uint32_t kTextureWidth = 1280;
constexpr uint32_t kTextureHeight = 720;

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

NSString* NSStringOrNil(const std::string& value) {
  return value.empty() ? nil : [NSString stringWithUTF8String:value.c_str()];
}

NSString* NSStringOrEmpty(const std::string& value) {
  return NSStringOrNil(value) ?: @"";
}

// Holds the sink handed to us by the Flutter engine while something is
// listening on the event channel; cleared on cancel/dispose. Mirrors
// EventSinkState on Windows and EventChannelState on Linux.
struct EventDispatchState {
  std::mutex mutex;
  FlutterEventSink sink = nil;
  bool active = true;

  void Listen(FlutterEventSink newSink) {
    std::lock_guard<std::mutex> lock(mutex);
    sink = newSink;
  }

  void Cancel() {
    std::lock_guard<std::mutex> lock(mutex);
    sink = nil;
  }

  void Deactivate() {
    std::lock_guard<std::mutex> lock(mutex);
    active = false;
    sink = nil;
  }

  void Send(const EventSnapshot& snapshot) {
    std::lock_guard<std::mutex> lock(mutex);
    if (!active || sink == nil) return;

    NSMutableDictionary* event = [NSMutableDictionary dictionary];
    event[@"schemaVersion"] = @2;
    event[@"handle"] = @(snapshot.handle);
    event[@"sequence"] = @(snapshot.sequence);
    event[@"kind"] = [NSString stringWithUTF8String:snapshot.kind.c_str()];
    event[@"positionMs"] = @(static_cast<int64_t>(snapshot.position * 1000.0));
    event[@"paused"] = @(snapshot.paused);
    event[@"buffering"] = @(snapshot.buffering);
    event[@"eof"] = @(snapshot.eof);
    event[@"videoAspectRatio"] = @(snapshot.video_aspect_ratio);
    event[@"speed"] = @(snapshot.speed);
    event[@"recoverable"] = @(snapshot.recoverable);
    if (snapshot.duration > 0.0) {
      event[@"durationMs"] = @(static_cast<int64_t>(snapshot.duration * 1000.0));
    }
    if (snapshot.has_aid) event[@"aid"] = NSStringOrNil(snapshot.aid) ?: @"";
    if (snapshot.has_sid) event[@"sid"] = NSStringOrNil(snapshot.sid) ?: @"";
    if (snapshot.has_track_lists) {
      auto encode = [](const std::vector<EventSnapshot::Track>& tracks) {
        NSMutableArray* values = [NSMutableArray arrayWithCapacity:tracks.size()];
        for (const EventSnapshot::Track& track : tracks) {
          NSMutableDictionary* value = [NSMutableDictionary dictionary];
          value[@"id"] = [NSString stringWithUTF8String:track.id.c_str()];
          value[@"label"] = [NSString stringWithUTF8String:track.label.c_str()];
          if (!track.language.empty()) {
            value[@"language"] = [NSString stringWithUTF8String:track.language.c_str()];
          }
          [values addObject:value];
        }
        return values;
      };
      event[@"audioTracks"] = encode(snapshot.audio_tracks);
      event[@"subtitleTracks"] = encode(snapshot.subtitle_tracks);
    }
    if (!snapshot.message.empty()) event[@"message"] = NSStringOrNil(snapshot.message);
    if (!snapshot.code.empty()) event[@"code"] = NSStringOrNil(snapshot.code);

    FlutterEventSink localSink = sink;
    dispatch_async(dispatch_get_main_queue(), ^{
      localSink(event);
    });
  }
};

// Renders mpv's software output into a pooled CVPixelBufferRef and hands the
// latest completed frame to the FlutterTexture on demand. Using a pool (as
// opposed to Linux/Windows' single persistent pixel buffer, which their
// copy-based texture APIs make safe) avoids tearing: macOS/Flutter consumes
// the CVPixelBufferRef by reference for GPU compositing rather than copying
// it out synchronously, so a frame still being read by the engine must not
// be mutated in place.
struct CopyPixelsContext {
  std::mutex mutex;
  mpv_handle* handle = nullptr;
  mpv_render_context* render_context = nullptr;
  CVPixelBufferPoolRef pool = nullptr;
  CVPixelBufferRef latest_buffer = nullptr;
  bool released = false;
  id<FlutterTextureRegistry> texture_registrar = nil;
  int64_t texture_id = 0;

  ~CopyPixelsContext() {
    if (latest_buffer != nullptr) CVPixelBufferRelease(latest_buffer);
    if (pool != nullptr) CVPixelBufferPoolRelease(pool);
  }

  void EnsurePool() {
    if (pool != nullptr) return;
    NSDictionary* pixelAttributes = @{
      (NSString*)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA),
      (NSString*)kCVPixelBufferWidthKey : @(kTextureWidth),
      (NSString*)kCVPixelBufferHeightKey : @(kTextureHeight),
      (NSString*)kCVPixelBufferIOSurfacePropertiesKey : @{},
    };
    CVPixelBufferPoolCreate(kCFAllocatorDefault, nullptr,
                            (__bridge CFDictionaryRef)pixelAttributes, &pool);
  }

  void SetUpdateCallback(mpv_render_update_fn callback, void* callback_context) {
    // mpv may invoke the callback synchronously, before this call even
    // returns - RenderFrame() below takes the same `mutex`, so it must not
    // still be held here or a synchronous callback self-deadlocks the
    // calling thread.
    mpv_render_context* context = nullptr;
    {
      std::lock_guard<std::mutex> lock(mutex);
      if (released || render_context == nullptr) return;
      context = render_context;
    }
    mpv_render_context_set_update_callback(context, callback, callback_context);
  }

  // Called on the mpv event/render thread when a new frame is ready.
  void RenderFrame() {
    std::lock_guard<std::mutex> lock(mutex);
    if (released || render_context == nullptr) return;
    EnsurePool();
    if (pool == nullptr) return;

    CVPixelBufferRef buffer = nullptr;
    if (CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer) != kCVReturnSuccess ||
        buffer == nullptr) {
      return;
    }

    CVPixelBufferLockBaseAddress(buffer, 0);
    int size[] = {static_cast<int>(kTextureWidth), static_cast<int>(kTextureHeight)};
    int stride = static_cast<int>(CVPixelBufferGetBytesPerRow(buffer));
    char format[] = "bgra";
    void* pixels = CVPixelBufferGetBaseAddress(buffer);
    // Without this, mpv defaults to blocking inside render() to wait for a
    // target vsync time - there's no real display/vsync source for this
    // offscreen software target, which can block indefinitely and wedge
    // mpv's core thread along with it (every later command needing the core
    // thread then hangs the calling thread forever too).
    int block_for_target_time = 0;
    mpv_render_param params[] = {
        {MPV_RENDER_PARAM_SW_SIZE, size},
        {MPV_RENDER_PARAM_SW_FORMAT, format},
        {MPV_RENDER_PARAM_SW_STRIDE, &stride},
        {MPV_RENDER_PARAM_SW_POINTER, pixels},
        {MPV_RENDER_PARAM_BLOCK_FOR_TARGET_TIME, &block_for_target_time},
        {MPV_RENDER_PARAM_INVALID, nullptr},
    };
    mpv_render_context_render(render_context, params);
    CVPixelBufferUnlockBaseAddress(buffer, 0);

    if (latest_buffer != nullptr) CVPixelBufferRelease(latest_buffer);
    latest_buffer = buffer;

    if (texture_registrar != nil && texture_id != 0) {
      id<FlutterTextureRegistry> registrar = texture_registrar;
      int64_t textureId = texture_id;
      dispatch_async(dispatch_get_main_queue(), ^{
        [registrar textureFrameAvailable:textureId];
      });
    }
  }

  // Called by the FlutterTexture's -copyPixelBuffer on whatever thread the
  // engine chooses; must return a caller-owned (+1) reference or NULL.
  CVPixelBufferRef CopyLatestBuffer() {
    std::lock_guard<std::mutex> lock(mutex);
    if (released || latest_buffer == nullptr) return nullptr;
    return CVPixelBufferRetain(latest_buffer);
  }

  void ReleaseResources() {
    std::lock_guard<std::mutex> lock(mutex);
    if (released) return;
    released = true;
    if (render_context != nullptr) {
      mpv_render_context_free(render_context);
      render_context = nullptr;
    }
    if (handle != nullptr) {
      mpv_terminate_destroy(handle);
      handle = nullptr;
    }
    if (latest_buffer != nullptr) {
      CVPixelBufferRelease(latest_buffer);
      latest_buffer = nullptr;
    }
  }
};

bool DoubleProperty(mpv_handle* handle, const char* name, double* value) {
  if (handle == nullptr) return false;
  double current = 0.0;
  if (mpv_get_property(handle, name, MPV_FORMAT_DOUBLE, &current) < 0) return false;
  *value = current;
  return true;
}

bool FlagProperty(mpv_handle* handle, const char* name, bool* value) {
  if (handle == nullptr) return false;
  int current = 0;
  if (mpv_get_property(handle, name, MPV_FORMAT_FLAG, &current) < 0) return false;
  *value = current != 0;
  return true;
}

bool StringProperty(mpv_handle* handle, const char* name, std::string* value) {
  if (handle == nullptr) return false;
  char* current = nullptr;
  if (mpv_get_property(handle, name, MPV_FORMAT_STRING, &current) < 0 || current == nullptr) {
    return false;
  }
  *value = current;
  mpv_free(current);
  return true;
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

struct PlayerInstance {
  PlayerInstance(std::shared_ptr<EventDispatchState> dispatch_state, mpv_handle* handle,
                 mpv_render_context* render_context, int64_t id)
      : event_dispatch_state(std::move(dispatch_state)),
        handle(handle),
        render_context(render_context),
        id(id),
        copy_context(std::make_shared<CopyPixelsContext>()) {
    copy_context->handle = handle;
    copy_context->render_context = render_context;
  }

  ~PlayerInstance() {
    disposing.store(true);
    if (handle != nullptr) mpv_wakeup(handle);
    if (event_thread.joinable()) event_thread.join();
    if (handle != nullptr) mpv_unobserve_property(handle, 0);
    copy_context->SetUpdateCallback(nullptr, nullptr);
    // event_dispatch_state is shared across every player for the lifetime of
    // the event channel (mirrors Windows' single EventSinkState); it must
    // NOT be deactivated here, only in +shutdown, or disposing the first
    // player would silently kill the event channel for every later one.

    if (texture_registrar != nullptr && texture_id != 0) {
      [texture_registrar unregisterTexture:texture_id];
    }
    // mpv/render-context teardown happens after unregistering the texture so
    // a concurrent -copyPixelBuffer call never touches a freed render context.
    copy_context->ReleaseResources();
    handle = nullptr;
    render_context = nullptr;
    delete render_update_context;
    render_update_context = nullptr;
  }

  void StartEventThread();
  void QueueEvent(EventSnapshot snapshot);
  void ReadSnapshotProperties(EventSnapshot* snapshot);
  void ReadTrackLists(EventSnapshot* snapshot);

  id<FlutterTextureRegistry> texture_registrar = nil;
  std::shared_ptr<EventDispatchState> event_dispatch_state;
  mpv_handle* handle = nullptr;
  mpv_render_context* render_context = nullptr;
  int64_t id = 0;
  int64_t texture_id = 0;
  std::shared_ptr<CopyPixelsContext> copy_context;
  std::shared_ptr<CopyPixelsContext>* render_update_context = nullptr;
  std::thread event_thread;
  std::atomic<bool> disposing{false};
  std::atomic<int64_t> sequence{0};
};

id<FlutterTextureRegistry> g_texture_registrar = nil;
std::shared_ptr<EventDispatchState> g_event_dispatch_state;
int64_t g_next_handle = 1;
std::map<int64_t, std::unique_ptr<PlayerInstance>> g_players;

void PlayerInstance::QueueEvent(EventSnapshot snapshot) {
  if (disposing.load() || event_dispatch_state == nullptr) return;
  snapshot.handle = id;
  snapshot.sequence = sequence.fetch_add(1);
  event_dispatch_state->Send(snapshot);
}

void PlayerInstance::ReadSnapshotProperties(EventSnapshot* snapshot) {
  DoubleProperty(handle, "time-pos", &snapshot->position);
  DoubleProperty(handle, "duration", &snapshot->duration);
  FlagProperty(handle, "pause", &snapshot->paused);
  bool paused_for_cache = false;
  FlagProperty(handle, "paused-for-cache", &paused_for_cache);
  snapshot->buffering = paused_for_cache;
  FlagProperty(handle, "eof-reached", &snapshot->eof);
  DoubleProperty(handle, "speed", &snapshot->speed);
  if (!DoubleProperty(handle, "video-params/aspect", &snapshot->video_aspect_ratio) ||
      snapshot->video_aspect_ratio <= 0.0) {
    double width = 0.0;
    double height = 0.0;
    if (DoubleProperty(handle, "dwidth", &width) && DoubleProperty(handle, "dheight", &height) &&
        height > 0.0) {
      snapshot->video_aspect_ratio = width / height;
    }
  }
  snapshot->has_aid = StringProperty(handle, "aid", &snapshot->aid);
  snapshot->has_sid = StringProperty(handle, "sid", &snapshot->sid);
}

void PlayerInstance::ReadTrackLists(EventSnapshot* snapshot) {
  snapshot->audio_tracks.clear();
  snapshot->subtitle_tracks.clear();
  snapshot->has_track_lists = false;

  mpv_node node{};
  if (mpv_get_property(handle, "track-list", MPV_FORMAT_NODE, &node) < 0) return;
  snapshot->has_track_lists = true;
  if (node.format == MPV_FORMAT_NODE_ARRAY && node.u.list != nullptr &&
      node.u.list->values != nullptr) {
    for (int index = 0; index < node.u.list->num; ++index) {
      const mpv_node& item = node.u.list->values[index];
      const std::string type = TrackNodeString(MapNodeValue(item, "type"));
      const std::string track_id = TrackNodeString(MapNodeValue(item, "id"));
      if (track_id.empty() || (type != "audio" && type != "sub")) continue;
      const std::string language = TrackNodeString(MapNodeValue(item, "lang"));
      const std::string label = TrackNodeString(MapNodeValue(item, "title"));
      const std::string normalized_label = label.empty() ? language : label;
      EventSnapshot::Track track{track_id, normalized_label.empty() ? track_id : normalized_label,
                                  language};
      if (type == "audio") {
        snapshot->audio_tracks.push_back(std::move(track));
      } else if (type == "sub") {
        snapshot->subtitle_tracks.push_back(std::move(track));
      }
    }
  }
  mpv_free_node_contents(&node);
}

void PlayerInstance::StartEventThread() {
  event_thread = std::thread([this]() {
    const char* doubles[] = {"time-pos", "duration",           "speed",
                              "video-params/aspect", "dwidth",  "dheight"};
    const char* flags[] = {"pause", "paused-for-cache", "eof-reached"};
    const char* strings[] = {"aid", "sid"};
    for (const char* name : doubles) mpv_observe_property(handle, 0, name, MPV_FORMAT_DOUBLE);
    for (const char* name : flags) mpv_observe_property(handle, 0, name, MPV_FORMAT_FLAG);
    for (const char* name : strings) mpv_observe_property(handle, 0, name, MPV_FORMAT_STRING);

    while (!disposing.load()) {
      mpv_event* event = mpv_wait_event(handle, 0.05);
      if (event == nullptr || event->event_id == MPV_EVENT_NONE) continue;

      EventSnapshot snapshot;
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
      } else if (event->event_id == MPV_EVENT_PLAYBACK_RESTART ||
                 event->event_id == MPV_EVENT_PROPERTY_CHANGE) {
        snapshot.kind = "PLAYBACK_RESTART";
      } else if (event->event_id == MPV_EVENT_VIDEO_RECONFIG) {
        snapshot.kind = "VIDEO_RECONFIG";
      } else if (event->event_id == MPV_EVENT_END_FILE) {
        const auto* end_file = static_cast<const mpv_event_end_file*>(event->data);
        const int reason = end_file == nullptr ? -1 : end_file->reason;
        switch (reason) {
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
            snapshot.message = "libmpv end-file error " + std::to_string(end_file->error);
            snapshot.code = "mpv-end-file-error";
            snapshot.recoverable = true;
            break;
          case MPV_END_FILE_REASON_REDIRECT:
            continue;
          default:
            snapshot.kind = "ERROR";
            snapshot.message = "unknown libmpv end-file reason " + std::to_string(reason);
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

void RenderUpdate(void* data) {
  auto* copy_context = static_cast<std::shared_ptr<CopyPixelsContext>*>(data);
  if (copy_context == nullptr || *copy_context == nullptr) return;
  (*copy_context)->RenderFrame();
}

std::string DisplayDetails(bool owned_surface) {
  std::ostringstream details;
  details << "windowSystem=cocoa-calayer; ownedSurface="
          << (owned_surface ? "available" : "unavailable")
          << "; texture=CVPixelBuffer via FlutterTextureRegistry; render=libmpv software API";
  return details.str();
}

NSDictionary* ProbeResult() {
  const bool has_registrar = g_texture_registrar != nil;
  // Linked directly against MPVKit's real headers, so client/render symbols
  // are always resolvable if this binary linked at all; the only runtime
  // unknown on macOS is texture registrar availability.
  std::string details = has_registrar
      ? "MPVKit client/render symbols linked at build time"
      : "Flutter texture registrar unavailable";
  details += "; " + DisplayDetails(has_registrar);

  return @{
    @"platform" : @"macos",
    @"windowSystem" : @"cocoa-calayer",
    @"videoApi" : @"CVPixelBuffer FlutterTexture using libmpv software render API (MPVKit)",
    @"ownedSurface" : @YES,
    @"libmpvAvailable" : @YES,
    @"renderApiAvailable" : @YES,
    @"canPlayFixture" : @(has_registrar),
    @"fallbackDecision" : has_registrar ? @"none" : @"server-transcode until Flutter texture registrar is available",
    @"details" : NSStringOrEmpty(details),
  };
}

std::string StringArg(NSDictionary* args, NSString* key) {
  id value = args[key];
  if (![value isKindOfClass:[NSString class]]) return "";
  const char* utf8 = [(NSString*)value UTF8String];
  return utf8 == nullptr ? "" : utf8;
}

int64_t IntArg(NSDictionary* args, NSString* key) {
  id value = args[key];
  return [value isKindOfClass:[NSNumber class]] ? [(NSNumber*)value longLongValue] : 0;
}

double DoubleArg(NSDictionary* args, NSString* key, double fallback) {
  id value = args[key];
  return [value isKindOfClass:[NSNumber class]] ? [(NSNumber*)value doubleValue] : fallback;
}

std::string HeaderString(NSDictionary* args) {
  id headers = args[@"headers"];
  if (![headers isKindOfClass:[NSDictionary class]]) return "";
  std::ostringstream value;
  for (NSString* key in (NSDictionary*)headers) {
    id item = ((NSDictionary*)headers)[key];
    if (![key isKindOfClass:[NSString class]] || ![item isKindOfClass:[NSString class]]) continue;
    if (value.tellp() > 0) value << ",";
    value << [key UTF8String] << ": " << [(NSString*)item UTF8String];
  }
  return value.str();
}

NSDictionary* LoadFailure(const char* code, const std::string& error) {
  return @{
    @"ok" : @NO,
    @"code" : [NSString stringWithUTF8String:code] ?: @"",
    @"error" : NSStringOrEmpty(error),
  };
}

NSDictionary* VideoAspectRatioResult(PlayerInstance* player) {
  NSMutableDictionary* result = [NSMutableDictionary dictionaryWithDictionary:@{@"ok" : @YES}];

  double aspect = 0.0;
  if (DoubleProperty(player->handle, "video-params/aspect", &aspect)) {
    result[@"videoAspectRatio"] = @(aspect);
  }
  double width = 0.0;
  double height = 0.0;
  if (DoubleProperty(player->handle, "dwidth", &width) &&
      DoubleProperty(player->handle, "dheight", &height) && height > 0.0) {
    result[@"videoWidth"] = @(width);
    result[@"videoHeight"] = @(height);
    if (aspect <= 0.0) result[@"videoAspectRatio"] = @(width / height);
  }
  return result;
}

}  // namespace

// FlutterTexture backed by the latest CVPixelBufferRef rendered by mpv's
// software render API. Structurally the macOS counterpart of Linux's
// MpvTexture (FlPixelBufferTexture) and Windows' PixelBufferTexture lambda.
@interface MpvTexture : NSObject <FlutterTexture>
@property(nonatomic) std::shared_ptr<CopyPixelsContext> copyContext;
@end

@implementation MpvTexture

- (CVPixelBufferRef _Nullable)copyPixelBuffer {
  if (!_copyContext) return nullptr;
  return _copyContext->CopyLatestBuffer();
}

@end

@interface DesktopLibmpvEventStreamHandler : NSObject <FlutterStreamHandler>
@property(nonatomic) std::shared_ptr<EventDispatchState> state;
@end

@implementation DesktopLibmpvEventStreamHandler

- (FlutterError* _Nullable)onListenWithArguments:(id _Nullable)arguments
                                        eventSink:(FlutterEventSink)events {
  if (_state) _state->Listen(events);
  return nil;
}

- (FlutterError* _Nullable)onCancelWithArguments:(id _Nullable)arguments {
  if (_state) _state->Cancel();
  return nil;
}

@end

@implementation DesktopLibmpvBackend

+ (NSDictionary*)load:(NSDictionary*)args
      textureRegistrar:(id<FlutterTextureRegistry>)textureRegistrar
     eventDispatchState:(std::shared_ptr<EventDispatchState>)eventDispatchState {
  if (textureRegistrar == nil) {
    return LoadFailure(kBackendUnavailableCode, "Flutter texture registrar unavailable");
  }
  if (eventDispatchState == nullptr) {
    return LoadFailure(kBackendUnavailableCode, "Flutter event channel unavailable");
  }

  // mpv requires the C numeric locale (its own option-string parsing is
  // locale-sensitive); a non-"C" LC_NUMERIC that uses ',' as the decimal
  // separator turns "start=123.45" into "start=123,45", which mpv's
  // comma-delimited option-string parser reads as two malformed options and
  // rejects with MPV_ERROR_INVALID_PARAMETER. Matches the same fix already
  // applied on Linux (desktop_libmpv_backend.cc).
  setlocale(LC_NUMERIC, "C");
  mpv_handle* handle = mpv_create();
  if (handle == nullptr) {
    return LoadFailure("desktop-libmpv-load-failed", "mpv_create returned null");
  }

  mpv_set_option_string(handle, "terminal", "no");
  mpv_set_option_string(handle, "config", "no");
  mpv_set_option_string(handle, "vo", "libmpv");
  // "auto-safe" (used on Linux/Windows) selects VideoToolbox hwdec here,
  // whose frames are hardware surfaces that don't convert cleanly back to
  // the plain CPU buffer this software-render path
  // (MPV_RENDER_PARAM_SW_POINTER) expects - suspected cause of the
  // black-screen/no-audio/frozen-core-thread failure seen on macOS.
  // Disabled until that's confirmed and a working hwdec path is found.
  mpv_set_option_string(handle, "hwdec", "no");
  mpv_set_option_string(handle, "idle", "yes");
  mpv_set_option_string(handle, "keepaspect", "no");
  // libass (subtitle burn-in) needs a font provider to rasterize glyphs.
  // MPVKit is a portable cross-platform build, and if its libass defaults
  // to fontconfig (the Linux-style provider) rather than CoreText on
  // macOS, it can fail to find any usable font inside this app bundle and
  // silently render nothing - no error, subtitles just never appear. Force
  // CoreText, the native macOS text provider, explicitly.
  mpv_set_option_string(handle, "sub-font-provider", "coretext");
  const std::string user_agent = StringArg(args, @"userAgent");
  if (!user_agent.empty()) mpv_set_option_string(handle, "user-agent", user_agent.c_str());
  const std::string headers = HeaderString(args);
  if (!headers.empty()) mpv_set_option_string(handle, "http-header-fields", headers.c_str());

  int rc = mpv_initialize(handle);
  if (rc < 0) {
    const std::string detail =
        std::string("mpv_initialize failed: ") + mpv_error_string(rc);
    mpv_terminate_destroy(handle);
    return LoadFailure("desktop-libmpv-load-failed", detail);
  }

  char api_type[] = MPV_RENDER_API_TYPE_SW;
  mpv_render_param create_params[] = {
      {MPV_RENDER_PARAM_API_TYPE, api_type},
      {MPV_RENDER_PARAM_INVALID, nullptr},
  };
  mpv_render_context* render_context = nullptr;
  rc = mpv_render_context_create(&render_context, handle, create_params);
  if (rc < 0 || render_context == nullptr) {
    const std::string detail = rc < 0
        ? std::string("mpv_render_context_create failed: ") + mpv_error_string(rc)
        : std::string("mpv_render_context_create returned a null context");
    mpv_terminate_destroy(handle);
    return LoadFailure("desktop-libmpv-load-failed", detail);
  }

  const int64_t playerId = g_next_handle++;
  auto player = std::make_unique<PlayerInstance>(eventDispatchState, handle, render_context, playerId);
  player->texture_registrar = textureRegistrar;

  MpvTexture* texture = [[MpvTexture alloc] init];
  texture.copyContext = player->copy_context;
  const int64_t textureId = [textureRegistrar registerTexture:texture];
  if (textureId < 0) {
    return LoadFailure("desktop-libmpv-load-failed", "Flutter texture registration failed");
  }
  player->texture_id = textureId;
  player->copy_context->texture_registrar = textureRegistrar;
  player->copy_context->texture_id = textureId;

  // mpv only ever hands this pointer back to RenderUpdate(); it must stay
  // alive for as long as the render context can invoke the callback, so it
  // is heap-allocated here and freed in ~PlayerInstance() after the update
  // callback has been cleared.
  player->render_update_context = new std::shared_ptr<CopyPixelsContext>(player->copy_context);
  player->copy_context->SetUpdateCallback(RenderUpdate, player->render_update_context);
  player->StartEventThread();

  const std::string uri = StringArg(args, @"uri");
  const int64_t startPositionMs = IntArg(args, @"startPositionMs");
  if (startPositionMs > 0) {
    // Set as a plain option rather than appending "start=<seconds>" as
    // loadfile's positional options argument - that positional argument
    // consistently produced MPV_ERROR_INVALID_PARAMETER against MPVKit's
    // mpv build even with LC_NUMERIC forced to "C", for reasons not fully
    // root-caused. Setting the option directly before loadfile sidesteps
    // that argument-parsing path entirely and is applied to the file this
    // loadfile call is about to open.
    const double seconds = static_cast<double>(startPositionMs) / 1000.0;
    const std::string start_value = std::to_string(seconds);
    mpv_set_option_string(handle, "start", start_value.c_str());
  }
  const char* loadArgs[] = {"loadfile", uri.c_str(), "replace", nullptr};
  rc = mpv_command(handle, loadArgs);
  if (rc < 0) {
    const std::string detail =
        std::string("mpv loadfile command failed: ") + mpv_error_string(rc);
    return LoadFailure("desktop-libmpv-load-failed", detail);
  }

  g_players[playerId] = std::move(player);
  return @{
    @"ok" : @YES,
    @"handle" : @(playerId),
    @"textureId" : @(textureId),
    @"display" : NSStringOrEmpty(DisplayDetails(true)),
  };
}

+ (void)control:(NSString*)method arguments:(NSDictionary*)args {
  const int64_t playerId = IntArg(args, @"handle");
  auto it = g_players.find(playerId);
  if (it == g_players.end()) return;
  PlayerInstance* player = it->second.get();

  if ([method isEqualToString:@"play"]) {
    const char* command[] = {"set", "pause", "no", nullptr};
    mpv_command(player->handle, command);
  } else if ([method isEqualToString:@"pause"]) {
    const char* command[] = {"set", "pause", "yes", nullptr};
    mpv_command(player->handle, command);
  } else if ([method isEqualToString:@"seek"]) {
    const double seconds = static_cast<double>(IntArg(args, @"positionMs")) / 1000.0;
    const std::string value = std::to_string(seconds);
    const char* command[] = {"seek", value.c_str(), "absolute", nullptr};
    mpv_command(player->handle, command);
  } else if ([method isEqualToString:@"stop"]) {
    const char* command[] = {"stop", nullptr};
    mpv_command(player->handle, command);
    EventSnapshot snapshot;
    snapshot.kind = "STOP";
    player->ReadSnapshotProperties(&snapshot);
    player->QueueEvent(std::move(snapshot));
  } else if ([method isEqualToString:@"quit"]) {
    const char* command[] = {"quit", nullptr};
    mpv_command(player->handle, command);
    EventSnapshot snapshot;
    snapshot.kind = "QUIT";
    player->ReadSnapshotProperties(&snapshot);
    player->QueueEvent(std::move(snapshot));
  } else if ([method isEqualToString:@"setAudioTrack"]) {
    const std::string track = StringArg(args, @"trackId");
    const char* command[] = {"set", "aid", track.empty() ? "no" : track.c_str(), nullptr};
    mpv_command(player->handle, command);
    EventSnapshot snapshot;
    snapshot.kind = "PLAYBACK_RESTART";
    player->ReadSnapshotProperties(&snapshot);
    player->ReadTrackLists(&snapshot);
    player->QueueEvent(std::move(snapshot));
  } else if ([method isEqualToString:@"setSubtitleTrack"]) {
    const std::string track = StringArg(args, @"trackId");
    const char* command[] = {"set", "sid", track.empty() ? "no" : track.c_str(), nullptr};
    mpv_command(player->handle, command);
    EventSnapshot snapshot;
    snapshot.kind = "PLAYBACK_RESTART";
    player->ReadSnapshotProperties(&snapshot);
    player->ReadTrackLists(&snapshot);
    player->QueueEvent(std::move(snapshot));
  } else if ([method isEqualToString:@"setPlaybackSpeed"]) {
    const std::string speed = std::to_string(DoubleArg(args, @"speed", 1.0));
    const char* command[] = {"set", "speed", speed.c_str(), nullptr};
    mpv_command(player->handle, command);
  } else if ([method isEqualToString:@"dispose"]) {
    // ~PlayerInstance() joins the mpv event thread, which can take longer
    // than a "quick" cleanup if that thread is blocked inside mpv (e.g. a
    // wedged core thread) - do the actual teardown off the main/platform
    // thread so a stuck player can't freeze the whole app's run loop.
    // Extracting the raw pointer before dispatching keeps g_players itself
    // only ever touched on the main thread; std::unique_ptr isn't copyable
    // so it can't be captured into the block directly.
    PlayerInstance* owned = it->second.release();
    g_players.erase(it);
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
      delete owned;
    });
  }
}

+ (void)registerWithRegistry:(NSObject<FlutterPluginRegistry>*)registry {
  // mpv/FFmpeg's HLS networking writes to sockets on its own threads; if the
  // remote end resets/closes the connection, an unhandled write raises
  // SIGPIPE, whose default disposition kills the whole process instantly
  // with no crash report (unlike SIGSEGV/SIGABRT, ReportCrash does not
  // intercept SIGPIPE) - it looks exactly like the app quit. Cocoa apps
  // don't ignore SIGPIPE by default, so it must be silenced explicitly here.
  signal(SIGPIPE, SIG_IGN);

  NSObject<FlutterPluginRegistrar>* registrar =
      [registry registrarForPlugin:@"DesktopLibmpvBackend"];
  g_texture_registrar = registrar.textures;
  g_event_dispatch_state = std::make_shared<EventDispatchState>();

  FlutterMethodChannel* channel = [FlutterMethodChannel methodChannelWithName:kChannelName
                                                                binaryMessenger:registrar.messenger];
  id<FlutterTextureRegistry> textureRegistrar = g_texture_registrar;
  std::shared_ptr<EventDispatchState> eventDispatchState = g_event_dispatch_state;
  [channel setMethodCallHandler:^(FlutterMethodCall* call, FlutterResult result) {
    NSDictionary* args = [call.arguments isKindOfClass:[NSDictionary class]]
                              ? (NSDictionary*)call.arguments
                              : @{};
    if ([call.method isEqualToString:@"probe"]) {
      result(ProbeResult());
    } else if ([call.method isEqualToString:@"load"]) {
      result([DesktopLibmpvBackend load:args
                        textureRegistrar:textureRegistrar
                       eventDispatchState:eventDispatchState]);
    } else if ([call.method isEqualToString:@"getVideoAspectRatio"]) {
      const int64_t playerId = IntArg(args, @"handle");
      auto it = g_players.find(playerId);
      result(it == g_players.end() ? @{@"ok" : @NO} : VideoAspectRatioResult(it->second.get()));
    } else {
      [DesktopLibmpvBackend control:call.method arguments:args];
      result(nil);
    }
  }];

  FlutterEventChannel* eventChannel =
      [FlutterEventChannel eventChannelWithName:kEventChannelName
                                 binaryMessenger:registrar.messenger];
  DesktopLibmpvEventStreamHandler* handler = [[DesktopLibmpvEventStreamHandler alloc] init];
  handler.state = eventDispatchState;
  [eventChannel setStreamHandler:handler];
}

+ (void)shutdown {
  g_players.clear();
  if (g_event_dispatch_state != nullptr) g_event_dispatch_state->Deactivate();
  g_event_dispatch_state.reset();
  g_texture_registrar = nil;
}

@end
