import 'dart:async';

import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:m3u_tv/features/multiview/multiview_controller.dart';
import 'package:m3u_tv/features/multiview/multiview_grid_math.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/navigation/app_router.dart';
import 'package:m3u_tv/navigation/content_actions.dart';
import 'package:m3u_tv/playback/playback_orchestrator.dart';
import 'package:m3u_tv/playback/player_adapter.dart';
import 'package:m3u_tv/providers/app_providers.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';
import 'package:m3u_tv/shared/gradient_border_effect.dart';

enum _LayoutMode { grid, featured, pip }

/// Up to [MultiviewController.maxStreams] live channels playing at once.
///
/// D-pad movement follows which tile is audible (all others are muted);
/// select just activates a tile as that audio source. Long-press opens a
/// per-tile menu to reorder, feature one tile larger (<=3 streams), go
/// picture-in-picture (exactly 2 streams), drop a stream from the grid, or
/// promote it to the normal full-screen player (reused unmodified via
/// [ContentActions.onOpenPlayer]) — kept off direct select since opening a
/// second native player on top of a grid tile's own was crashing/freezing
/// playback on multiple platforms.
class MultiviewScreen extends ConsumerStatefulWidget {
  const MultiviewScreen({super.key});

  @override
  ConsumerState<MultiviewScreen> createState() => _MultiviewScreenState();
}

class _MultiviewTile {
  _MultiviewTile(this.channel, this.playerId)
    : focusNode = FocusNode(debugLabel: 'multiview-$playerId');

  final Channel channel;
  final String playerId;
  final FocusNode focusNode;
  PlaybackOrchestrator? orchestrator;
  MultiviewBackend? backend;
  StreamSubscription<PlaybackState>? stateSub;
  StreamSubscription<PlaybackError>? errorSub;
  PlaybackState? state;
  bool hasError = false;

  void dispose() {
    unawaited(stateSub?.cancel());
    unawaited(errorSub?.cancel());
    focusNode.dispose();
    final orch = orchestrator;
    if (orch != null) unawaited(orch.dispose());
  }
}

class _MultiviewScreenState extends ConsumerState<MultiviewScreen> {
  final List<_MultiviewTile> _tiles = <_MultiviewTile>[];
  int _focusedIndex = 0;
  int? _reorderingIndex;
  _LayoutMode _layoutMode = _LayoutMode.grid;
  int _primaryIndex = 0;
  MultiviewPipCorner _pipCorner = MultiviewPipCorner.bottomRight;
  int _nextPlayerSeq = 0;

  @override
  void initState() {
    super.initState();
    for (final channel in ref.read(multiviewChannelsProvider)) {
      _openTile(channel);
    }
  }

  @override
  void dispose() {
    for (final tile in _tiles) {
      tile.dispose();
    }
    super.dispose();
  }

  PlaybackSource _sourceFor(Channel channel) => PlaybackSource(
    uri: channel.streamUrl,
    title: channel.name,
    isLive: true,
    headers: channel.headers,
  );

  void _openTile(Channel channel) {
    final playerId = 'multiview-${_nextPlayerSeq++}';
    final tile = _MultiviewTile(channel, playerId);
    final built = buildMultiviewTilePlayer(playerId);
    tile
      ..orchestrator = built.orchestrator
      ..backend = built.backend
      ..stateSub = built.orchestrator.onState.listen((state) {
        if (!mounted) return;
        setState(() {
          tile.state = state;
          // A state update past the initial loading/buffering steps means
          // the retry actually worked — clear the error so the tile stops
          // showing the retry affordance.
          if (state.status == PlaybackStatus.ready ||
              state.status == PlaybackStatus.playing) {
            tile.hasError = false;
          }
        });
      })
      ..errorSub = built.orchestrator.onError.listen((_) {
        // PlaybackOrchestrator gives up after one internal retry and never
        // tries again on its own — without this the tile would just stay
        // black forever with no way to recover short of leaving and
        // re-adding the channel.
        if (!mounted) return;
        setState(() => tile.hasError = true);
      });
    _tiles.add(tile);
    // Android's native player is only created inside its "load" handler, so
    // a setVolume sent before this resolves races the player into existing
    // and silently no-ops -- leaving whichever tile buffers first audible
    // regardless of focus. Reapplying focus after open() actually finishes
    // (guaranteed once its Future resolves) is the only fully reliable
    // point, so this replaces the single eager call this used to make from
    // initState() right after opening every tile.
    unawaited(
      built.orchestrator.open(_sourceFor(channel)).then((_) {
        if (!mounted) return;
        _applyAudioFocus();
      }),
    );
  }

  void _retryTile(int index) {
    final tile = _tiles[index];
    setState(() => tile.hasError = false);
    unawaited(tile.orchestrator?.open(_sourceFor(tile.channel)));
  }

  void _applyAudioFocus() {
    for (var i = 0; i < _tiles.length; i++) {
      final backend = _tiles[i].backend;
      if (backend != null) {
        unawaited(backend.setVolume(i == _focusedIndex ? 1 : 0));
      }
    }
  }

  void _handleTileFocusChange(int index, bool focused) {
    if (!focused || _focusedIndex == index) return;
    setState(() => _focusedIndex = index);
    _applyAudioFocus();
  }

  // The full-screen player is a separate native player instance opened as
  // an overlay on top of this screen -- leaving the grid's own players
  // running underneath it (even muted) is the same "two players alive for
  // one stream at once" pattern that was crashing/freezing playback when
  // direct-select used to trigger this. So every grid player is torn down
  // and this screen is popped *before* the full-screen player opens,
  // instead of layering it on top.
  Future<void> _openFullscreen(int index) async {
    final channel = _tiles[index].channel;
    final onOpenPlayer = ContentActions.of(context).onOpenPlayer;
    final navigator = Navigator.of(context);
    await Future.wait([
      for (final tile in _tiles)
        tile.orchestrator?.dispose() ?? Future<void>.value(),
    ]);
    if (!mounted) return;
    navigator.pop();
    onOpenPlayer(
      PlayerArgs(
        streamUrl: channel.streamUrl,
        title: channel.name,
        type: 'live',
        streamId: channel.id,
        epgChannelId: channel.epgChannelId ?? channel.tvgName ?? channel.name,
        headers: channel.headers,
      ),
    );
  }

  void _removeTile(int index) {
    ref.read(multiviewControllerProvider).toggle(_tiles[index].channel);
    _tiles.removeAt(index).dispose();
    if (_tiles.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      if (_focusedIndex >= _tiles.length) _focusedIndex = _tiles.length - 1;
      if (_primaryIndex >= _tiles.length) _primaryIndex = 0;
      if (_reorderingIndex == index) _reorderingIndex = null;
      final layoutStillValid = switch (_layoutMode) {
        _LayoutMode.pip => _tiles.length == 2,
        _LayoutMode.featured => _tiles.length > 1,
        _LayoutMode.grid => true,
      };
      if (!layoutStillValid) _layoutMode = _LayoutMode.grid;
    });
    _applyAudioFocus();
  }

  bool _handleDirection(int index, TraversalDirection direction) {
    if (_reorderingIndex == index) {
      if (_layoutMode == _LayoutMode.pip) {
        setState(
          () => _pipCorner = multiviewPipCornerAfter(_pipCorner, direction),
        );
        return true;
      }
      final target = multiviewSwapTarget(
        index: index,
        itemCount: _tiles.length,
        direction: direction,
      );
      if (target == null) return true;
      setState(() {
        final tile = _tiles.removeAt(index);
        _tiles.insert(target, tile);
        _reorderingIndex = target;
        if (_focusedIndex == index) _focusedIndex = target;
      });
      ref.read(multiviewControllerProvider).reorder(index, target);
      return true;
    }
    if (_layoutMode == _LayoutMode.pip && _tiles.length == 2) {
      // The floating PiP tile's bounds sit entirely inside the full-bleed
      // primary tile's bounds rather than beside it, so the d-pad's spatial
      // "nearest focusable in this direction" traversal can never resolve a
      // path onto it. With only ever two tiles in PiP, any direction press
      // unambiguously means "the other one" — so just toggle focus directly
      // instead of relying on geometry.
      _tiles[index == 0 ? 1 : 0].focusNode.requestFocus();
      return true;
    }
    return false;
  }

  Future<void> _showTileMenu(int index) async {
    final l10n = AppLocalizations.of(context);
    final count = _tiles.length;
    final action = await showDialog<_TileMenuAction>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(_tiles[index].channel.name),
        children: [
          DpadRegion(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_layoutMode == _LayoutMode.grid ||
                    (_layoutMode == _LayoutMode.pip && index != _primaryIndex))
                  _MenuOption(
                    icon: Icons.open_with,
                    label: l10n.multiviewMove,
                    autofocus: true,
                    onTap: () =>
                        Navigator.of(dialogContext).pop(_TileMenuAction.move),
                  ),
                if (count > 1 &&
                    count <= 3 &&
                    _layoutMode != _LayoutMode.featured)
                  _MenuOption(
                    icon: Icons.view_sidebar,
                    label: l10n.multiviewMakeFeatured,
                    onTap: () => Navigator.of(
                      dialogContext,
                    ).pop(_TileMenuAction.feature),
                  ),
                if (count == 2 && _layoutMode != _LayoutMode.pip)
                  _MenuOption(
                    icon: Icons.picture_in_picture_alt,
                    label: l10n.multiviewPictureInPicture,
                    onTap: () =>
                        Navigator.of(dialogContext).pop(_TileMenuAction.pip),
                  ),
                if (_layoutMode != _LayoutMode.grid)
                  _MenuOption(
                    icon: Icons.grid_view,
                    label: l10n.multiviewBackToGrid,
                    onTap: () =>
                        Navigator.of(dialogContext).pop(_TileMenuAction.grid),
                  ),
                _MenuOption(
                  icon: Icons.fullscreen,
                  label: l10n.multiviewOpenFullscreen,
                  onTap: () => Navigator.of(
                    dialogContext,
                  ).pop(_TileMenuAction.fullscreen),
                ),
                _MenuOption(
                  icon: Icons.close,
                  label: l10n.multiviewRemove,
                  onTap: () =>
                      Navigator.of(dialogContext).pop(_TileMenuAction.remove),
                ),
                _MenuOption(
                  icon: Icons.arrow_back,
                  label: l10n.cancel,
                  onTap: () => Navigator.of(dialogContext).pop(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    if (!mounted) return;
    switch (action) {
      case _TileMenuAction.move:
        setState(() => _reorderingIndex = index);
      case _TileMenuAction.feature:
        setState(() {
          _primaryIndex = index;
          _layoutMode = _LayoutMode.featured;
        });
      case _TileMenuAction.pip:
        setState(() {
          _primaryIndex = index;
          _layoutMode = _LayoutMode.pip;
        });
      case _TileMenuAction.grid:
        setState(() => _layoutMode = _LayoutMode.grid);
      case _TileMenuAction.fullscreen:
        unawaited(_openFullscreen(index));
      case _TileMenuAction.remove:
        _removeTile(index);
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFF09090b),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: Row(
                children: [
                  DpadFocusable(
                    onSelect: () => Navigator.of(context).pop(),
                    effects: const [
                      GradientBorderEffect(
                        borderRadius: BorderRadius.all(Radius.circular(50)),
                      ),
                    ],
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.arrow_back),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    l10n.multiviewTitle,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ],
              ),
            ),
            Expanded(
              child: _tiles.isEmpty
                  ? Center(child: Text(l10n.multiviewEmpty))
                  : _buildLayout(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLayout() {
    return switch (_layoutMode) {
      _LayoutMode.grid => _buildGrid(),
      _LayoutMode.featured => _buildFeatured(),
      _LayoutMode.pip => _buildPip(),
    };
  }

  // A plain Row/Column grid rather than a GridView: with at most 9 tiles,
  // this should always divide the available screen space evenly and never
  // scroll. A scrollable GridView with a fixed childAspectRatio could size
  // its content taller than the viewport, which both looks like a stray
  // "webpage scroll" when the d-pad auto-scrolls the newly-focused row into
  // view, and can crop a tile's rendered video against the viewport edge.
  Widget _buildGrid() {
    final columns = multiviewGridColumns(_tiles.length);
    final rows = (_tiles.length / columns).ceil();
    return Padding(
      padding: const EdgeInsets.all(16),
      child: DpadRegion(
        memoryKey: 'multiview/grid',
        child: Column(
          children: [
            for (var row = 0; row < rows; row++) ...[
              if (row > 0) const SizedBox(height: 12),
              Expanded(
                child: Row(
                  children: [
                    for (var col = 0; col < columns; col++) ...[
                      if (col > 0) const SizedBox(width: 12),
                      Expanded(
                        child: row * columns + col < _tiles.length
                            ? _buildTile(row * columns + col)
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFeatured() {
    final others = [
      for (var i = 0; i < _tiles.length; i++)
        if (i != _primaryIndex) i,
    ];
    return Padding(
      padding: const EdgeInsets.all(16),
      child: DpadRegion(
        memoryKey: 'multiview/featured',
        child: Row(
          children: [
            Expanded(flex: 2, child: _buildTile(_primaryIndex)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                children: [
                  for (final index in others) ...[
                    Expanded(child: _buildTile(index)),
                    if (index != others.last) const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const double _pipInset = 24;

  Widget _buildPip() {
    final other = _primaryIndex == 0 ? 1 : 0;
    final atTop =
        _pipCorner == MultiviewPipCorner.topLeft ||
        _pipCorner == MultiviewPipCorner.topRight;
    final atLeft =
        _pipCorner == MultiviewPipCorner.topLeft ||
        _pipCorner == MultiviewPipCorner.bottomLeft;
    return DpadRegion(
      memoryKey: 'multiview/pip',
      child: Stack(
        children: [
          Positioned.fill(child: _buildTile(_primaryIndex)),
          Positioned(
            top: atTop ? _pipInset : null,
            bottom: atTop ? null : _pipInset,
            left: atLeft ? _pipInset : null,
            right: atLeft ? null : _pipInset,
            width: 280,
            height: 158,
            child: _buildTile(other),
          ),
        ],
      ),
    );
  }

  Widget _buildTile(int index) {
    final tile = _tiles[index];
    final state = tile.state;
    final isFocused = _focusedIndex == index;
    final isReordering = _reorderingIndex == index;
    return DpadFocusable(
      focusNode: tile.focusNode,
      autofocus: index == 0,
      onSelect: () {
        if (isReordering) {
          setState(() => _reorderingIndex = null);
        } else if (tile.hasError) {
          _retryTile(index);
        }
        // Tapping already focuses the tile (via DpadFocusable's tapDown)
        // before this fires, which is all select should do otherwise --
        // opening a second native player on top of this tile's own was
        // what caused the "player within a player" crashes/freezes.
      },
      onLongSelect: () => unawaited(_showTileMenu(index)),
      onDirection: (direction) => _handleDirection(index, direction),
      onFocusChange: (focused) => _handleTileFocusChange(index, focused),
      effects: [
        GradientBorderEffect(
          borderRadius: const BorderRadius.all(Radius.circular(8)),
          width: isReordering ? 4 : 2.5,
        ),
      ],
      child: ClipRRect(
        borderRadius: const BorderRadius.all(Radius.circular(8)),
        child: ColoredBox(
          color: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _TileVideoSurface(
                textureId: _textureIdFor(tile),
                aspectRatio: state?.videoAspectRatio ?? 16 / 9,
              ),
              if (tile.hasError)
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: Colors.white,
                        size: 28,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        AppLocalizations.of(context).multiviewRetry,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                )
              else if (state == null ||
                  state.status == PlaybackStatus.loading ||
                  state.status == PlaybackStatus.buffering)
                const Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              Positioned(
                left: 8,
                right: 8,
                bottom: 8,
                child: Row(
                  children: [
                    Icon(
                      isFocused ? Icons.volume_up : Icons.volume_off,
                      size: 16,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        tile.channel.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          shadows: [Shadow(blurRadius: 4)],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  int? _textureIdFor(_MultiviewTile tile) {
    final backend = tile.backend;
    if (backend == null) return null;
    return backend.textureId;
  }
}

enum _TileMenuAction { move, feature, pip, grid, fullscreen, remove }

class _MenuOption extends StatelessWidget {
  const _MenuOption({
    required this.icon,
    required this.label,
    required this.onTap,
    this.autofocus = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return DpadInkWell(
      onTap: onTap,
      autofocus: autofocus,
      borderRadius: const BorderRadius.all(Radius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 12),
            Text(label),
          ],
        ),
      ),
    );
  }
}

class _TileVideoSurface extends StatelessWidget {
  const _TileVideoSurface({required this.textureId, required this.aspectRatio});

  final int? textureId;
  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    final id = textureId;
    if (id == null) return const ColoredBox(color: Colors.black);
    return Center(
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: Texture(textureId: id),
      ),
    );
  }
}
