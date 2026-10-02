import 'dart:async';

import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:m3u_tv/features/settings/settings_ui.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/app_log_buffer.dart';
import 'package:m3u_tv/shared/app_button.dart';

/// Upload cap; matches m3u-editor's `TvDeviceLog::MAX_BYTES`. The export
/// keeps the device header and the newest lines that fit.
const int kDiagnosticsUploadMaxBytes = 1024 * 1024;

/// Settings > General > Logs & Diagnostics: a device header (build, platform,
/// renderer, performance tier, memory) above this session's captured log
/// lines, with an Upload that stores the report against this device in
/// m3u-editor's Registered Devices list. Modeled on Plezy's logs screen.
class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({
    super.key,
    required this.loadHeader,
    this.onUpload,
    this.buffer,
  });

  /// Builds the device header fresh (memory figures change over time).
  final Future<String> Function() loadHeader;

  /// Uploads a report and returns the stored upload's id. Null when not
  /// connected to a server, which disables Upload.
  final Future<int> Function(String report)? onUpload;

  /// Defaults to [AppLogBuffer.instance].
  final AppLogBuffer? buffer;

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  final _uploadFocusNode = FocusNode(debugLabel: 'diagnostics-upload');
  final _paneFocusNode = FocusNode(debugLabel: 'diagnostics-pane');
  final _scrollController = ScrollController();

  String? _header;
  List<AppLogEntry> _entries = const [];
  bool _uploading = false;

  AppLogBuffer get _buffer => widget.buffer ?? AppLogBuffer.instance;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  @override
  void dispose() {
    _uploadFocusNode.dispose();
    _paneFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final header = await widget.loadHeader();
    if (!mounted) return;
    setState(() {
      _header = header;
      _entries = _buffer.entries.reversed.toList(growable: false);
    });
  }

  void _clear() {
    _buffer.clear();
    setState(() => _entries = const []);
  }

  Future<void> _upload() async {
    final onUpload = widget.onUpload;
    if (onUpload == null || _uploading) return;
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _uploading = true);
    try {
      await _refresh();
      final report = _buffer.export(
        header: _header ?? '',
        maxBytes: kDiagnosticsUploadMaxBytes,
      );
      final id = await onUpload(report);
      messenger.showSnackBar(
        SnackBar(content: Text(l.diagnosticsUploaded(id))),
      );
    } on Object catch (error) {
      debugPrint('[Diagnostics] upload failed: $error');
      messenger.showSnackBar(
        SnackBar(content: Text(l.diagnosticsUploadFailed('$error'))),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  // Every direction is consumed so a press never falls through to spatial
  // traversal (see the release notes pane, which this mirrors).
  bool _onDirection(TraversalDirection direction) {
    switch (direction) {
      case TraversalDirection.up:
        if (!_scrollController.hasClients ||
            _scrollController.position.pixels <=
                _scrollController.position.minScrollExtent + 0.5) {
          _uploadFocusNode.requestFocus();
        } else {
          _scrollBy(-_step);
        }
      case TraversalDirection.down:
        _scrollBy(_step);
      case TraversalDirection.left:
      case TraversalDirection.right:
        break;
    }
    return true;
  }

  double get _step =>
      (_scrollController.position.viewportDimension * 0.4).clamp(120.0, 400.0);

  void _scrollBy(double delta) {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final target = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((target - position.pixels).abs() < 0.5) return;
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final mono = theme.textTheme.bodySmall?.copyWith(
      fontFamily: 'monospace',
      height: 1.4,
    );
    final canUpload = widget.onUpload != null;

    // No outer padding: the settings sub-page scaffold already insets every
    // page by 24, so the buttons and cards line up with the other pages.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            AppButton(
              label: _uploading ? l.diagnosticsUploading : l.diagnosticsUpload,
              icon: Icons.cloud_upload_outlined,
              variant: AppButtonVariant.primary,
              focusNode: _uploadFocusNode,
              autofocus: true,
              loading: _uploading,
              onPressed: canUpload ? () => unawaited(_upload()) : null,
            ),
            AppButton(
              label: l.diagnosticsRefresh,
              icon: Icons.refresh,
              onPressed: () => unawaited(_refresh()),
            ),
            AppButton(
              label: l.diagnosticsClear,
              icon: Icons.delete_outline,
              onPressed: _clear,
            ),
            if (!canUpload)
              Text(
                l.diagnosticsNotConnected,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        // The first section header carries its own top spacing.
        Expanded(
          child: DpadFocusable(
            focusNode: _paneFocusNode,
            autoScroll: false,
            tapToSelect: false,
            onDirection: _onDirection,
            builder: (context, state, child) => Scrollbar(
              controller: _scrollController,
              thumbVisibility: state.focused,
              child: child,
            ),
            child: CustomScrollView(
              controller: _scrollController,
              slivers: [
                SliverToBoxAdapter(
                  child: SettingsSectionHeader(l.diagnosticsDeviceHeading),
                ),
                SliverToBoxAdapter(
                  child: SettingsCard(
                    child: SizedBox(
                      width: double.infinity,
                      child: Text(_header ?? '', style: mono),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: SettingsSectionHeader(
                    l.diagnosticsLogsHeading(_entries.length),
                  ),
                ),
                if (_entries.isEmpty)
                  SliverToBoxAdapter(
                    child: SettingsCard(
                      child: Text(
                        l.diagnosticsNoLogs,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  )
                else
                  // The same card as [SettingsCard] (which the empty state
                  // uses), built as slivers so the list stays lazy.
                  DecoratedSliver(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(
                        kSettingsGroupRadius,
                      ),
                    ),
                    sliver: SliverPadding(
                      padding: const EdgeInsets.all(16),
                      // Newest first: what led up to the problem is on top.
                      sliver: SliverList.builder(
                        itemCount: _entries.length,
                        itemBuilder: (context, index) {
                          final entry = _entries[index];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text(
                              entry.format(),
                              style: entry.level == AppLogLevel.error
                                  ? mono?.copyWith(
                                      color: theme.colorScheme.error,
                                    )
                                  : mono,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
