import 'dart:async';

import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/favorites_service.dart';
import 'package:m3u_tv/shared/app_button.dart';
import 'package:material_ui/material_ui.dart';

/// Adds or removes [id] from [service] on a detail page, so a movie or
/// series can be favorited without the long-press its browse card needs
/// (which a remote or mouse has no obvious way to give).
class FavoriteButton extends StatefulWidget {
  const FavoriteButton({super.key, required this.service, required this.id});

  final FavoritesService service;
  final int id;

  @override
  State<FavoriteButton> createState() => _FavoriteButtonState();
}

class _FavoriteButtonState extends State<FavoriteButton> {
  bool _isFavorite = false;

  @override
  void initState() {
    super.initState();
    widget.service.addListener(_load);
    _load();
  }

  @override
  void didUpdateWidget(FavoriteButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.service, widget.service) &&
        oldWidget.id == widget.id) {
      return;
    }
    oldWidget.service.removeListener(_load);
    widget.service.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    widget.service.removeListener(_load);
    super.dispose();
  }

  void _load() {
    final id = widget.id;
    unawaited(
      widget.service.isFavorite(id).then((isFavorite) {
        if (mounted && id == widget.id && isFavorite != _isFavorite) {
          setState(() => _isFavorite = isFavorite);
        }
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AppButton(
      icon: _isFavorite ? Icons.star : Icons.star_border,
      label: _isFavorite ? l.liveTvRemoveFavorite : l.liveTvFavorite,
      autoScroll: false,
      onPressed: () => unawaited(widget.service.toggle(widget.id)),
    );
  }
}
