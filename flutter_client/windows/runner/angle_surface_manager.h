#ifndef ANGLE_SURFACE_MANAGER_H_
#define ANGLE_SURFACE_MANAGER_H_

#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <EGL/eglplatform.h>
#include <GLES2/gl2.h>
#include <GLES2/gl2ext.h>

#include <windows.h>

#include <d3d11.h>
#include <dxgi.h>
#include <wrl/client.h>

#include <cstdint>
#include <functional>

// Bridges mpv's OpenGL render API to a D3D11 texture that Flutter can
// display via FlutterDesktopGpuSurfaceTexture
// (kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle), using ANGLE (Google's
// GL-to-D3D11 translation layer) as the bridge. This is the real GPU-texture
// replacement for the native-child-window GPU path that turned out to be a
// confirmed dead end on stock Flutter (see the large comment on
// CreateGpuVideoWindow in desktop_libmpv_backend.cpp) -- it stays entirely
// inside Flutter's own proven texture compositing instead of a sibling
// window.
//
// Adapted from the (fully removed from this project, see
// docs/release/platform-release-matrix.md) media_kit_video package's own
// Windows implementation
// (media_kit_video-2.0.1/windows/angle_surface_manager.{h,cc}, MIT
// licensed), itself adapted from the Flutter engine's own
// shell/platform/windows/angle_surface_manager.h. Unlike both of those
// references, this project builds with exceptions disabled
// (_HAS_EXCEPTIONS=0, see the top-level windows/CMakeLists.txt), so failures
// are reported via IsValid()/bool returns instead of throwing.
//
// Two D3D11 textures are used deliberately, not one: an "internal" texture
// that mpv/ANGLE draws into (bound as the EGL surface's backing store) and
// an "external" texture that Read() copies the internal one into right
// before Flutter opens its shared handle. This avoids any need to
// synchronize GL rendering against Flutter's raster thread reading the same
// texture mid-draw.
class ANGLESurfaceManager {
 public:
  // `width`/`height` are fixed for the lifetime of the instance -- unlike
  // the media_kit reference, this project's SW pixel-buffer path already
  // renders into a fixed-size buffer (kTextureWidth/kTextureHeight in
  // desktop_libmpv_backend.cpp) and lets mpv's own scaler letterbox into it,
  // so this path does the same rather than adding dynamic-resize plumbing
  // this project has no equivalent of on any other backend.
  ANGLESurfaceManager(int32_t width, int32_t height);
  ~ANGLESurfaceManager();

  ANGLESurfaceManager(const ANGLESurfaceManager&) = delete;
  ANGLESurfaceManager& operator=(const ANGLESurfaceManager&) = delete;

  // False if ANGLE/D3D11 initialization failed anywhere along the way (no
  // suitable GPU/driver, EGL extension missing, etc). The caller must not
  // use any other method on an invalid instance, and should fall back to
  // the SW pixel-buffer path instead -- this is a real runtime capability
  // check, not something knowable ahead of time on unseen hardware.
  bool IsValid() const { return valid_; }

  int32_t width() const { return width_; }
  int32_t height() const { return height_; }
  // Shared HANDLE for the *external* (published) D3D11 texture, passed as
  // FlutterDesktopGpuSurfaceDescriptor::handle.
  HANDLE handle() const { return handle_; }

  // Makes the ANGLE/EGL context current on the calling thread if `current`
  // is true, or releases it if false. Exposed publicly (not just used
  // internally by Draw()) because mpv's OpenGL-backed render context must
  // also have this context current when it is freed (render.h: "if the
  // OpenGL backend is used, for all functions the OpenGL context must be
  // current") -- see TextureReleaseContext::Release in
  // desktop_libmpv_backend.cpp.
  void MakeCurrent(bool current);

  // Makes the context current, runs `callback` (issue GL/mpv render calls
  // here, targeting FBO 0 -- the pbuffer surface bound in the constructor
  // serves as the default framebuffer), flushes, then releases the
  // context. Guarded by an internal mutex so concurrent Draw/Read calls
  // (e.g. from Flutter's raster thread via the GpuSurfaceTexture callback)
  // never overlap.
  void Draw(const std::function<void()>& callback);

  // Copies the internal (drawn-into) texture to the external (published)
  // texture. Call this right before returning the FlutterDesktopGpuSurfaceDescriptor
  // from a GpuSurfaceTexture callback, so Flutter always reads a complete
  // frame rather than one mpv/ANGLE is still drawing.
  void Read();

 private:
  void SwapBuffers();
  bool CreateD3DDevice();
  bool CreateD3DTextures();
  bool CreateEGLDisplay();
  bool CreateAndBindEGLSurface();

  int32_t width_ = 1;
  int32_t height_ = 1;
  bool valid_ = false;

  // Guards Draw()/Read() against overlapping (e.g. mpv's render thread vs.
  // Flutter's raster thread), same purpose as media_kit's reference.
  HANDLE mutex_ = nullptr;

  HANDLE internal_handle_ = nullptr;
  HANDLE handle_ = nullptr;

  ID3D11Device* d3d_11_device_ = nullptr;
  ID3D11DeviceContext* d3d_11_device_context_ = nullptr;
  Microsoft::WRL::ComPtr<ID3D11Texture2D> internal_d3d_11_texture_2d_;
  Microsoft::WRL::ComPtr<ID3D11Texture2D> d3d_11_texture_2d_;

  EGLSurface surface_ = EGL_NO_SURFACE;
  EGLDisplay display_ = EGL_NO_DISPLAY;
  EGLContext context_ = EGL_NO_CONTEXT;
  EGLConfig config_ = nullptr;

  // Tracks live instances so the shared EGLDisplay is only eglTerminate()'d
  // once the last one goes away -- matches the media_kit reference and the
  // Flutter engine's own angle_surface_manager.h, both of which treat the
  // platform display as process-wide.
  static int32_t instance_count_;

  static constexpr EGLint kEGLConfigurationAttributes[] = {
      EGL_RED_SIZE,   8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE,    8,
      EGL_ALPHA_SIZE, 8, EGL_DEPTH_SIZE, 8, EGL_STENCIL_SIZE, 8,
      EGL_NONE,
  };
  static constexpr EGLint kEGLContextAttributes[] = {
      EGL_CONTEXT_CLIENT_VERSION,
      2,
      EGL_NONE,
  };
  // Three fallback tiers, tried in order by CreateEGLDisplay: full D3D11,
  // D3D11 Feature Level 9_3 (older/lower-end GPUs), then D3D9. Matches the
  // media_kit/Flutter engine reference exactly.
  static constexpr EGLint kD3D11DisplayAttributes[] = {
      EGL_PLATFORM_ANGLE_TYPE_ANGLE,
      EGL_PLATFORM_ANGLE_TYPE_D3D11_ANGLE,
      EGL_PLATFORM_ANGLE_ENABLE_AUTOMATIC_TRIM_ANGLE,
      EGL_TRUE,
      EGL_NONE,
  };
  static constexpr EGLint kD3D11FL93DisplayAttributes[] = {
      EGL_PLATFORM_ANGLE_TYPE_ANGLE,
      EGL_PLATFORM_ANGLE_TYPE_D3D11_ANGLE,
      EGL_PLATFORM_ANGLE_MAX_VERSION_MAJOR_ANGLE,
      9,
      EGL_PLATFORM_ANGLE_MAX_VERSION_MINOR_ANGLE,
      3,
      EGL_PLATFORM_ANGLE_ENABLE_AUTOMATIC_TRIM_ANGLE,
      EGL_TRUE,
      EGL_NONE,
  };
  static constexpr EGLint kD3D9DisplayAttributes[] = {
      EGL_PLATFORM_ANGLE_TYPE_ANGLE,
      EGL_PLATFORM_ANGLE_TYPE_D3D9_ANGLE,
      EGL_PLATFORM_ANGLE_DEVICE_TYPE_ANGLE,
      EGL_PLATFORM_ANGLE_DEVICE_TYPE_HARDWARE_ANGLE,
      EGL_NONE,
  };
};

#endif  // ANGLE_SURFACE_MANAGER_H_
