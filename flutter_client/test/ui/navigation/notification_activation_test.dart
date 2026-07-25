import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/app/app_shell.dart';
import 'package:m3u_tv/navigation/route_names.dart';
import 'package:m3u_tv/services/tv_notification_service.dart';

void main() {
  test('safe activation destinations use the fixed route table', () {
    expect(
      notificationRouteFor(TvNotificationDestination.notifications),
      RouteNames.notifications,
    );
    expect(
      notificationRouteFor(
        TvNotificationDestination.dvr,
        hasDvrFeature: true,
      ),
      RouteNames.dvr,
    );
    expect(
      notificationRouteFor(
        TvNotificationDestination.requests,
        hasRequestsFeature: true,
      ),
      RouteNames.requests,
    );
  });

  test('unavailable feature destinations fail closed to notifications', () {
    expect(
      notificationRouteFor(TvNotificationDestination.dvr),
      RouteNames.notifications,
    );
    expect(
      notificationRouteFor(TvNotificationDestination.requests),
      RouteNames.notifications,
    );
  });
}
