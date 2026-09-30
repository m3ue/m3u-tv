import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/epg/epg_guide_navigation.dart';
import 'package:m3u_tv/services/domain_models.dart';

void main() {
  DateTime at(int hour, [int minute = 0]) =>
      DateTime(2026, 7, 31, hour, minute);

  EpgProgram program(String title, DateTime start, DateTime end) => EpgProgram(
    channelId: 'chan',
    title: title,
    description: '',
    start: start,
    end: end,
  );

  final early = program('Early', at(8), at(9));
  final morning = program('Morning', at(9), at(10));
  final late = program('Late', at(11), at(12));
  final programs = [early, morning, late];

  group('EpgGuideNavigation.inWindow', () {
    test('keeps only programmes overlapping the window', () {
      final result = EpgGuideNavigation.inWindow(programs, at(9, 30), at(11));
      expect(result, [morning]);
    });

    test('drops slivers under a minute once clamped', () {
      final sliver = program(
        'Sliver',
        at(8, 59),
        DateTime(2026, 7, 31, 9, 0, 30),
      );
      final result = EpgGuideNavigation.inWindow(
        [sliver, morning],
        DateTime(2026, 7, 31, 9, 0, 1),
        at(12),
      );
      expect(result, [morning]);
    });
  });

  group('EpgGuideNavigation.at', () {
    test('returns the programme airing at the time', () {
      expect(EpgGuideNavigation.at(programs, at(9, 15)), morning);
    });

    test('an end instant belongs to the next programme', () {
      expect(EpgGuideNavigation.at(programs, at(9)), morning);
    });

    test('falls back to the nearest programme inside a gap', () {
      expect(EpgGuideNavigation.at(programs, at(10, 20)), morning);
      expect(EpgGuideNavigation.at(programs, at(10, 40)), late);
    });

    test('ties inside a gap go to the later programme', () {
      expect(EpgGuideNavigation.at(programs, at(10, 30)), late);
    });

    test('is null for an empty row', () {
      expect(EpgGuideNavigation.at(const [], at(9)), isNull);
    });
  });

  group('EpgGuideNavigation.next / previous', () {
    test('step through the row in order', () {
      expect(EpgGuideNavigation.next(programs, early), morning);
      expect(EpgGuideNavigation.next(programs, late), isNull);
      expect(EpgGuideNavigation.previous(programs, morning), early);
      expect(EpgGuideNavigation.previous(programs, early), isNull);
    });

    test('match by start so a refreshed programme object still resolves', () {
      final refreshed = program('Morning (updated)', at(9), at(10));
      expect(EpgGuideNavigation.next(programs, refreshed), late);
    });
  });

  group('EpgGuideNavigation.anchorFor', () {
    test('anchors on now while the programme is airing', () {
      expect(
        EpgGuideNavigation.anchorFor(
          morning,
          now: at(9, 40),
          visibleStart: at(9, 50),
        ),
        at(9, 40),
      );
    });

    test('anchors on the view start when the start is scrolled off', () {
      expect(
        EpgGuideNavigation.anchorFor(
          late,
          now: at(8),
          visibleStart: at(11, 20),
        ),
        at(11, 20),
      );
    });

    test('anchors on the start otherwise', () {
      expect(
        EpgGuideNavigation.anchorFor(late, now: at(8), visibleStart: at(10)),
        at(11),
      );
    });
  });
}
