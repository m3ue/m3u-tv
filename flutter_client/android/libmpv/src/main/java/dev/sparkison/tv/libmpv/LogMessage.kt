package dev.sparkison.tv.libmpv

data class LogMessage(
  val prefix: String,
  val level: LogLevel,
  val text: String
)
