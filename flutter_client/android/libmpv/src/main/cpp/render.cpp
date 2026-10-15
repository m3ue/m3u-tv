#include <jni.h>
#include <mpv/client.h>

#include <cstdint>

#include "jni_utils.h"
#include "log.h"
#include "session.h"

extern "C" {
jni_func(jint, nativeAttachSurface, jlong session, jobject surface_);
jni_func(void, nativeDetachSurface, jlong session);
jni_func(jint, nativeAttachOsdSurface, jlong session, jobject surface_);
jni_func(void, nativeDetachOsdSurface, jlong session);
};

// Admission precedes this mutex, and it belongs to the session whose Surfaces
// it guards. Teardown drains admission before cleanup and never takes this
// mutex, so a waiting handoff cannot outlive its mpv handle.
class SurfaceGuard {
 public:
  explicit SurfaceGuard(Session& session) : session(session) { pthread_mutex_lock(&session.surface_lock); }
  ~SurfaceGuard() { pthread_mutex_unlock(&session.surface_lock); }
  SurfaceGuard(const SurfaceGuard&) = delete;
  SurfaceGuard& operator=(const SurfaceGuard&) = delete;

 private:
  Session& session;
};

// Hands mpv a Surface through [option] and swaps it into [slot]. The previous
// ref is released only once mpv has taken the new one.
static int attach(JNIEnv* env, mpv_handle* mpv, const char* option, jobject surface_, jobject& slot) {
  if (!surface_) return MPV_ERROR_INVALID_PARAMETER;
  jobject next = env->NewGlobalRef(surface_);
  if (!next) return MPV_ERROR_NOMEM;

  int64_t wid = static_cast<int64_t>(reinterpret_cast<uintptr_t>(next));
  const int result = mpv_set_option(mpv, option, MPV_FORMAT_INT64, &wid);
  if (result < 0) {
    ALOGE("mpv_set_option(%s) returned error %s", option, mpv_error_string(result));
    env->DeleteGlobalRef(next);
    return result;
  }
  if (slot) env->DeleteGlobalRef(slot);
  slot = next;
  return 0;
}

// The global ref must outlive the VO's use of it, so mpv is told to drop the
// Surface first and the ref is released after.
static void detach(JNIEnv* env, mpv_handle* mpv, const char* option, jobject& slot) {
  if (!slot) return;
  int64_t wid = 0;
  const int result = mpv_set_option(mpv, option, MPV_FORMAT_INT64, &wid);
  if (result < 0) ALOGE("mpv_set_option(%s) returned error %s", option, mpv_error_string(result));
  env->DeleteGlobalRef(slot);
  slot = nullptr;
}

jni_func(jint, nativeAttachSurface, jlong session, jobject surface_) {
  SessionGuard guard(session);
  if (!guard.mpv) return MPV_ERROR_UNINITIALIZED;
  SurfaceGuard lock(*guard.session);
  return attach(env, guard.mpv, "wid", surface_, guard.session->surface);
}

jni_func(void, nativeDetachSurface, jlong session) {
  SessionGuard guard(session);
  if (!guard.mpv) return;
  SurfaceGuard lock(*guard.session);
  detach(env, guard.mpv, "wid", guard.session->surface);
}

// The OSD plane of vo=mediacodec. Same lifetime rules as the video surface:
// detach only after vo has been unset.
jni_func(jint, nativeAttachOsdSurface, jlong session, jobject surface_) {
  SessionGuard guard(session);
  if (!guard.mpv) return MPV_ERROR_UNINITIALIZED;
  SurfaceGuard lock(*guard.session);
  return attach(env, guard.mpv, "vo-mediacodec-osd-surface", surface_, guard.session->osd_surface);
}

jni_func(void, nativeDetachOsdSurface, jlong session) {
  SessionGuard guard(session);
  if (!guard.mpv) return;
  SurfaceGuard lock(*guard.session);
  detach(env, guard.mpv, "vo-mediacodec-osd-surface", guard.session->osd_surface);
}

// Called once the session was unpublished, admission revoked and its JNI
// readers drained, the event thread joined and mpv terminated. Nothing else
// can reach these fields by then: every entry that could touch them is refused
// on [Session::retired] before it dereferences the session.
void render_cleanup(JNIEnv* env, Session& session) {
  if (session.surface) {
    env->DeleteGlobalRef(session.surface);
    session.surface = nullptr;
  }
  if (session.osd_surface) {
    env->DeleteGlobalRef(session.osd_surface);
    session.osd_surface = nullptr;
  }
}
