#include <jni.h>
#include <mpv/client.h>
#include <pthread.h>

#include <clocale>
#include <cstring>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

extern "C" {
#include <libavcodec/jni.h>
}

#include "event.h"
#include "globals.h"
#include "jni_utils.h"
#include "log.h"
#include "session.h"

#define ARRAYLEN(a) (sizeof(a) / sizeof(a[0]))

void render_cleanup(JNIEnv* env, Session& session);

extern "C" {
jni_func(jlong, nativeCreate, jobject appctx);
jni_func(jint, nativeInit, jlong session);
jni_func(void, nativeDestroy, jlong session);

jni_func(jlong, nativeCommand, jlong session, jobjectArray jarray);
jni_func(jint, nativeHookAdd, jlong session, jstring name, jint priority);
jni_func(void, nativeHookContinue, jlong session, jlong id);
};

JavaVM* g_vm;

static std::once_flag environment_once;

// Process-wide JNI and FFmpeg wiring, done exactly once. Sessions coexist - a
// retiring one can still be terminating when its successor opens - so this
// must never be rewritten underneath a session that can still call back, and
// the app context global ref is taken a single time rather than per create.
static void prepare_environment(JNIEnv* env, jobject appctx) {
  std::call_once(environment_once, [env, appctx] {
    setlocale(LC_NUMERIC, "C");

    if (!env->GetJavaVM(&g_vm) && g_vm) av_jni_set_java_vm(g_vm, NULL);

    jobject global_appctx = env->NewGlobalRef(appctx);
    if (global_appctx) av_jni_set_android_app_ctx(global_appctx, NULL);

    init_methods_cache(env);
  });
}

// bionic's mallopt is API 26+ and M_PURGE API 28+, above this module's minSdk,
// so the symbol is resolved weakly and simply skipped on an older device.
#define MP_M_PURGE (-101)
extern "C" int mallopt(int, int) __attribute__((weak));

static void purge_native_arena() {
  if (mallopt) mallopt(MP_M_PURGE, 0);
}

// Terminates a retired session off the caller's thread. mpv_terminate_destroy
// blocks through decoder and video-output teardown, and on a wedged vendor
// decoder may never return; it must cost this thread only, never the player
// core that is waiting to open the next session.
static void* terminate_session_thread(void* arg) {
  std::unique_ptr<std::shared_ptr<Session>> owned(static_cast<std::shared_ptr<Session>*>(arg));
  Session& s = **owned;

  mpv_terminate_destroy(s.handle);

  // The video output can hold the Surfaces until its final teardown, so their
  // global refs are released only once termination has returned.
  JNIEnv* env = NULL;
  if (acquire_jni_env(g_vm, &env) && env) {
    render_cleanup(env, s);
    g_vm->DetachCurrentThread();
  }

  // A 4K session grows the native arena by ~115 MB and hands almost all of it
  // back here, but Scudo keeps the freed pages resident for a long time. Ask
  // once, at the one moment a large, short-lived arena has just drained, as
  // Plezy's module does.
  purge_native_arena();
  return NULL;
}

jni_func(jlong, nativeCreate, jobject appctx) {
  prepare_environment(env, appctx);

  // No predecessor is consulted, waited for, or destroyed here: a session that
  // is still terminating owns nothing this one needs.
  mpv_handle* mpv = mpv_create();
  if (!mpv) {
    die("context init failed");
    return 0;
  }

  // Warn and above is every line the player core reads (it reports the last
  // error-level line with a failed end-file); verbose would push hundreds of
  // lines a second across JNI for nothing.
  mpv_request_log_messages(mpv, "warn");
  return (jlong)session_register(mpv)->id;
}

jni_func(jint, nativeInit, jlong session) {
  // Read-held across mpv_initialize and the event thread's start, like every
  // other entry. That is what keeps a retirement from overlapping the
  // initialization it is retiring: nativeDestroy takes admission for write,
  // which drains this reader first, and one that got there before this call
  // has already unpublished the session so the lookup below fails.
  SessionGuard guard(session);
  if (!guard.mpv) return MPV_ERROR_UNINITIALIZED;
  Session& s = *guard.session;

  const int result = mpv_initialize(guard.mpv);
  if (result < 0) {
    ALOGE("mpv_initialize returned error %s", mpv_error_string(result));
    return result;
  }

  if (pthread_create(&s.event_thread, NULL, event_thread, &s) != 0) {
    ALOGE("event thread create failed");
    return MPV_ERROR_GENERIC;
  }
  s.event_thread_started = true;
  pthread_setname_np(s.event_thread, "event_thread");
  return 0;
}

jni_func(void, nativeDestroy, jlong session) {
  // Unpublished first, so no later JNI entry can find it and exactly one
  // caller is handed the retirement. A wrapper whose session is already gone
  // has nothing left to destroy.
  std::shared_ptr<Session> s = session_retire((uint64_t)session);
  if (!s) return;

  {
    pthread_rwlock_wrlock(&s->admission);
    s->retired = true;
    pthread_rwlock_unlock(&s->admission);
  }

  // Admission is revoked and its readers have drained; the event thread is the
  // handle's only remaining borrower, and a callback that reenters through a
  // SessionGuard during this join is refused and returns.
  if (s->event_thread_started) {
    s->event_thread_exit = true;
    mpv_wakeup(s->handle);
    pthread_join(s->event_thread, NULL);
    s->event_thread_started = false;
  }

  // Termination runs on a detached thread that owns the session from here.
  auto* owned = new std::shared_ptr<Session>(s);
  pthread_t tid;
  if (pthread_create(&tid, NULL, terminate_session_thread, owned) == 0) {
    pthread_detach(tid);
  } else {
    terminate_session_thread(owned);
  }
}

// Runs a command synchronously. Returns the negative mpv error on failure,
// the `playlist_entry_id` a `loadfile` created (always > 0), or 0 for a
// command that succeeded without one. A retired session reports
// MPV_ERROR_UNINITIALIZED like any other rejected command.
jni_func(jlong, nativeCommand, jlong session, jobjectArray jarray) {
  SessionGuard guard(session);
  if (!guard.mpv) return MPV_ERROR_UNINITIALIZED;

  const char* arguments[128] = {0};
  int len = env->GetArrayLength(jarray);
  if (len >= (int)ARRAYLEN(arguments)) {
    ALOGE("too many command arguments");
    return MPV_ERROR_INVALID_PARAMETER;
  }

  std::vector<std::string> storage;
  storage.reserve(len);
  for (int i = 0; i < len; ++i) {
    jstring jarg = (jstring)env->GetObjectArrayElement(jarray, i);
    storage.push_back(java_string_to_utf8(env, jarg));
    arguments[i] = storage.back().c_str();
    env->DeleteLocalRef(jarg);
  }

  mpv_node result{};
  const int status = mpv_command_ret(guard.mpv, arguments, &result);
  if (status < 0) {
    ALOGE("mpv_command(%s) returned error %s", len > 0 ? arguments[0] : "", mpv_error_string(status));
    return status;
  }

  jlong playlist_entry_id = 0;
  const mpv_node_list* map = result.format == MPV_FORMAT_NODE_MAP ? result.u.list : nullptr;
  if (map && map->keys && map->values) {
    for (int i = 0; i < map->num; ++i) {
      if (map->keys[i] && strcmp(map->keys[i], "playlist_entry_id") == 0 && map->values[i].format == MPV_FORMAT_INT64) {
        playlist_entry_id = (jlong)map->values[i].u.int64;
        break;
      }
    }
  }
  mpv_free_node_contents(&result);
  return playlist_entry_id;
}

// Registers a hook (e.g. on_preloaded, which runs after the demuxer opened a
// file and before the decoders are created). mpv holds playback at the hook
// until Kotlin answers through nativeHookContinue; see MpvPlayer.hookHandler.
jni_func(jint, nativeHookAdd, jlong session, jstring jname, jint priority) {
  SessionGuard guard(session);
  if (!guard.mpv) return MPV_ERROR_UNINITIALIZED;

  const std::string name = java_string_to_utf8(env, jname);
  const int result = mpv_hook_add(guard.mpv, 0, name.c_str(), (int)priority);
  if (result < 0) ALOGE("mpv_hook_add(%s) returned error %s", name.c_str(), mpv_error_string(result));
  return result;
}

// A continuation for a retired session is dropped, even while its handle is
// still terminating. Destruction releases any outstanding hooks; a session's
// hook ids are its own, so no other session can ever receive one.
jni_func(void, nativeHookContinue, jlong session, jlong id) {
  SessionGuard guard(session);
  if (!guard.mpv) return;
  mpv_hook_continue(guard.mpv, (uint64_t)id);
}
