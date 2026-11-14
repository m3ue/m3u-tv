import 'package:intl/intl.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';
import 'package:m3u_tv/shared/image_quality_scope.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';
import 'package:m3u_tv/shared/recording_dot.dart';
import 'package:material_ui/material_ui.dart';

/// Channel card used by the Live TV "Grid" view and the Home Live TV row:
/// logo, current-program progress bar, channel name, current program title
/// and its start/end time. Sized by its parent.
/// What a [ChannelGridTile] shows under the channel name in place of its
/// guide data: a matched show's airing in search results.
class ChannelTileProgramme {
  const ChannelTileProgramme({
    required this.title,
    required this.timeLabel,
    this.progress,
  });

  final String title;
  final String timeLabel;

  /// How far through the airing it is (0-1), for one on now. Null hides the
  /// progress bar, as for an upcoming airing.
  final double? progress;
}

class ChannelGridTile extends StatelessWidget {
  const ChannelGridTile({
    required this.channel,
    this.epg,
    this.programme,
    required this.isFavorite,
    required this.isRecording,
    required this.autofocus,
    required this.onTap,
    this.onLongPress,
    super.key,
  });

  /// Unscaled card size; callers multiply by `FontSizeScope.scaleOf`.
  static const double baseWidth = 220;
  static const double baseHeight = 160;

  final Channel channel;
  final EpgCurrentNext? epg;

  /// Shown in place of [epg]'s current programme when set.
  final ChannelTileProgramme? programme;
  final bool isFavorite;
  final bool isRecording;
  final bool autofocus;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final scale = FontSizeScope.scaleOf(context);
    final languageTag = Localizations.localeOf(context).toLanguageTag();
    final timeFormat = DateFormat.jm(languageTag);
    final current = epg?.current;
    final programmeTitle = programme?.title ?? current?.displayTitle;
    final timeLabel =
        programme?.timeLabel ??
        (current == null
            ? null
            : '${timeFormat.format(current.start.toLocal())} - '
                  '${timeFormat.format(current.end.toLocal())}');
    final progress = programme != null ? programme!.progress : epg?.progress;
    return DpadInkWell(
      autofocus: autofocus,
      onTap: onTap,
      onLongTap: onLongPress,
      color: colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: ResilientMediaImage(
                      imageUrl: channel.logoUrl,
                      fallbackIcon: Icons.tv,
                      fit: BoxFit.contain,
                      oversample: 2,
                    ),
                  ),
                  if (isFavorite)
                    Positioned(
                      top: 0,
                      left: 0,
                      child: Container(
                        padding: EdgeInsets.all(3 * scale),
                        decoration: BoxDecoration(
                          color: colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.star,
                          color: Colors.white,
                          size: 14 * scale,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            if (progress != null)
              LinearProgressIndicator(
                value: progress,
                minHeight: 3,
                backgroundColor: colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation(colorScheme.primary),
              )
            else
              const SizedBox(height: 3),
            const SizedBox(height: 6),
            Row(
              children: [
                if (isRecording) ...[
                  RecordingDot(color: colorScheme.error),
                  const SizedBox(width: 4),
                ],
                Expanded(
                  child: Text(
                    channel.name,
                    style: Theme.of(context).textTheme.labelMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (programmeTitle != null) ...[
              Text(
                programmeTitle,
                style:
                    Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                timeLabel ?? '',
                style:
                    Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ] else
              Text(
                AppLocalizations.of(context).liveTvNoProgram,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
    );
  }
}
