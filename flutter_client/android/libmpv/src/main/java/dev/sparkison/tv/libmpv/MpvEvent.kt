package dev.sparkison.tv.libmpv

sealed interface MpvEvent {
  /** The playlist entry the event belongs to (what `loadfile` returned), when mpv names one. */
  val sourceId: Long?

  data class Shutdown(override val sourceId: Long?) : MpvEvent
  data class StartFile(override val sourceId: Long?) : MpvEvent
  data class EndFile(
    val reason: EndFileReason?,
    override val sourceId: Long?,
    /** mpv_error code when [reason] is [EndFileReason.Error]; null otherwise. */
    val error: MpvError? = null,
    /** `mpv_error_string` for that code; null unless [reason] is [EndFileReason.Error]. */
    val errorMessage: String? = null
  ) : MpvEvent
  data class FileLoaded(override val sourceId: Long?) : MpvEvent
  data class VideoReconfig(override val sourceId: Long?) : MpvEvent
  data class AudioReconfig(override val sourceId: Long?) : MpvEvent
  data class Seek(override val sourceId: Long?) : MpvEvent
  data class PlaybackRestart(
    override val sourceId: Long?,
    val positionSeconds: Double?
  ) : MpvEvent
  data class QueueOverflow(override val sourceId: Long?) : MpvEvent
  data class Other(val eventId: Int, override val sourceId: Long?) : MpvEvent

  /**
   * One mpv log line. It travels in the same ordered stream as the lifecycle
   * events, so a line never reaches a collector after the end-file it
   * explains. mpv attributes log lines to no playlist entry.
   */
  data class LogMessage(
    val prefix: String,
    val level: LogLevel,
    val text: String
  ) : MpvEvent {
    override val sourceId: Long? get() = null
  }

  companion object {
    internal fun fromId(
      id: Int,
      sourceId: Long?,
      positionSeconds: Double?
    ): MpvEvent? = when (id) {
      1 -> Shutdown(sourceId)
      6 -> StartFile(sourceId)
      8 -> FileLoaded(sourceId)
      17 -> VideoReconfig(sourceId)
      18 -> AudioReconfig(sourceId)
      20 -> Seek(sourceId)
      21 -> PlaybackRestart(sourceId, positionSeconds)
      24 -> QueueOverflow(sourceId)
      // 0=NONE, 2=LOG_MESSAGE, 7=END_FILE, 22=PROPERTY_CHANGE, 25=HOOK arrive via their own JNI paths
      0, 2, 7, 22, 25 -> null
      else -> Other(id, sourceId)
    }
  }
}
