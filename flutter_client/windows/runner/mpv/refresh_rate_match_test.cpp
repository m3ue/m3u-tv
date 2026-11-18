// Host test for refresh_rate_match.h. Not part of the Windows runner build:
// the header has no Windows dependencies, so CI compiles and runs this on
// Linux.
//
//   clang++ -std=c++17 -Wall -Werror -I windows/runner/mpv \
//     windows/runner/mpv/refresh_rate_match_test.cpp -o refresh_rate_match_test
//   ./refresh_rate_match_test

#include "refresh_rate_match.h"

#include <cstdio>

using refresh_rate_match::FindBestRefreshRate;

namespace {

int failures = 0;

void Expect(const char* name, uint32_t actual, uint32_t expected) {
  if (actual == expected) return;
  std::printf("FAIL %s: got %u, want %u\n", name, actual, expected);
  ++failures;
}

constexpr double kNtsc24 = 24000.0 / 1001.0;
constexpr double kNtsc30 = 30000.0 / 1001.0;
constexpr double kNtsc60 = 60000.0 / 1001.0;

}  // namespace

int main() {
  // Film and other rates: lowest multiple, closest first.
  Expect("23.976 takes 23 over 24", FindBestRefreshRate(kNtsc24, {23, 24, 47, 60}), 23);
  Expect("24 is not doubled", FindBestRefreshRate(24.0, {24, 48, 60}), 24);
  Expect("59.94 takes 59", FindBestRefreshRate(kNtsc60, {59, 60}), 59);
  Expect("no clean multiple", FindBestRefreshRate(23.976, {50, 60}), 0);
  Expect("non-positive fps", FindBestRefreshRate(0.0, {60}), 0);

  // 25/30 fps class.
  Expect("25 takes 50 over 25", FindBestRefreshRate(25.0, {60, 50, 25}, 60), 50);
  Expect("29.97 takes 59 over 60 and 29", FindBestRefreshRate(kNtsc30, {60, 59, 29}, 60), 59);
  Expect("29.97 keeps 29 without a 59", FindBestRefreshRate(kNtsc30, {60, 29}, 60), 29);
  Expect("30 takes 60 over 30 and 120", FindBestRefreshRate(30.0, {30, 60, 120}, 30), 60);
  Expect("30 keeps an active 120", FindBestRefreshRate(30.0, {60, 120}, 120), 120);
  Expect("25 keeps an active 100", FindBestRefreshRate(25.0, {50, 100}, 100), 100);
  Expect("25 takes 25 over 100 without a 50", FindBestRefreshRate(25.0, {60, 25, 100}, 60), 25);
  Expect("25 falls back to 25", FindBestRefreshRate(25.0, {60, 25}, 60), 25);
  Expect("current rate unknown", FindBestRefreshRate(30.0, {60, 120}), 60);

  if (failures == 0) std::printf("refresh_rate_match: all tests passed\n");
  return failures == 0 ? 0 : 1;
}
