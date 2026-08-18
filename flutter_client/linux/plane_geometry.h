#ifndef FLUTTER_CLIENT_LINUX_PLANE_GEOMETRY_H_
#define FLUTTER_CLIENT_LINUX_PLANE_GEOMETRY_H_

#include <cstdint>
#include <limits>

// How large the video plane's buffer is and where its subsurface sits, given
// the rect Flutter cut out for it and the output's buffer scale.
//
// Ported near-verbatim from the open-source Plezy player
// (github.com/edde746/plezy, GPL-3.0, linux/runner/mpv/plane_geometry.h):
// both rules bias the plane *outward* on purpose -- an undersized plane shows
// the desktop through the seam, and a buffer size that is not a whole
// multiple of the buffer scale is a fatal Wayland protocol error that
// disconnects the client. Header-only, pure functions over int32, no
// dependencies.

namespace m3u_tv_mpv_plane {

// The buffer scale to actually divide and round by. Anything below 1 is not
// a scale (0 divides by zero, negative inflates instead of shrinking), so 1
// is the safe floor.
inline int32_t NormalizePlaneScale(int32_t scale) { return scale < 1 ? 1 : scale; }

// Where one axis of the plane starts, in whole surface-local units. Floors
// rather than truncates so a negative origin (a video rect scrolled partly
// off the left/top) biases the plane outward the same way the extent below
// does.
inline int32_t PlaneOriginUnits(int32_t position, int32_t scale) {
  const int32_t divisor = NormalizePlaneScale(scale);
  const int32_t quotient = position / divisor;
  return (position % divisor != 0 && position < 0) ? quotient - 1 : quotient;
}

// One dimension of the plane's buffer, in physical pixels, for the rect
// [position, position + extent). Measured from the floored origin, not from
// the extent alone -- flooring the origin moves the near edge outward but
// does nothing for the far edge, so the far edge is separately taken to the
// next whole unit. The buffer size must be an integer multiple of the
// buffer scale or wl_surface.commit raises a fatal invalid_size error.
inline int32_t PlaneBufferExtent(int32_t position, int32_t extent, int32_t scale) {
  const int64_t block = NormalizePlaneScale(scale);
  const int64_t start = PlaneOriginUnits(position, scale);
  const int64_t far = static_cast<int64_t>(position) + extent;
  const int64_t end = far >= 0 ? (far + block - 1) / block : -((-far) / block);
  int64_t span = (end - start) * block;
  if (span < block) span = block;
  const int64_t cap = (static_cast<int64_t>(std::numeric_limits<int32_t>::max()) / block) * block;
  if (span > cap) span = cap;
  return static_cast<int32_t>(span);
}

// One axis of the subsurface's position, in the toplevel's surface-local
// frame. `view_offset` is where the FlView sits inside the toplevel (non-zero
// under client-side decorations) and is added after the divide because GTK
// widget coordinates are already logical units, the same frame
// wl_subsurface_set_position expects. Summed in 64 bits and clamped: the
// position is an int32 cast of an unvalidated channel argument.
inline int32_t PlaneSurfacePosition(int32_t position, int32_t scale, int32_t view_offset) {
  const int64_t sum = static_cast<int64_t>(PlaneOriginUnits(position, scale)) + view_offset;
  constexpr int64_t kMin = std::numeric_limits<int32_t>::min();
  constexpr int64_t kMax = std::numeric_limits<int32_t>::max();
  return static_cast<int32_t>(sum < kMin ? kMin : (sum > kMax ? kMax : sum));
}

}  // namespace m3u_tv_mpv_plane

#endif  // FLUTTER_CLIENT_LINUX_PLANE_GEOMETRY_H_
