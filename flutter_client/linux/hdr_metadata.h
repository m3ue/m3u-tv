#ifndef FLUTTER_CLIENT_LINUX_HDR_METADATA_H_
#define FLUTTER_CLIENT_LINUX_HDR_METADATA_H_

#include <cstdint>

// Source HDR10 static metadata, and the rules for turning it into a set of
// color-management-v1 luminance requests the compositor will accept.
//
// Adapted near-verbatim from the open-source Plezy player's `hdr_metadata.h`
// (github.com/edde746/plezy, GPL-3.0, linux/runner/mpv/hdr_metadata.h).
//
// This header is deliberately free of Wayland and GTK: the interesting logic
// is the validation, the penalty for getting it wrong is severe (a bad
// luminance request is a *protocol error* on create(), which disconnects the
// whole client, not just a failed HDR description), and neither deserves a
// display server to test. Header-only and pure-functional so it can be
// reasoned about (and, in a project with C++ test infrastructure, unit
// tested) without a compositor.

namespace m3u_tv_mpv_plane {

// The source's transfer function, so far as describing the plane cares. Every
// SDR curve collapses to kSdr: the plane is then left undescribed and mpv's
// normal output is already right, so there is nothing to distinguish.
enum class SourceTransfer { kSdr, kPq, kHlg };

// The source's container primaries. Only BT.2020 has a named counterpart
// worth describing for video; everything else is treated as "not a wide
// gamut" and leaves the plane undescribed.
enum class SourcePrimaries { kOther, kBt2020 };

// What the current source actually is, plus its HDR10 static metadata, as
// reported by mpv's video-params. A zero luminance field means the source did
// not carry it.
struct HdrMetadata {
  SourceTransfer transfer = SourceTransfer::kSdr;
  SourcePrimaries primaries = SourcePrimaries::kOther;
  uint32_t max_cll = 0;        // nits, maximum content light level
  uint32_t max_fall = 0;       // nits, maximum frame-average light level
  uint32_t max_luminance = 0;  // nits, mastering display maximum
  double min_luminance = 0.0;  // nits, mastering display minimum
};

inline bool operator==(const HdrMetadata& a, const HdrMetadata& b) {
  return a.transfer == b.transfer && a.primaries == b.primaries && a.max_cll == b.max_cll &&
         a.max_fall == b.max_fall && a.max_luminance == b.max_luminance && a.min_luminance == b.min_luminance;
}

inline bool operator!=(const HdrMetadata& a, const HdrMetadata& b) { return !(a == b); }

// True when the source carries an HDR transfer function, i.e. when there is
// anything to pass through at all.
inline bool SourceIsHdr(const HdrMetadata& metadata) { return metadata.transfer != SourceTransfer::kSdr; }

// Who reduces the source's dynamic range to what the display can show.
enum class HdrToneMapping { kCompositor, kPlayer };

// The primary color volume maxima the protocol attaches to each named
// transfer function. PQ's EOTF swings to 10000 cd/m2, while HLG is a
// *relative* signal whose absolute luminances are all defined against a 1000
// cd/m2 peak display.
constexpr uint32_t kPqMaxLuminanceNits = 10000;
constexpr uint32_t kHlgMaxLuminanceNits = 1000;

// The protocol carries the mastering minimum scaled by this to keep four
// decimals of a value that is normally a small fraction of a nit.
constexpr uint32_t kMinLuminanceScale = 10000;

// Both PQ and HLG declare the same primary color volume floor, 0.005 cd/m2,
// already in the protocol's scaled units.
constexpr uint32_t kPrimaryVolumeMinScaled = 50;

inline uint32_t PrimaryVolumeMaxNits(SourceTransfer transfer) {
  switch (transfer) {
    case SourceTransfer::kHlg:
      return kHlgMaxLuminanceNits;
    case SourceTransfer::kPq:
    case SourceTransfer::kSdr:
      break;
  }
  return kPqMaxLuminanceNits;
}

// What the compositor told us it can accept, which decides how much of the
// source's metadata may legally be forwarded.
struct CompositorLuminanceSupport {
  // feature.set_mastering_display_primaries. Without it, set_mastering_luminance
  // raises unsupported_feature.
  bool mastering = false;
  // feature.extended_target_volume. Without it, the mastering advertisement
  // only promises target volumes fully contained within the primary color
  // volume.
  bool extended_target_volume = false;
  uint32_t interface_version = 1;
};

// Which luminance requests to actually emit. A false flag means the field is
// left unset so the compositor applies its own default.
struct HdrLuminancePlan {
  bool send_mastering = false;
  uint32_t mastering_min_scaled = 0;
  uint32_t mastering_max = 0;
  bool send_max_cll = false;
  uint32_t max_cll = 0;
  bool send_max_fall = false;
  uint32_t max_fall = 0;
};

inline uint32_t ScaleMinLuminance(double nits) {
  if (!(nits > 0.0)) return 0;
  const double scaled = nits * static_cast<double>(kMinLuminanceScale) + 0.5;
  if (scaled >= static_cast<double>(UINT32_MAX)) return UINT32_MAX;
  return static_cast<uint32_t>(scaled);
}

inline bool LuminanceInMasteringRange(uint32_t value_nits, uint32_t min_lum_scaled, uint32_t max_lum_nits) {
  if (value_nits > max_lum_nits) return false;
  return static_cast<uint64_t>(value_nits) * kMinLuminanceScale > min_lum_scaled;
}

// Decides which of set_mastering_luminance / set_max_cll / set_max_fall may
// be sent for `metadata`, given what the compositor advertised. Every
// constraint enforced here is a protocol error on create(), not a failed
// image description, so badly authored HDR content (a MaxCLL above the
// mastering display's own peak is common) is never trusted blindly.
inline HdrLuminancePlan PlanHdrLuminance(const HdrMetadata& metadata, const CompositorLuminanceSupport& support) {
  HdrLuminancePlan plan;

  const uint32_t volume_max = PrimaryVolumeMaxNits(metadata.transfer);

  const uint32_t mastering_ceiling = support.extended_target_volume ? kPqMaxLuminanceNits : volume_max;
  const uint32_t mastering_floor_scaled = support.extended_target_volume ? 0 : kPrimaryVolumeMinScaled;
  uint32_t mastering_max = metadata.max_luminance;
  if (mastering_max > mastering_ceiling) mastering_max = mastering_ceiling;
  uint32_t mastering_min_scaled = ScaleMinLuminance(metadata.min_luminance);
  if (mastering_min_scaled < mastering_floor_scaled) mastering_min_scaled = mastering_floor_scaled;
  if (support.mastering && mastering_max > 0 &&
      static_cast<uint64_t>(mastering_max) * kMinLuminanceScale > mastering_min_scaled) {
    plan.send_mastering = true;
    plan.mastering_min_scaled = mastering_min_scaled;
    plan.mastering_max = mastering_max;
  }

  plan.send_max_cll = metadata.max_cll > 0;
  plan.max_cll = metadata.max_cll;
  plan.send_max_fall = metadata.max_fall > 0;
  plan.max_fall = metadata.max_fall;

  const uint32_t range_max = plan.send_mastering ? plan.mastering_max : volume_max;
  const uint32_t range_min_scaled = plan.send_mastering ? plan.mastering_min_scaled : 0;

  if (plan.send_max_cll && plan.max_cll > volume_max) plan.send_max_cll = false;
  if (plan.send_max_fall && plan.max_fall > volume_max) plan.send_max_fall = false;

  if (support.interface_version < 2) {
    if (plan.send_max_cll && !LuminanceInMasteringRange(plan.max_cll, range_min_scaled, range_max)) {
      plan.send_max_cll = false;
    }
    if (plan.send_max_fall && !LuminanceInMasteringRange(plan.max_fall, range_min_scaled, range_max)) {
      plan.send_max_fall = false;
    }
  }

  if (plan.send_max_cll && plan.send_max_fall && plan.max_fall > plan.max_cll) {
    plan.send_max_fall = false;
  }
  return plan;
}

// Rewrites the metadata to describe a signal *we* tone-mapped to `peak_nits`,
// rather than the source's original range.
inline HdrMetadata DescribeTonemappedTo(const HdrMetadata& source, uint32_t peak_nits) {
  HdrMetadata described = source;
  if (peak_nits == 0) return described;
  const uint32_t volume_max = PrimaryVolumeMaxNits(source.transfer);
  if (peak_nits > volume_max) peak_nits = volume_max;
  described.max_luminance = peak_nits;
  described.max_cll = peak_nits;
  described.max_fall = (source.max_fall > 0 && source.max_fall <= peak_nits) ? source.max_fall : 0;
  return described;
}

// Whether an output's reported luminances leave enough room above its own
// diffuse white to be worth passing HDR through instead of tone-mapping here.
// Headroom describes the panel rather than the encoding, which is why this is
// used instead of any single "is HDR on" signal (color-management-v1 has
// none). The half-stop margin (2*max >= 3*reference) rejects the case where
// an SDR output's own dimmed-white-vs-undimmed-max gap would otherwise read
// as false headroom.
inline bool OutputHasHdrHeadroom(uint32_t max_luminance, uint32_t reference_luminance) {
  if (reference_luminance == 0) return false;
  return static_cast<uint64_t>(max_luminance) * 2 >= static_cast<uint64_t>(reference_luminance) * 3;
}

// What the compositor advertised it will accept, as named curves and primaries.
struct CompositorColorSupport {
  bool bt2020 = false;
  bool pq = false;
  bool hlg = false;
};

// Whether this source can be described to the compositor at all. Naming a
// curve the compositor never advertised is a fatal invalid_tf on create(),
// which disconnects the whole client rather than failing the description.
inline bool SourceIsDescribable(const HdrMetadata& metadata, const CompositorColorSupport& support) {
  if (!SourceIsHdr(metadata)) return false;
  if (metadata.primaries != SourcePrimaries::kBt2020 || !support.bt2020) return false;
  switch (metadata.transfer) {
    case SourceTransfer::kPq:
      return support.pq;
    case SourceTransfer::kHlg:
      return support.hlg;
    case SourceTransfer::kSdr:
      break;
  }
  return false;
}

// Everything outside the source that bears on whether the plane carries HDR.
struct HdrInputs {
  bool allowed = false;              // the app's permission
  bool client_can_describe = false;  // deep-color plane, color-managed surface, advertised curve
  bool output_is_hdr = false;        // the output offers headroom above reference white
  bool source_describable = false;   // this source's curve and gamut are both advertised
  HdrToneMapping requested = HdrToneMapping::kCompositor;
  uint32_t display_peak_nits = 0;     // the output's peak while in HDR; 0 means unknown
  uint32_t sdr_reference_nits = 0;    // the output's diffuse-white luminance; 0 means unknown
};

// What to do about it.
struct HdrDecision {
  bool describe = false;            // attach an image description at all
  bool tone_map_in_player = false;  // mpv reduces the range rather than the compositor
  uint32_t target_peak_nits = 0;    // the peak mpv aims at; 0 means target-peak stays on auto
};

// mpv's target-peak option accepts 10..10000; outside that there is nothing
// sensible to aim at and auto is the honest answer.
inline uint32_t UsableTargetPeak(uint32_t nits, uint32_t volume_max) {
  if (nits > volume_max) nits = volume_max;
  return nits >= 10 ? nits : 0;
}

// The single gate. Four independent conditions must hold before a plane is
// described as HDR: the user's/app's setting, the compositor's advertised
// capabilities, the output's current state, and the file. Any one failing
// falls back to mpv's ordinary tone-mapped SDR output, which is always safe.
inline HdrDecision DecideHdr(const HdrInputs& inputs, const HdrMetadata& source) {
  HdrDecision decision;
  decision.describe = inputs.allowed && inputs.client_can_describe && inputs.output_is_hdr &&
                      inputs.source_describable && SourceIsHdr(source);
  if (!decision.describe) {
    if (SourceIsHdr(source)) {
      decision.target_peak_nits = UsableTargetPeak(inputs.sdr_reference_nits, kPqMaxLuminanceNits);
      decision.tone_map_in_player = decision.target_peak_nits > 0;
    }
    return decision;
  }

  if (inputs.requested == HdrToneMapping::kPlayer && inputs.display_peak_nits > 0) {
    const uint32_t peak = UsableTargetPeak(inputs.display_peak_nits, PrimaryVolumeMaxNits(source.transfer));
    if (peak > 0) {
      decision.tone_map_in_player = true;
      decision.target_peak_nits = peak;
    }
  }
  return decision;
}

}  // namespace m3u_tv_mpv_plane

#endif  // FLUTTER_CLIENT_LINUX_HDR_METADATA_H_
