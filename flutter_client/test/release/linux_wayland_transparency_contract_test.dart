import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Linux attaches the transparent Flutter view before window realization',
    () {
      final source = File('linux/my_application.cc').readAsStringSync();

      int statementIndex(String statement) {
        expect(statement.allMatches(source), hasLength(1), reason: statement);
        return source.indexOf(statement);
      }

      final enableTransparency = statementIndex(
        'enable_video_plane_transparency(window, view);',
      );
      final showView = statementIndex(
        'gtk_widget_show(GTK_WIDGET(view));',
      );
      final attachView = statementIndex(
        'gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));',
      );
      final registerFlutterPlugins = statementIndex(
        'fl_register_plugins(FL_PLUGIN_REGISTRY(view));',
      );
      final registerMpvBackend = statementIndex(
        'desktop_libmpv_backend_register(FL_PLUGIN_REGISTRY(view));',
      );
      final showWindow = statementIndex(
        'gtk_widget_show(GTK_WIDGET(window));',
      );

      expect(enableTransparency, lessThan(showWindow));
      expect(showView, lessThan(attachView));
      expect(
        attachView,
        lessThan(showWindow),
        reason:
            'The transparent Flutter view must be attached before the '
            'toplevel window is shown and realized.',
      );
      expect(registerFlutterPlugins, lessThan(showWindow));
      expect(registerMpvBackend, lessThan(showWindow));
    },
  );
}
