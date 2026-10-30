import 'dart:async';

import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/shared/app_button.dart';
import 'package:m3u_tv/shared/image_quality_scope.dart';

// ---------------------------------------------------------------------------
// Viewer management dialog
// ---------------------------------------------------------------------------

class ViewerManagementDialog extends StatefulWidget {
  const ViewerManagementDialog({
    super.key,
    required this.viewers,
    required this.activeViewer,
    required this.onSwitch,
    this.onCreateViewer,
  });

  final List<Viewer> viewers;
  final Viewer activeViewer;
  final void Function(Viewer viewer) onSwitch;
  final Future<Viewer?> Function(String name)? onCreateViewer;

  @override
  State<ViewerManagementDialog> createState() => _ViewerManagementDialogState();
}

class _ViewerManagementDialogState extends State<ViewerManagementDialog> {
  bool _showAddForm = false;
  final _nameController = TextEditingController();
  bool _isCreating = false;
  String? _createError;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _handleCreate() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || widget.onCreateViewer == null) return;
    setState(() {
      _isCreating = true;
      _createError = null;
    });
    final viewer = await widget.onCreateViewer!(name);
    if (!mounted) return;
    if (viewer != null) {
      widget.onSwitch(viewer);
      Navigator.of(context).pop();
    } else {
      setState(() {
        _isCreating = false;
        _createError = AppLocalizations.of(context).settingsCreateViewerFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final others = widget.viewers
        .where((v) => v.ulid != widget.activeViewer.ulid)
        .toList();

    final scale = FontSizeScope.scaleOf(context);

    return Dialog(
      child: SizedBox(
        width: 520 * scale,
        child: DpadRegion(
          memoryKey: 'viewer-management',
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header row
                Row(
                  children: [
                    Text(
                      _showAddForm
                          ? AppLocalizations.of(context).settingsAddViewer
                          : AppLocalizations.of(context).settingsManageViewers,
                      style: theme.textTheme.titleLarge,
                    ),
                    const Spacer(),
                    DpadFocusable(
                      onSelect: () => Navigator.of(context).pop(),
                      effects: kStadiumFocusEffects,
                      child: IconButton(
                        icon: Icon(Icons.close, size: 24 * scale),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                if (_showAddForm) ...[
                  // ── Add viewer form ────────────────────────────────────────
                  TextField(
                    controller: _nameController,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: AppLocalizations.of(
                        context,
                      ).settingsViewerNameLabel,
                      errorText: _createError,
                      border: const OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12 * scale,
                        vertical: 16 * scale,
                      ),
                    ),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _handleCreate(),
                    enabled: !_isCreating,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      AppButton(
                        label: AppLocalizations.of(context).cancel,
                        onPressed: () => setState(() {
                          _showAddForm = false;
                          _nameController.clear();
                          _createError = null;
                        }),
                      ),
                      const SizedBox(width: 8),
                      AppButton(
                        variant: AppButtonVariant.primary,
                        label: AppLocalizations.of(context).settingsCreate,
                        loading: _isCreating,
                        onPressed: _handleCreate,
                      ),
                    ],
                  ),
                ] else ...[
                  // ── Active viewer ──────────────────────────────────────────
                  Text(
                    AppLocalizations.of(context).settingsActiveViewer,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _ViewerRow(viewer: widget.activeViewer, isActive: true),

                  // ── Switch viewer list ─────────────────────────────────────
                  if (others.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    Text(
                      AppLocalizations.of(context).settingsSwitchViewer,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: 280 * scale),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: others.length,
                        itemBuilder: (context, index) {
                          final viewer = others[index];
                          return DpadFocusable(
                            autofocus: index == 0,
                            onSelect: () {
                              widget.onSwitch(viewer);
                              Navigator.of(context).pop();
                            },
                            child: _ViewerRow(
                              viewer: viewer,
                              onTap: () {
                                widget.onSwitch(viewer);
                                Navigator.of(context).pop();
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  ],

                  // ── Add new viewer ─────────────────────────────────────────
                  if (widget.onCreateViewer != null) ...[
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    AppButton(
                      autofocus: others.isEmpty,
                      variant: AppButtonVariant.primary,
                      icon: Icons.person_add,
                      label: AppLocalizations.of(context).settingsAddViewer,
                      onPressed: () => setState(() => _showAddForm = true),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ViewerRow extends StatelessWidget {
  const _ViewerRow({required this.viewer, this.isActive = false, this.onTap});

  final Viewer viewer;
  final bool isActive;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scale = FontSizeScope.scaleOf(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: isActive ? theme.colorScheme.primary : null,
        child: Text(
          viewer.name.isNotEmpty ? viewer.name[0].toUpperCase() : '?',
          style: isActive
              ? TextStyle(color: theme.colorScheme.onPrimary)
              : null,
        ),
      ),
      title: Text(viewer.name),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (viewer.isAdmin)
            Text(
              AppLocalizations.of(context).admin,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          if (isActive) ...[
            if (viewer.isAdmin) SizedBox(width: 8 * scale),
            Icon(
              Icons.check_circle,
              size: 16 * scale,
              color: theme.colorScheme.primary,
            ),
          ],
        ],
      ),
      onTap: onTap,
    );
  }
}
