#import "GeneratedPluginRegistrant.h"
#import <Flutter/Flutter.h>

// FlutterSceneDelegate implements these UISceneDelegate callbacks but doesn't
// declare them in its header, so Swift can't call super on them. SceneDelegate
// sets the window up on the shared engine first, then hands over to these.
@interface FlutterSceneDelegate (M3USceneConnection)
- (void)scene:(UIScene *)scene
    willConnectToSession:(UISceneSession *)session
                 options:(UISceneConnectionOptions *)connectionOptions;
- (void)sceneDidDisconnect:(UIScene *)scene;
@end
