#ifndef FLUTTER_CLIENT_WINDOWS_RUNNER_DESKTOP_LIBMPV_BACKEND_H_
#define FLUTTER_CLIENT_WINDOWS_RUNNER_DESKTOP_LIBMPV_BACKEND_H_

#include <flutter/plugin_registrar_windows.h>
#include <windows.h>

constexpr UINT kDesktopLibmpvPlatformDispatchMessage = WM_APP + 116;

bool DispatchDesktopLibmpvPlatformMessage(WPARAM task_id);
void RegisterDesktopLibmpvBackend(flutter::PluginRegistrarWindows* registrar, HWND hwnd);

#endif
