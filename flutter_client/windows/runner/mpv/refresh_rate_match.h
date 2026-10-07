#pragma once

// Refresh-rate selection for DisplayModeManager::MatchRefreshRate. Kept free
// of Windows headers so it can be compiled and tested on any host. Ported from
// Plezy's DisplayModeService.findBestRefreshRate (github.com/edde746/plezy,
// GPL-3.0).

#include <cmath>
#include <cstdint>
#include <vector>

namespace refresh_rate_match {

// The rate a Windows mode really runs at. Windows reports whole hertz, and the
// NTSC-family 1000/1001 rates (23.976, 29.97, 59.94 and multiples such as
// 47.952 or 119.88) come through one below the nominal rate: 23, 29, 59, 47,
// 119.
inline double EffectiveRefreshRate(uint32_t rate) {
  const uint32_t nominal = rate + 1;
  if (nominal % 24 == 0 || nominal % 30 == 0) return nominal * 1000.0 / 1001.0;
  return static_cast<double>(rate);
}

// The best of `rates` (whole-hertz values as Windows reports them) for
// `video_fps`: the lowest whole multiple of it within 0.5%, and of those the
// closest, so 23.976 fps content takes a 23 (23.976) Hz mode over 24 Hz and an
// exact rate beats any multiple. 0 when no rate is within tolerance.
inline uint32_t FindBestRefreshRate(double video_fps, const std::vector<uint32_t>& rates) {
  if (!(video_fps > 0.0)) return 0;
  uint32_t best_rate = 0;
  int best_multiplier = 0;
  double best_deviation = 0.0;
  for (const uint32_t rate : rates) {
    if (rate == 0) continue;
    const double ratio = EffectiveRefreshRate(rate) / video_fps;
    const double rounded = std::round(ratio);
    if (rounded < 1.0) continue;
    const int multiplier = static_cast<int>(rounded);
    const double deviation = std::fabs(ratio - rounded) / rounded;
    if (deviation > 0.005) continue;
    const bool better = best_rate == 0 || multiplier < best_multiplier ||
                        (multiplier == best_multiplier &&
                         (deviation < best_deviation || (deviation == best_deviation && rate > best_rate)));
    if (better) {
      best_rate = rate;
      best_multiplier = multiplier;
      best_deviation = deviation;
    }
  }
  return best_rate;
}

}  // namespace refresh_rate_match
