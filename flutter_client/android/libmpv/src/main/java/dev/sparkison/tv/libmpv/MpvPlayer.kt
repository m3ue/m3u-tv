package dev.sparkison.tv.libmpv

import android.content.Context
import android.view.Surface
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import kotlin.coroutines.coroutineContext

/**
 * Kotlin face of one native player session. The JNI layer gives each session
 * its own mpv handle, event thread and Surfaces, refuses any call that names a
 * session it has retired, and stamps every callback with the session it came
 * from; Kotlin routes a callback only to the wrapper registered for that
 * session. Together they make a retiring wrapper's in-flight work (a queued
 * property write, a late hook continuation) inert against its successor, and
 * keep its tail events out of the successor's flows (Plezy 1d5b175cc).
 */
class MpvPlayer private constructor(
  /** Identity of the native session this wrapper owns; see nativeCreate. */
  val session: Long
) : AutoCloseable {

  companion object {
    /** Upper bound for a hook handler; longer stalls playback start. */
    private const val HOOK_TIMEOUT_MS = 3_000L

    init {
      System.loadLibrary("mpv")
      System.loadLibrary("player")
    }

    private val sessions = ConcurrentHashMap<Long, MpvPlayer>()

    // Not real suspend functions: every native call below runs directly,
    // blocking, on whatever thread invokes it, with no internal dispatcher
    // hop. That's deliberate -- this class's sole caller
    // (android/app/.../mpv/MpvPlayerCore.kt) confines all of these calls to
    // its own single-thread-at-a-time dispatcher
    // (Dispatchers.IO.limitedParallelism(1)) precisely to get strict
    // single-thread ordering for its own unsynchronized fields; an internal
    // withContext(Dispatchers.IO) here would hand execution to a *different*,
    // multi-threaded pool mid-call, silently freeing up that single-thread
    // slot for another queued call to run concurrently and breaking that
    // ordering guarantee.
    suspend fun create(
      context: Context,
      configure: MpvPlayerConfig.() -> Unit = {}
    ): MpvPlayer {
      val player = MpvPlayer(nativeCreate(context.applicationContext))
      sessions[player.session] = player
      try {
        MpvPlayerConfig(player.session).apply(configure)
        val result = nativeInit(player.session)
        if (result < 0) throw MpvException("Failed to initialize mpv: error $result")
        coroutineContext.ensureActive()
        return player
      } catch (e: Throwable) {
        player.close()
        throw e
      }
    }

    // JNI callbacks, called from the native event thread. Each names the
    // session it originated from; only the wrapper published for that
    // session may receive it.

    private fun target(session: Long): MpvPlayer? = sessions[session]

    @JvmStatic
    fun onPropertyChanged(session: Long, name: String, sourceId: Long, hasSourceId: Boolean) {
      target(session)?.rawPropertyChanges?.trySend(
        PropertyChange.None(name, sourceId.takeIf { hasSourceId })
      )
    }

    @JvmStatic
    fun onPropertyChanged(session: Long, name: String, value: Boolean, sourceId: Long, hasSourceId: Boolean) {
      target(session)?.rawPropertyChanges?.trySend(
        PropertyChange.Flag(name, value, sourceId.takeIf { hasSourceId })
      )
    }

    @JvmStatic
    fun onPropertyChanged(session: Long, name: String, value: Long, sourceId: Long, hasSourceId: Boolean) {
      target(session)?.rawPropertyChanges?.trySend(
        PropertyChange.Int64(name, value, sourceId.takeIf { hasSourceId })
      )
    }

    @JvmStatic
    fun onPropertyChanged(session: Long, name: String, value: Double, sourceId: Long, hasSourceId: Boolean) {
      target(session)?.rawPropertyChanges?.trySend(
        PropertyChange.Double(name, value, sourceId.takeIf { hasSourceId })
      )
    }

    @JvmStatic
    fun onPropertyChanged(session: Long, name: String, value: String, sourceId: Long, hasSourceId: Boolean) {
      target(session)?.rawPropertyChanges?.trySend(
        PropertyChange.Str(name, value, sourceId.takeIf { hasSourceId })
      )
    }

    @JvmStatic
    fun onEvent(
      session: Long,
      eventId: Int,
      sourceId: Long,
      hasSourceId: Boolean,
      positionSeconds: Double,
      hasPositionSeconds: Boolean
    ) {
      val event = MpvEvent.fromId(
        eventId,
        sourceId.takeIf { hasSourceId },
        positionSeconds.takeIf { hasPositionSeconds && it.isFinite() }
      ) ?: return
      target(session)?.rawEvents?.trySend(event)
    }

    @JvmStatic
    fun onEndFile(
      session: Long,
      reason: Int,
      sourceId: Long,
      hasSourceId: Boolean,
      error: Int,
      errorMessage: String?
    ) {
      target(session)?.rawEvents?.trySend(
        MpvEvent.EndFile(
          EndFileReason.fromId(reason),
          sourceId.takeIf { hasSourceId },
          MpvError.fromCode(error),
          errorMessage?.takeIf { it.isNotBlank() }
        )
      )
    }

    @JvmStatic
    fun onLogMessage(session: Long, prefix: String, level: Int, text: String) {
      val logLevel = LogLevel.fromNative(level) ?: return
      target(session)?.rawEvents?.trySend(MpvEvent.LogMessage(prefix, logLevel, text.trimEnd()))
    }

    @JvmStatic
    fun onHook(session: Long, name: String, id: Long) {
      val player = target(session)
      if (player == null || player.closed || !player.rawHooks.trySend(Hook(name, id)).isSuccess) {
        // Nobody will answer: release mpv rather than leave it waiting. The
        // native side drops this if the session has since been retired.
        nativeHookContinue(session, id)
      }
    }

    // JNI native declarations, private to avoid internal name mangling.
    // Every entry after nativeCreate names the session it acts for; the
    // native side refuses a retired one.

    /** Publishes a new native session and returns its identity. */
    @JvmStatic private external fun nativeCreate(appctx: Context): Long

    /** 0 on success, otherwise a negative mpv error. */
    @JvmStatic private external fun nativeInit(session: Long): Int

    /** Returns once the event thread stopped; mpv terminates on a native thread of its own. */
    @JvmStatic private external fun nativeDestroy(session: Long)

    /** Negative mpv error, the playlist entry id a `loadfile` created, or 0 when the command returned none. */
    @JvmStatic private external fun nativeCommand(session: Long, cmd: Array<out String>): Long

    @JvmStatic private external fun nativeHookAdd(session: Long, name: String, priority: Int): Int

    @JvmStatic private external fun nativeHookContinue(session: Long, id: Long)

    @JvmStatic private external fun nativeSetOptionString(session: Long, name: String, value: String): Int

    @JvmStatic private external fun nativeAttachSurface(session: Long, surface: Surface): Int

    @JvmStatic private external fun nativeDetachSurface(session: Long)

    @JvmStatic private external fun nativeAttachOsdSurface(session: Long, surface: Surface): Int

    @JvmStatic private external fun nativeDetachOsdSurface(session: Long)

    @JvmStatic private external fun nativeGetPropertyInt(session: Long, name: String): Int?

    @JvmStatic private external fun nativeGetPropertyDouble(session: Long, name: String): Double?

    @JvmStatic private external fun nativeGetPropertyBoolean(session: Long, name: String): Boolean?

    @JvmStatic private external fun nativeGetPropertyString(session: Long, name: String): String?

    @JvmStatic private external fun nativeSetPropertyInt(session: Long, name: String, value: Int): Int

    @JvmStatic private external fun nativeSetPropertyDouble(session: Long, name: String, value: Double): Int

    @JvmStatic private external fun nativeSetPropertyBoolean(session: Long, name: String, value: Boolean): Int

    @JvmStatic private external fun nativeSetPropertyString(session: Long, name: String, value: String): Int

    @JvmStatic private external fun nativeObserveProperty(session: Long, name: String, format: Int): Int

    internal fun setOptionString(session: Long, name: String, value: String): Int =
      nativeSetOptionString(session, name, value)
  }

  // The native event thread hands everything to unbounded channels: trySend
  // on them cannot fail (until close) and cannot block mpv's event loop. A
  // pump per stream re-emits into the SharedFlow, whose SUSPEND overflow
  // parks the pump - not the native thread - while a collector catches up.
  //
  // Log lines share the event channel rather than having their own: event.cpp
  // forwards the lines explaining a failure before its end-file, and separate
  // channels, pumps and collectors could still deliver the end-file first.
  private val rawEvents = Channel<MpvEvent>(Channel.UNLIMITED)
  private val rawHooks = Channel<Hook>(Channel.UNLIMITED)
  private val rawPropertyChanges = Channel<PropertyChange>(Channel.UNLIMITED)

  private val events = MutableSharedFlow<MpvEvent>(extraBufferCapacity = 64)
  private val propertyChanges = MutableSharedFlow<PropertyChange>(extraBufferCapacity = 64)

  private val pumpScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

  private class Hook(val name: String, val id: Long)

  /**
   * Handler for hooks registered with [addHook]. mpv holds playback until the
   * handler returns; a handler that throws or overruns [HOOK_TIMEOUT_MS] is
   * abandoned and playback continues. Unset, hooks continue immediately.
   */
  @Volatile var hookHandler: (suspend (name: String) -> Unit)? = null

  init {
    pumpScope.launch { for (e in rawEvents) events.emit(e) }
    pumpScope.launch {
      for (hook in rawHooks) {
        try {
          val handler = if (closed) null else hookHandler
          if (handler != null) {
            withTimeoutOrNull(HOOK_TIMEOUT_MS) { handler(hook.name) }
              ?: android.util.Log.w("MpvPlayer", "Hook ${hook.name} handler overran; continuing playback")
          }
        } catch (e: Exception) {
          android.util.Log.w("MpvPlayer", "Hook ${hook.name} handler failed; continuing playback", e)
        } finally {
          // Validated natively against this session, atomically with its
          // retirement: a continuation that lost the race is dropped, never
          // delivered to a successor's core.
          nativeHookContinue(session, hook.id)
        }
      }
    }
    pumpScope.launch { for (c in rawPropertyChanges) propertyChanges.emit(c) }
  }

  /** Lifecycle events and log lines, in the order mpv produced them. */
  val eventFlow: SharedFlow<MpvEvent> = events.asSharedFlow()
  val propertyFlow: SharedFlow<PropertyChange> = propertyChanges.asSharedFlow()

  // Commands

  /**
   * Runs an mpv command. `loadfile` returns the id of the playlist entry it
   * created (the `sourceId` its start-file / file-loaded / end-file events
   * carry); every other command returns null. A command mpv rejects throws
   * [MpvException].
   */
  suspend fun command(vararg args: String): Long? {
    checkNotClosed()
    val status = nativeCommand(session, args)
    if (status < 0) throw MpvException("Command '${args.firstOrNull() ?: ""}' failed: error $status")
    return if (status > 0) status else null
  }

  /**
   * Registers an mpv hook (e.g. `on_preloaded`), answered by [hookHandler].
   * Call it before loading the file the hook should apply to.
   */
  fun addHook(name: String, priority: Int = 0) {
    checkNotClosed()
    val result = nativeHookAdd(session, name, priority)
    if (result < 0) throw MpvException("Failed to add hook '$name': error $result")
  }

  // Surface - not suspend, called from SurfaceHolder.Callback

  fun attachSurface(surface: Surface) {
    checkNotClosed()
    val result = nativeAttachSurface(session, surface)
    if (result < 0) throw MpvException("Failed to attach surface: error $result")
  }

  fun detachSurface() {
    checkNotClosed()
    nativeDetachSurface(session)
  }

  /** OSD/subtitle plane for `vo=mediacodec`; attach before selecting the VO. */
  fun attachOsdSurface(surface: Surface) {
    checkNotClosed()
    val result = nativeAttachOsdSurface(session, surface)
    if (result < 0) throw MpvException("Failed to attach OSD surface: error $result")
  }

  fun detachOsdSurface() {
    checkNotClosed()
    nativeDetachOsdSurface(session)
  }

  // Property getters

  suspend fun getInt(name: String): Int? {
    checkNotClosed()
    return nativeGetPropertyInt(session, name)
  }

  suspend fun getDouble(name: String): Double? {
    checkNotClosed()
    return nativeGetPropertyDouble(session, name)
  }

  suspend fun getFlag(name: String): Boolean? {
    checkNotClosed()
    return nativeGetPropertyBoolean(session, name)
  }

  suspend fun getString(name: String): String? {
    checkNotClosed()
    return nativeGetPropertyString(session, name)
  }

  // Property setters. A write mpv rejects throws, like every sibling native
  // call, rather than reporting success for a value mpv refused.

  suspend fun setProperty(name: String, value: Int) {
    checkNotClosed()
    val result = nativeSetPropertyInt(session, name, value)
    if (result < 0) throw MpvException("Failed to set property '$name': error $result")
  }

  suspend fun setProperty(name: String, value: Double) {
    checkNotClosed()
    val result = nativeSetPropertyDouble(session, name, value)
    if (result < 0) throw MpvException("Failed to set property '$name': error $result")
  }

  suspend fun setProperty(name: String, value: Boolean) {
    checkNotClosed()
    val result = nativeSetPropertyBoolean(session, name, value)
    if (result < 0) throw MpvException("Failed to set property '$name': error $result")
  }

  suspend fun setProperty(name: String, value: String) {
    checkNotClosed()
    val result = nativeSetPropertyString(session, name, value)
    if (result < 0) throw MpvException("Failed to set property '$name': error $result")
  }

  // Property observation. Also throws on refusal: a property mpv does not
  // know reports success while nothing will ever be delivered for it.

  suspend fun observeProperty(name: String, format: PropertyFormat) {
    checkNotClosed()
    val result = nativeObserveProperty(session, name, format.nativeValue)
    if (result < 0) throw MpvException("Failed to observe property '$name': error $result")
  }

  // Lifecycle

  private val closeLock = Any()

  @Volatile
  private var closed = false

  /**
   * Retires the native session: once this returns no callback reaches this
   * wrapper and no call names its session again. mpv's own termination, which
   * can block for a long time on a wedged decoder, continues on a native
   * thread and holds up neither the caller nor the next session.
   */
  override fun close() {
    synchronized(closeLock) {
      if (closed) return
      closed = true
      hookHandler = null
      sessions.remove(session, this)
    }
    // The event thread joined inside nativeDestroy is the only producer, and
    // a trySend on a closed channel simply fails. A hook already queued still
    // answers through nativeHookContinue, which the native side drops once
    // the session is retired; mpv releases held hooks as it terminates.
    rawEvents.close()
    rawHooks.close()
    rawPropertyChanges.close()
    nativeDestroy(session)
  }

  private fun checkNotClosed() {
    check(!closed) { "MpvPlayer has been closed" }
  }
}
