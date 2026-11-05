import 'package:dpad/dpad.dart';
import 'package:m3u_tv/features/sports/sports_fixture_card.dart';
import 'package:m3u_tv/features/sports/sports_fixture_details_screen.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/sports_channel_lookup.dart';
import 'package:m3u_tv/services/sports_models.dart';
import 'package:m3u_tv/shared/app_menu_dialog.dart';
import 'package:m3u_tv/shared/app_modal.dart';
import 'package:material_ui/material_ui.dart';

/// Whether a game can still be watched (on now or yet to start).
bool isSportsFixtureWatchable(SportsFixture fixture) =>
    fixture.state == SportsFixtureState.live ||
    fixture.state == SportsFixtureState.scheduled;

/// What pressing a game does: play it when it can be watched, else show its
/// details, the next best thing for a finished game or one no channel carries.
/// Shared by the Sports screen and Home's Sports row.
Future<void> openSportsFixture(
  BuildContext context, {
  required SportsFixture fixture,
  required List<SportsChannelMatch> matches,
  required ValueChanged<Channel> onChannelSelect,
  bool Function()? onBack,
}) {
  if (isSportsFixtureWatchable(fixture) && matches.isNotEmpty) {
    return playSportsFixture(
      context,
      fixture: fixture,
      matches: matches,
      onChannelSelect: onChannelSelect,
    );
  }
  return openSportsFixtureDetails(
    context,
    fixture: fixture,
    matches: matches,
    onChannelSelect: onChannelSelect,
    onBack: onBack,
  );
}

/// Plays [fixture]: straight away on its only channel, else on the one the
/// viewer picks from [matches].
Future<void> playSportsFixture(
  BuildContext context, {
  required SportsFixture fixture,
  required List<SportsChannelMatch> matches,
  required ValueChanged<Channel> onChannelSelect,
}) async {
  final match = matches.length == 1
      ? matches.single
      : await pickSportsChannel(context, fixture, matches);
  debugPrint(
    '[Sports] open ${fixture.league.id}:${fixture.id}: '
    '${matches.length} channel(s), playing ${match?.channel.id}',
  );
  if (match != null && context.mounted) onChannelSelect(match.channel);
}

/// Asks which of [matches] to use for [fixture]; null when cancelled.
Future<SportsChannelMatch?> pickSportsChannel(
  BuildContext context,
  SportsFixture fixture,
  List<SportsChannelMatch> matches,
) {
  final l10n = AppLocalizations.of(context);
  return showAppDialog<SportsChannelMatch>(
    context: context,
    builder: (dialogContext) => AppMenuDialog(
      title: Text(
        sportsFixtureTitle(l10n, fixture),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      children: [
        DpadRegion(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < matches.length; i++)
                AppMenuOption(
                  icon: Icons.live_tv,
                  label: matches[i].channel.name,
                  subtitle: matches[i].programTitle ?? l10n.sportsEventChannel,
                  autofocus: i == 0,
                  onTap: () => Navigator.of(dialogContext).pop(matches[i]),
                ),
              AppMenuOption(
                icon: Icons.close,
                label: l10n.cancel,
                onTap: () => Navigator.of(dialogContext).pop(),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
