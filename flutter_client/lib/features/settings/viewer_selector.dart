import 'package:flutter/material.dart';

import 'package:m3u_tv/services/domain_models.dart';

/// Widget for switching between viewers and creating new ones.
///
/// Shows the active viewer, a list of other viewers to switch to, and
/// a create-viewer form when [onCreateViewer] is provided.
class ViewerSelector extends StatefulWidget {
  const ViewerSelector({
    super.key,
    required this.viewers,
    required this.activeViewer,
    required this.onSwitch,
    this.onCreateViewer,
  });

  final List<Viewer> viewers;
  final Viewer activeViewer;
  final void Function(Viewer viewer) onSwitch;

  /// If non-null, a "Create Viewer" form is shown. The callback receives the
  /// name and should return the created [Viewer] or null on failure.
  final Future<Viewer?> Function(String name)? onCreateViewer;

  @override
  State<ViewerSelector> createState() => _ViewerSelectorState();
}

class _ViewerSelectorState extends State<ViewerSelector> {
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
      _nameController.clear();
    } else {
      setState(
        () => _createError = 'Failed to create viewer. Please try again.',
      );
    }
    setState(() => _isCreating = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final others = widget.viewers
        .where((v) => v.ulid != widget.activeViewer.ulid)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Active Viewer', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        _ViewerCard(viewer: widget.activeViewer),
        if (others.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Switch Viewer', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          ...others.map(
            (viewer) => _ViewerTile(
              viewer: viewer,
              onTap: () => widget.onSwitch(viewer),
            ),
          ),
        ],
        if (widget.onCreateViewer != null) ...[
          const SizedBox(height: 24),
          Text('Create New Viewer', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    hintText: 'Viewer name',
                    errorText: _createError,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _handleCreate(),
                  enabled: !_isCreating,
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _isCreating ? null : _handleCreate,
                child: _isCreating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Create'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _ViewerCard extends StatelessWidget {
  const _ViewerCard({required this.viewer});

  final Viewer viewer;

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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
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
        child: Text(
          viewer.name.isNotEmpty ? viewer.name[0].toUpperCase() : '?',
        ),
      ),
      title: Text(viewer.name),
      trailing: viewer.isAdmin
          ? Text(
              'Admin',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            )
          : null,
      onTap: onTap,
    );
  }
}
