import 'dart:async';

import 'package:dpad/dpad.dart';
import 'package:intl/intl.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/epg_service.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';
import 'package:material_ui/material_ui.dart';

/// Presents [channel]'s replayable catchup programs (most-recent first) as a
/// D-pad-navigable list, mirroring the row styling of the Live TV long-press
/// context menu that opens this dialog.
///
/// Live-updates as [epgService] notifies, so newly merged history (e.g. the
/// catchup-window fetch kicked off via [epgLoad]) appears without a reopen.
/// Resolves with the selected [EpgProgram], or null if the user cancels.
Future<EpgProgram?> showCatchupShowsDialog(
  BuildContext context, {
  required Channel channel,
  required EpgService epgService,
  Future<void>? epgLoad,
}) {
  return showDialog<EpgProgram>(
    context: context,
    builder: (dialogContext) => SimpleDialog(
      title: Row(
        children: [
          const Icon(Icons.video_library, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              channel.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      children: [
        _CatchupShowsList(
          channel: channel,
          epgService: epgService,
          epgLoad: epgLoad,
        ),
      ],
    ),
  );
}

class _CatchupShowsList extends StatefulWidget {
  const _CatchupShowsList({
    required this.channel,
    required this.epgService,
    required this.epgLoad,
  });

  final Channel channel;
  final EpgService epgService;
  final Future<void>? epgLoad;

  @override
  State<_CatchupShowsList> createState() => _CatchupShowsListState();
}

class _CatchupShowsListState extends State<_CatchupShowsList> {
  final _scrollController = ScrollController();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final load = widget.epgLoad;
    if (load != null) {
      unawaited(
        load
            .whenComplete(() {
              if (!mounted) return;
              setState(() => _loading = false);
            })
            // The fetch swallows its own errors, but guard anyway so a future
            // contract change can't surface here as an unhandled async error.
            .catchError((Object _) {}),
      );
    } else {
      _loading = false;
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return ListenableBuilder(
      listenable: widget.epgService,
      builder: (context, _) {
        final programs = widget.epgService.catchupProgramsForChannel(
          widget.channel,
        );
        if (_loading && programs.isEmpty) {
          return DpadRegion(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          l10n.catchupShowsLoading,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _CatchupShowRow(
                    icon: Icons.close,
                    label: l10n.cancel,
                    autofocus: true,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          );
        }

        if (programs.isEmpty) {
          return DpadRegion(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.catchupShowsEmpty,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  _CatchupShowRow(
                    icon: Icons.close,
                    label: l10n.cancel,
                    autofocus: true,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          );
        }

        final maxHeight = MediaQuery.sizeOf(context).height * 0.55;
        final languageTag = Localizations.localeOf(context).toLanguageTag();
        final startFormat = DateFormat.MMMd(languageTag).add_jm();
        final endFormat = DateFormat.jm(languageTag);
        String times(EpgProgram p) =>
            '${startFormat.format(p.start.toLocal())} '
            '- ${endFormat.format(p.end.toLocal())}';

        return DpadRegion(
          child: SizedBox(
            width: double.maxFinite,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: Scrollbar(
                controller: _scrollController,
                thumbVisibility: true,
                child: ListView.builder(
                  controller: _scrollController,
                  shrinkWrap: true,
                  itemCount: programs.length + 1,
                  itemBuilder: (context, index) {
                    if (index == programs.length) {
                      return _CatchupShowRow(
                        icon: Icons.close,
                        label: l10n.cancel,
                        onTap: () => Navigator.of(context).pop(),
                      );
                    }
                    final program = programs[index];
                    final hasTitle = program.title.isNotEmpty;
                    final label = hasTitle
                        ? program.title
                        : program.displayTitle;
                    final subtitle = hasTitle && program.subtitle != null
                        ? '${program.subtitle} · ${times(program)}'
                        : times(program);
                    return _CatchupShowRow(
                      icon: Icons.play_circle_outline,
                      label: label,
                      subtitle: subtitle,
                      autofocus: index == 0,
                      onTap: () => Navigator.of(context).pop(program),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CatchupShowRow extends StatelessWidget {
  const _CatchupShowRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.autofocus = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? subtitle;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return DpadInkWell(
      autofocus: autofocus,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 24),
        child: Row(
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: subtitle != null
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          subtitle!,
                          style: Theme.of(context).textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    )
                  : Text(label),
            ),
          ],
        ),
      ),
    );
  }
}
