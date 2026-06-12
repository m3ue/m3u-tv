#ifndef FLUTTER_CLIENT_WINDOWS_RUNNER_DESKTOP_LIBMPV_BACKEND_H_
#define FLUTTER_CLIENT_WINDOWS_RUNNER_DESKTOP_LIBMPV_BACKEND_H_

#include <flutter/plugin_registrar_windows.h>
#include <windows.h>

void RegisterDesktopLibmpvBackend(flutter::PluginRegistrarWindows* registrar, HWND hwnd);

#endif
