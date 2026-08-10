import 'package:flutter/material.dart';

/// Small rounded, alpha-bordered pill used for compact EPG/channel badges
/// (catchup availability, recording indicators). Wraps a small child, usually
/// an [Icon] or an [Icon] + label [Row].
class EpgIconPill extends StatelessWidget {
  const EpgIconPill({
    required this.color,
    required this.borderColor,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
    super.key,
  });

  final Color color;
  final Color borderColor;
  final EdgeInsetsGeometry padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor),
      ),
      child: child,
    );
  }
}
