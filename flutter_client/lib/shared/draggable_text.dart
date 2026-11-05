import 'package:material_ui/material_ui.dart';

/// One line of text that can be dragged sideways to read what doesn't fit,
/// for a label too narrow to show it all. Text that fits doesn't claim the
/// drag, so it still reaches whatever scrolls behind it.
class DraggableText extends StatelessWidget {
  const DraggableText(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Text(text, style: style, maxLines: 1, softWrap: false),
      ),
    );
  }
}
