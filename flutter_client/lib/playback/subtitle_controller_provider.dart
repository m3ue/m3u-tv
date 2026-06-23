import 'package:media_kit_video/media_kit_video.dart' as mkv;

/// Implemented by adapters that expose a [mkv.VideoController] for use with
/// [mkv.SubtitleView], which renders text subtitles as a Flutter overlay
/// without interfering with the native video rendering pipeline.
abstract class SubtitleControllerProvider {
  mkv.VideoController get subtitleController;
}
