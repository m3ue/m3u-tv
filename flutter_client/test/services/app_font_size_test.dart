import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/view_settings_service.dart';
import 'package:m3u_tv/shared/image_quality_scope.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  group('AppFontSize', () {
    test('sizes get strictly larger, smallest first', () {
      final scales = AppFontSize.values.map((size) => size.scale).toList();
      for (var i = 1; i < scales.length; i++) {
        expect(scales[i], greaterThan(scales[i - 1]));
      }
    });

    test('the existing sizes keep their scale', () {
      expect(AppFontSize.normal.scale, closeTo(1.15, 0.0001));
      expect(AppFontSize.large.scale, closeTo(1.38, 0.0001));
      expect(AppFontSize.veryLarge.scale, closeTo(1.725, 0.0001));
    });

    test('every size round-trips through its stored value', () {
      for (final size in AppFontSize.values) {
        expect(AppFontSize.fromValue(size.value), size);
      }
    });

    test('defaults are unchanged', () {
      expect(
        AppFontSize.resolveDefault(stored: null, isTv: true),
        AppFontSize.veryLarge,
      );
      expect(
        AppFontSize.resolveDefault(stored: null, isTv: false),
        AppFontSize.normal,
      );
      expect(
        AppFontSize.resolveDefault(stored: AppFontSize.verySmall, isTv: true),
        AppFontSize.verySmall,
      );
    });

    test('a chosen small size persists', () async {
      final service = ViewSettingsService(memory: <String, Object?>{});
      await service.setFontSize(AppFontSize.small);
      expect(await service.fontSizeOrNull(), AppFontSize.small);
    });
  });

  group('FontSizeScope.isLarge', () {
    for (final (size, expected) in [
      (AppFontSize.verySmall, false),
      (AppFontSize.small, false),
      (AppFontSize.normal, false),
      (AppFontSize.large, true),
      (AppFontSize.veryLarge, true),
    ]) {
      test('${size.name} is $expected', () {
        expect(
          FontSizeScope(fontSize: size, child: const SizedBox()).isLarge,
          expected,
        );
      });
    }
  });
}
