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

struct RateMatch {
  uint32_t rate = 0;
  double deviation = 0.0;
};

// The lowest whole multiple of `video_fps` among `rates` within 0.5%, and of
// those the closest. rate is 0 when no rate is within tolerance.
inline RateMatch LowestMultiple(double video_fps, const std::vector<uint32_t>& rates) {
  RateMatch best;
  int best_multiplier = 0;
  for (const uint32_t rate : rates) {
    if (rate == 0) continue;
    const double ratio = EffectiveRefreshRate(rate) / video_fps;
    const double rounded = std::round(ratio);
    if (rounded < 1.0) continue;
    const int multiplier = static_cast<int>(rounded);
    const double deviation = std::fabs(ratio - rounded) / rounded;
    if (deviation > 0.005) continue;
    const bool better = best.rate == 0 || multiplier < best_multiplier ||
                        (multiplier == best_multiplier &&
                         (deviation < best.deviation || (deviation == best.deviation && rate > best.rate)));
    if (better) {
      best = {rate, deviation};
      best_multiplier = multiplier;
    }
  }
  return best;
}

// 25 and 29.97/30 fps-class content, which a 50/60 Hz mode shows at exactly
// twice its rate.
constexpr double kHalfRateMinFps = 24.5;
constexpr double kHalfRateMaxFps = 30.5;

// Relative rate error below which two matches count as equally precise: above
// the rounding in reported rates, below the 0.1% NTSC mismatch.
constexpr double kPreciseDeviation = 0.0002;

// The best of `rates` (whole-hertz values as Windows reports them) for
// `video_fps`: the lowest whole multiple of it within 0.5%, and of those the
// closest, so 23.976 fps content takes a 23 (23.976) Hz mode over 24 Hz and an
// exact rate beats any multiple. 25 and 30 fps-class content takes 50/60 Hz
// over its own 25/30 Hz modes unless they are more precise, as the Android
// DisplayModeSelector does: 2:2 has no judder, and a 25/30 Hz desktop drags
// the UI down with it. 0 when no rate is within tolerance.
inline uint32_t FindBestRefreshRate(double video_fps, const std::vector<uint32_t>& rates) {
  if (!(video_fps > 0.0)) return 0;
  const RateMatch own = LowestMultiple(video_fps, rates);
  if (video_fps >= kHalfRateMinFps && video_fps <= kHalfRateMaxFps) {
    const RateMatch doubled = LowestMultiple(video_fps * 2.0, rates);
    if (doubled.rate != 0 && (own.rate == 0 || doubled.deviation - own.deviation < kPreciseDeviation)) {
      return doubled.rate;
    }
  }
  return own.rate;
}

}  // namespace refresh_rate_match
