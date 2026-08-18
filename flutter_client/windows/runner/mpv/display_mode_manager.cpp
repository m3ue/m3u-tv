#include "display_mode_manager.h"

#include <algorithm>
#include <cmath>
#include <mutex>

#include "sdk_26100.h"

// Win32 API sequences (DisplayConfig target lookup, Kodi's Win8+ workaround
// for exact-integer refresh rates, the pre/post-toggle DEVMODEW save around
// an HDR state change) adapted from the open-source Plezy player
// (github.com/edde746/plezy, GPL-3.0, windows/runner/mpv/display_mode_manager.cpp),
// itself following Kodi's DisplayUtilsWin32.cpp / WIN32Util.cpp. The
// crash-recovery journal is a from-scratch, deliberately simplified
// single-record design -- see the header comment for why.

namespace m3u_tv_mpv_windows {

namespace {

constexpr wchar_t kRegistryPath[] = L"Software\\M3UTv\\DisplayModeOverride";
constexpr wchar_t kRegModeDeviceName[] = L"ModeDeviceName";
constexpr wchar_t kRegOriginalWidth[] = L"OriginalWidth";
constexpr wchar_t kRegOriginalHeight[] = L"OriginalHeight";
constexpr wchar_t kRegOriginalRefreshRate[] = L"OriginalRefreshRate";
constexpr wchar_t kRegModeChanged[] = L"ModeChanged";
constexpr wchar_t kRegHDRDeviceName[] = L"HDRDeviceName";
constexpr wchar_t kRegOriginalHDR[] = L"OriginalHDREnabled";
constexpr wchar_t kRegHDRChanged[] = L"HDRChanged";

// Guards the whole persisted record against two DisplayModeManager instances
// in this process racing each other; there is normally only one (the active
// player's), but a dispose racing a fresh load during a fast source switch
// is exactly the case this exists for.
std::mutex g_registry_mutex;

bool WriteRegistryDWORD(const wchar_t* value_name, DWORD value) {
  HKEY key;
  if (RegCreateKeyExW(HKEY_CURRENT_USER, kRegistryPath, 0, nullptr, 0, KEY_WRITE, nullptr, &key, nullptr) !=
      ERROR_SUCCESS) {
    return false;
  }
  const LONG result =
      RegSetValueExW(key, value_name, 0, REG_DWORD, reinterpret_cast<const BYTE*>(&value), sizeof(value));
  RegCloseKey(key);
  return result == ERROR_SUCCESS;
}

bool WriteRegistryString(const wchar_t* value_name, const std::wstring& value) {
  HKEY key;
  if (RegCreateKeyExW(HKEY_CURRENT_USER, kRegistryPath, 0, nullptr, 0, KEY_WRITE, nullptr, &key, nullptr) !=
      ERROR_SUCCESS) {
    return false;
  }
  const LONG result = RegSetValueExW(
      key, value_name, 0, REG_SZ, reinterpret_cast<const BYTE*>(value.c_str()),
      static_cast<DWORD>((value.size() + 1) * sizeof(wchar_t)));
  RegCloseKey(key);
  return result == ERROR_SUCCESS;
}

bool ReadRegistryDWORD(const wchar_t* value_name, DWORD& value) {
  HKEY key;
  if (RegOpenKeyExW(HKEY_CURRENT_USER, kRegistryPath, 0, KEY_READ, &key) != ERROR_SUCCESS) return false;
  DWORD size = sizeof(value);
  DWORD type = 0;
  const LONG result = RegQueryValueExW(key, value_name, nullptr, &type, reinterpret_cast<BYTE*>(&value), &size);
  RegCloseKey(key);
  return result == ERROR_SUCCESS && type == REG_DWORD && size == sizeof(value);
}

bool ReadRegistryString(const wchar_t* value_name, std::wstring& value) {
  HKEY key;
  if (RegOpenKeyExW(HKEY_CURRENT_USER, kRegistryPath, 0, KEY_READ, &key) != ERROR_SUCCESS) return false;
  DWORD size = 0;
  DWORD type = 0;
  if (RegQueryValueExW(key, value_name, nullptr, &type, nullptr, &size) != ERROR_SUCCESS || type != REG_SZ ||
      size == 0 || size % sizeof(wchar_t) != 0) {
    RegCloseKey(key);
    return false;
  }
  value.resize(size / sizeof(wchar_t));
  const LONG result = RegQueryValueExW(key, value_name, nullptr, nullptr, reinterpret_cast<BYTE*>(value.data()), &size);
  RegCloseKey(key);
  if (result != ERROR_SUCCESS) return false;
  while (!value.empty() && value.back() == L'\0') value.pop_back();
  return !value.empty();
}

void ClearMarker(const wchar_t* value_name) { WriteRegistryDWORD(value_name, 0); }

void DeleteRecordIfFullyClear() {
  DWORD mode_changed = 0;
  DWORD hdr_changed = 0;
  ReadRegistryDWORD(kRegModeChanged, mode_changed);
  ReadRegistryDWORD(kRegHDRChanged, hdr_changed);
  if (mode_changed != 0 || hdr_changed != 0) return;
  RegDeleteKeyW(HKEY_CURRENT_USER, kRegistryPath);
}

// Applies a saved DEVMODEW mode via ChangeDisplaySettingsExW. Shared by the
// normal restore path and startup crash recovery.
bool ApplyMode(const std::wstring& device_name, DWORD width, DWORD height, DWORD refresh_rate) {
  DEVMODEW dm = {};
  dm.dmSize = sizeof(dm);
  dm.dmPelsWidth = width;
  dm.dmPelsHeight = height;
  dm.dmDisplayFrequency = refresh_rate;
  dm.dmFields = DM_PELSWIDTH | DM_PELSHEIGHT | DM_DISPLAYFREQUENCY;
  return ChangeDisplaySettingsExW(device_name.c_str(), &dm, nullptr, CDS_FULLSCREEN, nullptr) == DISP_CHANGE_SUCCESSFUL;
}

bool ApplyHDR(const std::wstring& device_name, bool enabled) {
  const auto target_id = DisplayModeManager::GetDisplayTargetId(device_name);
  if (!target_id) return false;

  // Windows can change the display mode as a side effect of an HDR toggle;
  // save and restore DEVMODEW around it (Kodi WIN32Util.cpp:1252-1288).
  DEVMODEW pre_toggle_dm = {};
  pre_toggle_dm.dmSize = sizeof(pre_toggle_dm);
  EnumDisplaySettingsW(device_name.c_str(), ENUM_CURRENT_SETTINGS, &pre_toggle_dm);

  if (DisplayModeManager::SetHDRStateForTarget(*target_id, enabled) != ERROR_SUCCESS) return false;

  if (pre_toggle_dm.dmDisplayFrequency != 0) {
    pre_toggle_dm.dmFields = DM_PELSWIDTH | DM_PELSHEIGHT | DM_DISPLAYFREQUENCY | DM_DISPLAYFLAGS;
    ChangeDisplaySettingsExW(device_name.c_str(), &pre_toggle_dm, nullptr, CDS_FULLSCREEN, nullptr);
  }
  return true;
}

}  // namespace

std::wstring DisplayModeManager::GetMonitorDeviceName(HWND window) {
  HMONITOR monitor = MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST);
  if (!monitor) return {};

  MONITORINFOEXW mi = {};
  mi.cbSize = sizeof(mi);
  if (!GetMonitorInfoW(monitor, &mi)) return {};

  return mi.szDevice;
}

std::vector<DISPLAYCONFIG_PATH_INFO> DisplayModeManager::GetDisplayConfigPaths() {
  UINT32 path_count = 0;
  UINT32 mode_count = 0;
  std::vector<DISPLAYCONFIG_PATH_INFO> paths;
  std::vector<DISPLAYCONFIG_MODE_INFO> modes;

  constexpr UINT32 flags = QDC_ONLY_ACTIVE_PATHS;
  LONG result;
  // Retry loop for ERROR_INSUFFICIENT_BUFFER (Kodi pattern): the topology can
  // change between the size query and the fetch.
  do {
    if (GetDisplayConfigBufferSizes(flags, &path_count, &mode_count) != ERROR_SUCCESS) return {};
    paths.resize(path_count);
    modes.resize(mode_count);
    result = QueryDisplayConfig(flags, &path_count, paths.data(), &mode_count, modes.data(), nullptr);
  } while (result == ERROR_INSUFFICIENT_BUFFER);

  if (result != ERROR_SUCCESS) return {};
  paths.resize(path_count);
  return paths;
}

std::optional<DisplayConfigId> DisplayModeManager::GetDisplayTargetId(const std::wstring& gdi_device_name) {
  DISPLAYCONFIG_SOURCE_DEVICE_NAME source = {};
  source.header.type = DISPLAYCONFIG_DEVICE_INFO_GET_SOURCE_NAME;
  source.header.size = sizeof(source);

  for (const auto& path : GetDisplayConfigPaths()) {
    source.header.adapterId = path.sourceInfo.adapterId;
    source.header.id = path.sourceInfo.id;
    if (DisplayConfigGetDeviceInfo(&source.header) == ERROR_SUCCESS && gdi_device_name == source.viewGdiDeviceName) {
      return DisplayConfigId{path.targetInfo.adapterId, path.targetInfo.id};
    }
  }
  return std::nullopt;
}

bool DisplayModeManager::IsWin11_24H2OrNewer() {
  // Win11 24H2 = build 26100+.
  OSVERSIONINFOEXW osvi = {};
  osvi.dwOSVersionInfoSize = sizeof(osvi);
  osvi.dwBuildNumber = 26100;
  DWORDLONG condition_mask = 0;
  VER_SET_CONDITION(condition_mask, VER_BUILDNUMBER, VER_GREATER_EQUAL);
  return VerifyVersionInfoW(&osvi, VER_BUILDNUMBER, condition_mask) != FALSE;
}

std::vector<DisplayMode> DisplayModeManager::EnumerateDisplayModes(HWND window) {
  const std::wstring device_name = GetMonitorDeviceName(window);
  if (device_name.empty()) return {};

  std::vector<DisplayMode> modes;
  DEVMODEW dm = {};
  dm.dmSize = sizeof(dm);
  for (DWORD i = 0; EnumDisplaySettingsW(device_name.c_str(), i, &dm); i++) {
    modes.push_back({dm.dmPelsWidth, dm.dmPelsHeight, dm.dmDisplayFrequency});
  }

  std::sort(modes.begin(), modes.end(), [](const DisplayMode& a, const DisplayMode& b) {
    if (a.width != b.width) return a.width < b.width;
    if (a.height != b.height) return a.height < b.height;
    return a.refresh_rate < b.refresh_rate;
  });
  modes.erase(
      std::unique(
          modes.begin(), modes.end(),
          [](const DisplayMode& a, const DisplayMode& b) {
            return a.width == b.width && a.height == b.height && a.refresh_rate == b.refresh_rate;
          }),
      modes.end());
  return modes;
}

DisplayMode DisplayModeManager::GetCurrentMode(HWND window) {
  const std::wstring device_name = GetMonitorDeviceName(window);
  DisplayMode mode;
  if (device_name.empty()) return mode;

  DEVMODEW dm = {};
  dm.dmSize = sizeof(dm);
  if (EnumDisplaySettingsW(device_name.c_str(), ENUM_CURRENT_SETTINGS, &dm)) {
    mode = {dm.dmPelsWidth, dm.dmPelsHeight, dm.dmDisplayFrequency};
  }
  return mode;
}

bool DisplayModeManager::MatchRefreshRate(HWND window, double target_fps) {
  std::lock_guard<std::mutex> lock(g_registry_mutex);
  if (!(target_fps > 0.0)) return false;

  const std::wstring device_name = GetMonitorDeviceName(window);
  if (device_name.empty()) return false;

  const DisplayMode current = GetCurrentMode(window);
  if (current.width == 0 || current.height == 0 || current.refresh_rate == 0) return false;

  // Only a mode at the *current* resolution is a candidate -- no resolution
  // search, see the header comment on why that risk is deliberately not
  // taken here.
  const DisplayMode* best = nullptr;
  double best_distance = 1.0;  // Hz; anything farther than this is not "the same rate".
  for (const DisplayMode& mode : EnumerateDisplayModes(window)) {
    if (mode.width != current.width || mode.height != current.height) continue;
    const double distance = std::fabs(static_cast<double>(mode.refresh_rate) - target_fps);
    if (distance < best_distance) {
      best_distance = distance;
      best = &mode;
    }
  }
  if (best == nullptr || best->refresh_rate == current.refresh_rate) return false;

  const bool mode_was_changed = mode_changed_;
  if (!mode_changed_) {
    original_device_name_ = device_name;
    original_devmode_ = {};
    original_devmode_.dmSize = sizeof(original_devmode_);
    EnumDisplaySettingsW(device_name.c_str(), ENUM_CURRENT_SETTINGS, &original_devmode_);
  }
  if (original_device_name_.empty() || original_devmode_.dmPelsWidth == 0) return false;

  // Persist the original before touching the OS; see RecoverIfNeeded().
  if (!WriteRegistryString(kRegModeDeviceName, original_device_name_) ||
      !WriteRegistryDWORD(kRegOriginalWidth, original_devmode_.dmPelsWidth) ||
      !WriteRegistryDWORD(kRegOriginalHeight, original_devmode_.dmPelsHeight) ||
      !WriteRegistryDWORD(kRegOriginalRefreshRate, original_devmode_.dmDisplayFrequency) ||
      !WriteRegistryDWORD(kRegModeChanged, 1)) {
    return false;
  }

  bool changed = false;
  // Kodi's Win8+ workaround for exact-integer refresh rates (24/48/60 Hz):
  // write the desired mode to the registry, apply *from* the registry, then
  // restore the registry to what it was. Source:
  // xbmc/windowing/windows/WinSystemWin32.cpp:940-970.
  if (best->refresh_rate == 24 || best->refresh_rate == 48 || best->refresh_rate == 60) {
    DEVMODEW registry_dm = {};
    registry_dm.dmSize = sizeof(registry_dm);
    if (EnumDisplaySettingsW(device_name.c_str(), ENUM_REGISTRY_SETTINGS, &registry_dm)) {
      DEVMODEW dm = {};
      dm.dmSize = sizeof(dm);
      dm.dmPelsWidth = best->width;
      dm.dmPelsHeight = best->height;
      dm.dmDisplayFrequency = best->refresh_rate;
      dm.dmFields = DM_PELSWIDTH | DM_PELSHEIGHT | DM_DISPLAYFREQUENCY;
      if (ChangeDisplaySettingsExW(device_name.c_str(), &dm, nullptr, CDS_UPDATEREGISTRY | CDS_NORESET, nullptr) ==
          DISP_CHANGE_SUCCESSFUL) {
        changed =
            ChangeDisplaySettingsExW(device_name.c_str(), nullptr, nullptr, CDS_FULLSCREEN, nullptr) ==
            DISP_CHANGE_SUCCESSFUL;
      }
      registry_dm.dmFields = DM_PELSWIDTH | DM_PELSHEIGHT | DM_DISPLAYFREQUENCY | DM_DISPLAYFLAGS;
      ChangeDisplaySettingsExW(device_name.c_str(), &registry_dm, nullptr, CDS_UPDATEREGISTRY | CDS_NORESET, nullptr);
    }
  }
  if (!changed) changed = ApplyMode(device_name, best->width, best->height, best->refresh_rate);

  if (changed) {
    mode_changed_ = true;
  } else if (!mode_was_changed) {
    ClearMarker(kRegModeChanged);
    DeleteRecordIfFullyClear();
  }
  return changed;
}

bool DisplayModeManager::RestoreOriginalMode(HWND) {
  std::lock_guard<std::mutex> lock(g_registry_mutex);
  if (!mode_changed_ || original_device_name_.empty()) return false;

  original_devmode_.dmFields = DM_PELSWIDTH | DM_PELSHEIGHT | DM_DISPLAYFREQUENCY | DM_DISPLAYFLAGS;
  LONG rc =
      ChangeDisplaySettingsExW(original_device_name_.c_str(), &original_devmode_, nullptr, CDS_FULLSCREEN, nullptr);
  if (rc != DISP_CHANGE_SUCCESSFUL) {
    rc = ChangeDisplaySettingsExW(original_device_name_.c_str(), nullptr, nullptr, 0, nullptr);
  }
  if (rc != DISP_CHANGE_SUCCESSFUL) return false;

  mode_changed_ = false;
  ClearMarker(kRegModeChanged);
  DeleteRecordIfFullyClear();
  return true;
}

bool DisplayModeManager::IsHDRSupported(HWND window) {
  const std::wstring device_name = GetMonitorDeviceName(window);
  if (device_name.empty()) return false;
  const auto target_id = GetDisplayTargetId(device_name);
  if (!target_id) return false;

  // Follows Kodi's GetDisplayHDRStatus pattern.
  if (IsWin11_24H2OrNewer()) {
    DISPLAYCONFIG_GET_ADVANCED_COLOR_INFO_2 info = {};
    info.header.type = static_cast<DISPLAYCONFIG_DEVICE_INFO_TYPE>(DISPLAYCONFIG_DEVICE_INFO_GET_ADVANCED_COLOR_INFO_2);
    info.header.size = sizeof(info);
    info.header.adapterId = target_id->adapter_id;
    info.header.id = target_id->id;
    if (DisplayConfigGetDeviceInfo(&info.header) == ERROR_SUCCESS) return info.highDynamicRangeSupported == TRUE;
  } else {
    DISPLAYCONFIG_GET_ADVANCED_COLOR_INFO info = {};
    info.header.type = DISPLAYCONFIG_DEVICE_INFO_GET_ADVANCED_COLOR_INFO;
    info.header.size = sizeof(info);
    info.header.adapterId = target_id->adapter_id;
    info.header.id = target_id->id;
    if (DisplayConfigGetDeviceInfo(&info.header) == ERROR_SUCCESS) {
      // advancedColorSupported=1 && wideColorEnforced=0 => true HDR screen.
      // advancedColorSupported=1 && wideColorEnforced=1 => SDR screen with
      // ACM (Win11 22H2+). Source: Kodi DisplayUtilsWin32.cpp:157-172.
      return info.advancedColorSupported && !info.wideColorEnforced;
    }
  }
  return false;
}

bool DisplayModeManager::IsHDREnabled(HWND window) {
  const std::wstring device_name = GetMonitorDeviceName(window);
  if (device_name.empty()) return false;
  const auto target_id = GetDisplayTargetId(device_name);
  if (!target_id) return false;

  if (IsWin11_24H2OrNewer()) {
    DISPLAYCONFIG_GET_ADVANCED_COLOR_INFO_2 info = {};
    info.header.type = static_cast<DISPLAYCONFIG_DEVICE_INFO_TYPE>(DISPLAYCONFIG_DEVICE_INFO_GET_ADVANCED_COLOR_INFO_2);
    info.header.size = sizeof(info);
    info.header.adapterId = target_id->adapter_id;
    info.header.id = target_id->id;
    if (DisplayConfigGetDeviceInfo(&info.header) == ERROR_SUCCESS) {
      return info.activeColorMode == DISPLAYCONFIG_ADVANCED_COLOR_MODE_HDR;
    }
  } else {
    DISPLAYCONFIG_GET_ADVANCED_COLOR_INFO info = {};
    info.header.type = DISPLAYCONFIG_DEVICE_INFO_GET_ADVANCED_COLOR_INFO;
    info.header.size = sizeof(info);
    info.header.adapterId = target_id->adapter_id;
    info.header.id = target_id->id;
    if (DisplayConfigGetDeviceInfo(&info.header) == ERROR_SUCCESS) {
      return info.advancedColorSupported && !info.wideColorEnforced && info.advancedColorEnabled;
    }
  }
  return false;
}

bool DisplayModeManager::SetHDREnabled(HWND window, bool enabled) {
  std::lock_guard<std::mutex> lock(g_registry_mutex);
  const std::wstring device_name = GetMonitorDeviceName(window);
  if (device_name.empty()) return false;

  const bool hdr_was_changed = hdr_changed_;
  if (!hdr_changed_) {
    original_hdr_device_name_ = device_name;
    original_hdr_enabled_ = IsHDREnabled(window);
  }
  if (original_hdr_device_name_.empty()) return false;

  if (!WriteRegistryString(kRegHDRDeviceName, original_hdr_device_name_) ||
      !WriteRegistryDWORD(kRegOriginalHDR, original_hdr_enabled_ ? 1 : 0) ||
      !WriteRegistryDWORD(kRegHDRChanged, 1)) {
    return false;
  }

  if (!ApplyHDR(device_name, enabled)) {
    if (!hdr_was_changed) {
      ClearMarker(kRegHDRChanged);
      DeleteRecordIfFullyClear();
    }
    return false;
  }

  hdr_changed_ = true;
  return true;
}

bool DisplayModeManager::RestoreOriginalHDRState(HWND window) {
  std::lock_guard<std::mutex> lock(g_registry_mutex);
  if (!hdr_changed_ || original_hdr_device_name_.empty()) return false;

  if (IsHDREnabled(window) != original_hdr_enabled_) {
    if (!ApplyHDR(original_hdr_device_name_, original_hdr_enabled_)) return false;
  }

  hdr_changed_ = false;
  ClearMarker(kRegHDRChanged);
  DeleteRecordIfFullyClear();
  return true;
}

LONG DisplayModeManager::SetHDRStateForTarget(const DisplayConfigId& target, bool enabled) {
  if (IsWin11_24H2OrNewer()) {
    DISPLAYCONFIG_SET_HDR_STATE state = {};
    state.header.type = static_cast<DISPLAYCONFIG_DEVICE_INFO_TYPE>(DISPLAYCONFIG_DEVICE_INFO_SET_HDR_STATE);
    state.header.size = sizeof(state);
    state.header.adapterId = target.adapter_id;
    state.header.id = target.id;
    state.enableHdr = enabled ? TRUE : FALSE;
    return DisplayConfigSetDeviceInfo(&state.header);
  }
  DISPLAYCONFIG_SET_ADVANCED_COLOR_STATE state = {};
  state.header.type = DISPLAYCONFIG_DEVICE_INFO_SET_ADVANCED_COLOR_STATE;
  state.header.size = sizeof(state);
  state.header.adapterId = target.adapter_id;
  state.header.id = target.id;
  state.enableAdvancedColor = enabled ? TRUE : FALSE;
  return DisplayConfigSetDeviceInfo(&state.header);
}

// static
void DisplayModeManager::RecoverIfNeeded() {
  std::lock_guard<std::mutex> lock(g_registry_mutex);

  DWORD mode_changed = 0;
  if (ReadRegistryDWORD(kRegModeChanged, mode_changed) && mode_changed != 0) {
    std::wstring device_name;
    DWORD width = 0, height = 0, refresh_rate = 0;
    if (ReadRegistryString(kRegModeDeviceName, device_name) && ReadRegistryDWORD(kRegOriginalWidth, width) &&
        ReadRegistryDWORD(kRegOriginalHeight, height) && ReadRegistryDWORD(kRegOriginalRefreshRate, refresh_rate) &&
        width > 0 && height > 0 && refresh_rate > 0) {
      ApplyMode(device_name, width, height, refresh_rate);
    }
    ClearMarker(kRegModeChanged);
  }

  DWORD hdr_changed = 0;
  if (ReadRegistryDWORD(kRegHDRChanged, hdr_changed) && hdr_changed != 0) {
    std::wstring device_name;
    DWORD original_enabled = 0;
    if (ReadRegistryString(kRegHDRDeviceName, device_name) && ReadRegistryDWORD(kRegOriginalHDR, original_enabled)) {
      ApplyHDR(device_name, original_enabled != 0);
    }
    ClearMarker(kRegHDRChanged);
  }

  DeleteRecordIfFullyClear();
}

}  // namespace m3u_tv_mpv_windows
