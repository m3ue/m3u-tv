#import "AppDelegate.h"
// @generated begin react-native-keyevent-import - expo prebuild (DO NOT MODIFY) sync-3807e7899b947a617fc696f4f2a66dc6025e6b54
#import <RNKeyEvent.h>
// @generated end react-native-keyevent-import

#import <React/RCTBundleURLProvider.h>
#import <React/RCTLinkingManager.h>

@implementation AppDelegate
// @generated begin react-native-keyevent-body - expo prebuild (DO NOT MODIFY) sync-cccc1cb1fb7aa0d989cbc0626dad06801ade4f55
RNKeyEvent *keyEvent = nil;
 
- (NSMutableArray<UIKeyCommand *> *)keyCommands {
  NSMutableArray *keys = [NSMutableArray new];
   
  if (keyEvent == nil) {
    keyEvent = [[RNKeyEvent alloc] init];
  }
   
  if ([keyEvent isListening]) {
    NSArray *namesArray = [[keyEvent getKeys] componentsSeparatedByString:@","];
     
    NSCharacterSet *validChars = [NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZ"];
     
    for (NSString* names in namesArray) {
      NSRange  range = [names rangeOfCharacterFromSet:validChars];
       
      if (NSNotFound != range.location) {
        [keys addObject: [UIKeyCommand keyCommandWithInput:names modifierFlags:UIKeyModifierShift action:@selector(keyInput:)]];
      } else {
        [keys addObject: [UIKeyCommand keyCommandWithInput:names modifierFlags:0 action:@selector(keyInput:)]];
      }
    }
  }
   
  return keys;
}

- (void)keyInput:(UIKeyCommand *)sender {
  NSString *selected = sender.input;
  [keyEvent sendKeyEvent:selected];
}
// @generated end react-native-keyevent-body

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
  self.moduleName = @"main";

  // You can add your custom initial props in the dictionary below.
  // They will be passed down to the ViewController used by React Native.
  self.initialProps = @{};

  return [super application:application didFinishLaunchingWithOptions:launchOptions];
}

- (NSURL *)sourceURLForBridge:(RCTBridge *)bridge
{
  return [self bundleURL];
}

- (NSURL *)bundleURL
{
#if DEBUG
  return [[RCTBundleURLProvider sharedSettings] jsBundleURLForBundleRoot:@".expo/.virtual-metro-entry"];
#else
  return [[NSBundle mainBundle] URLForResource:@"main" withExtension:@"jsbundle"];
#endif
}

// Linking API
- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url options:(NSDictionary<UIApplicationOpenURLOptionsKey,id> *)options {
  return [super application:application openURL:url options:options] || [RCTLinkingManager application:application openURL:url options:options];
}

// Universal Links
- (BOOL)application:(UIApplication *)application continueUserActivity:(nonnull NSUserActivity *)userActivity restorationHandler:(nonnull void (^)(NSArray<id<UIUserActivityRestoring>> * _Nullable))restorationHandler {
  BOOL result = [RCTLinkingManager application:application continueUserActivity:userActivity restorationHandler:restorationHandler];
  return [super application:application continueUserActivity:userActivity restorationHandler:restorationHandler] || result;
}

// Explicitly define remote notification delegates to ensure compatibility with some third-party libraries
- (void)application:(UIApplication *)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken
{
  return [super application:application didRegisterForRemoteNotificationsWithDeviceToken:deviceToken];
}

// Explicitly define remote notification delegates to ensure compatibility with some third-party libraries
- (void)application:(UIApplication *)application didFailToRegisterForRemoteNotificationsWithError:(NSError *)error
{
  return [super application:application didFailToRegisterForRemoteNotificationsWithError:error];
}

// Explicitly define remote notification delegates to ensure compatibility with some third-party libraries
- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo fetchCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler
{
  return [super application:application didReceiveRemoteNotification:userInfo fetchCompletionHandler:completionHandler];
}

@end
