#ifndef FLUTTER_CLIENT_WINDOWS_MPV_DISPLAY_MODE_MANAGER_H_
#define FLUTTER_CLIENT_WINDOWS_MPV_DISPLAY_MODE_MANAGER_H_

#include <Windows.h>

#include <optional>
#include <string>
#include <vector>

// Manages Windows display-mode switching (refresh rate, HDR) for video
// playback. Pure Win32 utility -- no mpv or Flutter dependency.
//
// Adapted from the open-source Plezy player's `DisplayModeManager`
// (github.com/edde746/plezy, GPL-3.0, windows/runner/mpv/display_mode_manager.h),
// itself following Kodi's DisplayUtilsWin32.cpp / WIN32Util.cpp for the
// underlying DisplayConfig/ChangeDisplaySettingsExW sequences.
//
// Deliberately simplified from Plezy's crash-recovery design: Plezy persists
// a dual-slot registry journal (an "alternate" slot, "takeover eligibility",
// and "handoff pending" state) so two *simultaneously conflicting* recovery
// operations -- e.g. two app instances fighting over the same display --
// resolve safely. This app never runs more than one playback session against
// a display at a time, so that concurrency problem does not arise here; a
// single-record "was a mode/HDR override left applied" marker, restored at
// next launch, delivers the same actual safety property (a crash mid-switch
// does not permanently strand the display) with far less state-machine
// surface to get wrong blind. See RecoverIfNeeded().
//
// References:
//   ChangeDisplaySettingsExW:
//   https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-changedisplaysettingsexw
//   EnumDisplaySettingsW:
//   https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-enumdisplaysettingsw
//   DisplayConfigGetDeviceInfo:
//   https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-displayconfiggetdeviceinfo
//   DisplayConfigSetDeviceInfo:
//   https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-displayconfigsetdeviceinfo
namespace m3u_tv_mpv_windows {

struct DisplayMode {
  DWORD width = 0;
  DWORD height = 0;
  DWORD refresh_rate = 0;
};

// Identifies a display target in the DisplayConfig API.
struct DisplayConfigId {
  LUID adapter_id;
  UINT32 id = 0;
};

class DisplayModeManager {
 public:
  DisplayModeManager() = default;
  ~DisplayModeManager() = default;

  DisplayModeManager(const DisplayModeManager&) = delete;
  DisplayModeManager& operator=(const DisplayModeManager&) = delete;

  // --- Refresh rate / resolution ---

  // Enumerates available display modes for the monitor containing `window`.
  std::vector<DisplayMode> EnumerateDisplayModes(HWND window);

  // Returns the current display mode for the monitor containing `window`.
  DisplayMode GetCurrentMode(HWND window);

  // Changes the refresh rate at the *current* resolution only -- this app
  // never requests a resolution change, which is the higher-risk half of
  // what SetDisplayMode could do (a wrong resolution can blank the display;
  // a wrong refresh rate at the same resolution cannot). Only exact matches
  // (or within 0.05 Hz, since some drivers report a fractional NTSC rate
  // like 23.976 imprecisely) at the current resolution are applied; no
  // fallback resolution search is attempted. Returns true on success.
  bool MatchRefreshRate(HWND window, double target_fps);

  // Restores the previously saved display mode. No-op if none is pending.
  bool RestoreOriginalMode(HWND window);

  // True when a mode change has been applied and not yet restored.
  bool IsModeChanged() const { return mode_changed_; }

  // --- HDR ---

  // True if the display supports HDR (not just Advanced Color Mode/WCG).
  bool IsHDRSupported(HWND window);

  // True if HDR is currently enabled on the display.
  bool IsHDREnabled(HWND window);

  // Enables or disables system HDR for the monitor containing `window`.
  // Saves/restores DEVMODEW around the toggle, since Windows can change the
  // display mode as a side effect of an HDR state change.
  bool SetHDREnabled(HWND window, bool enabled);

  // Restores the previously saved HDR state. No-op if none is pending.
  bool RestoreOriginalHDRState(HWND window);

  // True when an HDR state change has been applied and not yet restored.
  bool IsHDRChanged() const { return hdr_changed_; }

  // --- Crash recovery ---
  //
  // Call once at process startup, before any SetHDREnabled/MatchRefreshRate
  // call from this or any other DisplayModeManager instance in the process.
  // Best-effort: a failure here just means a display left changed by a
  // previous crash stays changed until the user resets it by hand in
  // Windows Display Settings, which is the same outcome as not having this
  // at all -- it never leaves the display in a state a plain restart can't
  // recover from.
  static void RecoverIfNeeded();

  // Exposed for DisplayRecoveryTest -- computes the DisplayConfig target for
  // a GDI device name and the version-appropriate HDR toggle call, both pure
  // functions of Win32 state rather than of this object's instance fields.
  static std::optional<DisplayConfigId> GetDisplayTargetId(const std::wstring& gdi_device_name);
  static LONG SetHDRStateForTarget(const DisplayConfigId& target, bool enabled);

 private:
  static std::wstring GetMonitorDeviceName(HWND window);
  static std::vector<DISPLAYCONFIG_PATH_INFO> GetDisplayConfigPaths();
  static bool IsWin11_24H2OrNewer();

  // Stored original mode for restoration.
  std::wstring original_device_name_;
  DEVMODEW original_devmode_ = {};
  bool mode_changed_ = false;

  // Stored original HDR state for restoration.
  std::wstring original_hdr_device_name_;
  bool original_hdr_enabled_ = false;
  bool hdr_changed_ = false;
};

}  // namespace m3u_tv_mpv_windows

#endif  // FLUTTER_CLIENT_WINDOWS_MPV_DISPLAY_MODE_MANAGER_H_
