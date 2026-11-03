import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/shared/dominant_backdrop_color.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  group('deepBackdropTone', () {
    test('default tone is a deep wash safe behind light text', () {
      final tone = HSLColor.fromColor(
        deepBackdropTone(const Color(0xFFE23B3B)), // bright red still
      );
      expect(tone.lightness, lessThanOrEqualTo(0.20));
      expect(tone.saturation, lessThanOrEqualTo(0.55));
    });

    test('vivid tone is lighter and more saturated than the default', () {
      const swatch = Color(0xFF5A2E2E); // dark muted red, typical extraction
      final base = HSLColor.fromColor(deepBackdropTone(swatch));
      final vivid = HSLColor.fromColor(deepBackdropTone(swatch, vivid: true));

      expect(
        vivid.lightness,
        greaterThan(base.lightness),
        reason: 'phone wash must read as a colour, not near-black',
      );
      expect(vivid.saturation, greaterThan(base.saturation));
      expect(vivid.hue, closeTo(base.hue, 0.001), reason: 'hue is preserved');
    });

    test('vivid still clamps a pale swatch down for text contrast', () {
      final tone = HSLColor.fromColor(
        deepBackdropTone(const Color(0xFFF3EAEA), vivid: true), // near-white
      );
      expect(tone.lightness, lessThanOrEqualTo(0.34));
    });
  });
}
