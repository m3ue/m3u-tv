#ifndef FLUTTER_CLIENT_MACOS_RUNNER_DESKTOP_LIBMPV_BACKEND_H_
#define FLUTTER_CLIENT_MACOS_RUNNER_DESKTOP_LIBMPV_BACKEND_H_

#import <FlutterMacOS/FlutterMacOS.h>

NS_ASSUME_NONNULL_BEGIN

// Registers the "m3u_tv/desktop_libmpv" method channel and
// "m3u_tv/desktop_libmpv/events" event channel against the given plugin
// registry, mirroring desktop_libmpv_backend_register() on Linux and
// RegisterDesktopLibmpvBackend() on Windows.
@interface DesktopLibmpvBackend : NSObject

+ (void)registerWithRegistry:(NSObject<FlutterPluginRegistry> *)registry;
+ (void)shutdown;

@end

NS_ASSUME_NONNULL_END

#endif  // FLUTTER_CLIENT_MACOS_RUNNER_DESKTOP_LIBMPV_BACKEND_H_
