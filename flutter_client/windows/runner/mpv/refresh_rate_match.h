#pragma once

// Refresh-rate selection for DisplayModeManager::MatchRefreshRate. Kept free
// of Windows headers so it can be compiled and tested on any host. Ported from
// Plezy's DisplayModeService.findBestRefreshRate (github.com/edde746/plezy,
// GPL-3.0).

#include <cmath>
#include <cstdint>
#include <limits>
#include <tuple>
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
  int multiplier = 0;
  double deviation = 0.0;
};

// Whether `rate` presents `video_fps` as a whole multiple within 0.5%, and
// how: the multiplier and the relative deviation from it.
inline bool MatchRate(double video_fps, uint32_t rate, RateMatch* match) {
  if (rate == 0) return false;
  const double ratio = EffectiveRefreshRate(rate) / video_fps;
  const double rounded = std::round(ratio);
  if (rounded < 1.0) return false;
  const double deviation = std::fabs(ratio - rounded) / rounded;
  if (deviation > 0.005) return false;
  *match = {rate, static_cast<int>(rounded), deviation};
  return true;
}

// 25 and 29.97/30 fps-class content, which a 50/60 Hz mode shows at exactly
// twice its rate.
constexpr double kHalfRateMinFps = 24.5;
constexpr double kHalfRateMaxFps = 30.5;

// Relative rate error below which two matches count as equally precise: above
// the rounding in reported rates, below the 0.1% NTSC mismatch.
constexpr double kPreciseDeviation = 0.0002;

// The best of `rates` (whole-hertz values as Windows reports them) for
// `video_fps`, or 0 when no rate is a whole multiple of it within 0.5%.
//
// Generally the lowest multiple, and of those the closest, so 23.976 fps
// content takes a 23 (23.976) Hz mode over 24 Hz and an exact rate beats any
// multiple.
//
// 25 and 30 fps-class content ranks as the Android DisplayModeSelector does:
// a precise match first, then `current_rate` when it already shows the
// content as a multiple (a 120 Hz desktop keeps 30 fps at 4:4), then 2x
// (50/60 Hz, 2:2 with no judder, where a 25/30 Hz desktop drags the UI down
// with it), then the content's own rate, then any other multiple. So a 29.97
// fps file takes 59.94 Hz over 60 Hz, and a display with 25 and 100 Hz but no
// 50 Hz takes 25 Hz.
inline uint32_t FindBestRefreshRate(double video_fps, const std::vector<uint32_t>& rates,
                                    uint32_t current_rate = 0) {
  if (!(video_fps > 0.0)) return 0;
  const bool half_rate = video_fps >= kHalfRateMinFps && video_fps <= kHalfRateMaxFps;

  std::vector<RateMatch> matches;
  double best_deviation = std::numeric_limits<double>::infinity();
  for (const uint32_t rate : rates) {
    RateMatch match;
    if (!MatchRate(video_fps, rate, &match)) continue;
    matches.push_back(match);
    if (match.deviation < best_deviation) best_deviation = match.deviation;
  }

  const auto tier = [&](const RateMatch& match) {
    if (!half_rate) return 0;
    if (match.rate == current_rate && match.multiplier >= 2) return 0;
    if (match.multiplier == 2) return 1;
    if (match.multiplier == 1) return 2;
    return 3;
  };
  const auto rank = [&](const RateMatch& match) {
    const bool imprecise = half_rate && match.deviation - best_deviation >= kPreciseDeviation;
    // Higher rate last breaks an exact tie toward the faster mode.
    return std::make_tuple(imprecise, tier(match), match.multiplier, match.deviation,
                           -static_cast<int64_t>(match.rate));
  };

  const RateMatch* best = nullptr;
  for (const RateMatch& match : matches) {
    if (best == nullptr || rank(match) < rank(*best)) best = &match;
  }
  return best == nullptr ? 0 : best->rate;
}

}  // namespace refresh_rate_match
