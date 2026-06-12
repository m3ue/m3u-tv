import 'package:flutter/material.dart';

import 'package:m3u_tv/services/domain_models.dart';

/// Widget for switching between viewers in an m3u-editor backend.
///
/// Shows the active viewer with an admin badge if applicable,
/// and a list of available viewers to switch to.
class ViewerSelector extends StatelessWidget {
  const ViewerSelector({
    super.key,
    required this.viewers,
    required this.activeViewer,
    required this.onSwitch,
  });

  /// All available viewers from the backend.
  final List<Viewer> viewers;

  /// The currently active viewer.
  final Viewer activeViewer;

  /// Called when the user selects a different viewer.
  final void Function(Viewer viewer) onSwitch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Active Viewer', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        _ViewerCard(viewer: activeViewer, isActive: true),
        if (viewers.length > 1) ...[
          const SizedBox(height: 16),
          Text('Switch Viewer', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          ...viewers
              .where((v) => v.ulid != activeViewer.ulid)
              .map((viewer) => _ViewerTile(
                    viewer: viewer,
                    onTap: () => onSwitch(viewer),
                  )),
        ],
      ],
    );
  }
}

class _ViewerCard extends StatelessWidget {
  const _ViewerCard({required this.viewer, required this.isActive});

  final Viewer viewer;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: colorScheme.primary,
              child: Text(
                viewer.name.isNotEmpty ? viewer.name[0].toUpperCase() : '?',
                style: TextStyle(color: colorScheme.onPrimary),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(viewer.name, style: theme.textTheme.titleMedium),
                  if (viewer.isAdmin)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Admin',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.primary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ViewerTile extends StatelessWidget {
  const _ViewerTile({required this.viewer, required this.onTap});

  final Viewer viewer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      leading: CircleAvatar(
        child: Text(viewer.name.isNotEmpty ? viewer.name[0].toUpperCase() : '?'),
      ),
      title: Text(viewer.name),
      trailing: viewer.isAdmin
          ? Text('Admin', style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.primary,
            ))
          : null,
      onTap: onTap,
    );
  }
}