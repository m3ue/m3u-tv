#include "angle_surface_manager.h"

#include <d3dcommon.h>

#include <array>

int32_t ANGLESurfaceManager::instance_count_ = 0;

ANGLESurfaceManager::ANGLESurfaceManager(int32_t width, int32_t height)
    : width_(width), height_(height) {
  mutex_ = ::CreateMutexW(nullptr, FALSE, nullptr);
  valid_ = CreateD3DTextures() && CreateEGLDisplay() &&
           CreateAndBindEGLSurface() && internal_handle_ != nullptr &&
           handle_ != nullptr;
  if (valid_) {
    ++instance_count_;
  }
}

ANGLESurfaceManager::~ANGLESurfaceManager() {
  if (display_ != EGL_NO_DISPLAY && surface_ != EGL_NO_SURFACE) {
    eglReleaseTexImage(display_, surface_, EGL_BACK_BUFFER);
  }
  if (display_ != EGL_NO_DISPLAY && context_ != EGL_NO_CONTEXT) {
    eglDestroyContext(display_, context_);
    context_ = EGL_NO_CONTEXT;
  }
  if (display_ != EGL_NO_DISPLAY && surface_ != EGL_NO_SURFACE) {
    eglDestroySurface(display_, surface_);
    surface_ = EGL_NO_SURFACE;
  }
  if (valid_ && instance_count_ > 0) {
    --instance_count_;
    if (instance_count_ == 0 && display_ != EGL_NO_DISPLAY) {
      eglTerminate(display_);
    }
  }
  display_ = EGL_NO_DISPLAY;

  internal_d3d_11_texture_2d_.Reset();
  d3d_11_texture_2d_.Reset();

  if (d3d_11_device_context_ != nullptr) {
    d3d_11_device_context_->Release();
    d3d_11_device_context_ = nullptr;
  }
  if (d3d_11_device_ != nullptr) {
    d3d_11_device_->Release();
    d3d_11_device_ = nullptr;
  }
  if (mutex_ != nullptr) {
    ::CloseHandle(mutex_);
    mutex_ = nullptr;
  }
}

void ANGLESurfaceManager::MakeCurrent(bool current) {
  if (current) {
    eglMakeCurrent(display_, surface_, surface_, context_);
  } else {
    eglMakeCurrent(display_, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
  }
}

void ANGLESurfaceManager::SwapBuffers() { glFinish(); }

void ANGLESurfaceManager::Draw(const std::function<void()>& callback) {
  ::WaitForSingleObject(mutex_, INFINITE);
  MakeCurrent(true);
  callback();
  SwapBuffers();
  MakeCurrent(false);
  ::ReleaseMutex(mutex_);
}

void ANGLESurfaceManager::Read() {
  ::WaitForSingleObject(mutex_, INFINITE);
  if (d3d_11_device_context_ != nullptr) {
    d3d_11_device_context_->CopyResource(d3d_11_texture_2d_.Get(),
                                         internal_d3d_11_texture_2d_.Get());
    d3d_11_device_context_->Flush();
  }
  ::ReleaseMutex(mutex_);
}

bool ANGLESurfaceManager::CreateD3DDevice() {
  if (d3d_11_device_ != nullptr) return true;
  // Flutter's own Windows desktop support already requires Windows 10, so
  // (unlike the media_kit reference, which also supported Windows 7/8 via a
  // manual adapter-enumeration fallback) this always requests hardware
  // adapter auto-selection.
  const D3D_FEATURE_LEVEL feature_levels[] = {
      D3D_FEATURE_LEVEL_11_0,
      D3D_FEATURE_LEVEL_10_1,
      D3D_FEATURE_LEVEL_10_0,
      D3D_FEATURE_LEVEL_9_3,
  };
  const HRESULT hr = ::D3D11CreateDevice(
      nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, 0, feature_levels,
      static_cast<UINT>(std::size(feature_levels)), D3D11_SDK_VERSION,
      &d3d_11_device_, nullptr, &d3d_11_device_context_);
  if (FAILED(hr)) return false;

  Microsoft::WRL::ComPtr<IDXGIDevice> dxgi_device;
  if (SUCCEEDED(d3d_11_device_->QueryInterface(__uuidof(IDXGIDevice),
                                               reinterpret_cast<void**>(dxgi_device.GetAddressOf())))) {
    dxgi_device->SetGPUThreadPriority(5);  // Must be in [-7, 7].
  }
  return true;
}

bool ANGLESurfaceManager::CreateD3DTextures() {
  if (!CreateD3DDevice()) return false;

  D3D11_TEXTURE2D_DESC desc = {};
  desc.Width = static_cast<UINT>(width_);
  desc.Height = static_cast<UINT>(height_);
  desc.MipLevels = 1;
  desc.ArraySize = 1;
  desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
  desc.SampleDesc.Count = 1;
  desc.SampleDesc.Quality = 0;
  desc.Usage = D3D11_USAGE_DEFAULT;
  desc.BindFlags = D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE;
  desc.CPUAccessFlags = 0;
  desc.MiscFlags = D3D11_RESOURCE_MISC_SHARED;

  // Two textures: an "internal" one mpv/ANGLE draws into, and an
  // "external" one Read() copies into right before Flutter opens its
  // shared handle -- see the class comment in angle_surface_manager.h.
  Microsoft::WRL::ComPtr<IDXGIResource> resource;

  if (FAILED(d3d_11_device_->CreateTexture2D(&desc, nullptr, &internal_d3d_11_texture_2d_))) {
    return false;
  }
  if (FAILED(internal_d3d_11_texture_2d_.As(&resource))) return false;
  if (FAILED(resource->GetSharedHandle(&internal_handle_))) return false;

  if (FAILED(d3d_11_device_->CreateTexture2D(&desc, nullptr, &d3d_11_texture_2d_))) {
    return false;
  }
  if (FAILED(d3d_11_texture_2d_.As(&resource))) return false;
  if (FAILED(resource->GetSharedHandle(&handle_))) return false;

  return true;
}

bool ANGLESurfaceManager::CreateEGLDisplay() {
  auto eglGetPlatformDisplayEXT = reinterpret_cast<PFNEGLGETPLATFORMDISPLAYEXTPROC>(
      eglGetProcAddress("eglGetPlatformDisplayEXT"));
  if (eglGetPlatformDisplayEXT == nullptr) return false;

  const EGLint* attribute_tiers[] = {
      kD3D11DisplayAttributes,
      kD3D11FL93DisplayAttributes,
      kD3D9DisplayAttributes,
  };
  for (const EGLint* attributes : attribute_tiers) {
    display_ = eglGetPlatformDisplayEXT(EGL_PLATFORM_ANGLE_ANGLE,
                                        EGL_DEFAULT_DISPLAY, attributes);
    if (display_ != EGL_NO_DISPLAY &&
        eglInitialize(display_, nullptr, nullptr) == EGL_TRUE) {
      return true;
    }
  }
  display_ = EGL_NO_DISPLAY;
  return false;
}

bool ANGLESurfaceManager::CreateAndBindEGLSurface() {
  if (context_ == EGL_NO_CONTEXT) {
    EGLint config_count = 0;
    if (eglChooseConfig(display_, kEGLConfigurationAttributes, &config_, 1,
                        &config_count) == EGL_FALSE ||
        config_count == 0) {
      return false;
    }
    context_ = eglCreateContext(display_, config_, EGL_NO_CONTEXT,
                                kEGLContextAttributes);
    if (context_ == EGL_NO_CONTEXT) return false;
  }

  const EGLint buffer_attributes[] = {
      EGL_WIDTH,          width_,         EGL_HEIGHT,         height_,
      EGL_TEXTURE_TARGET, EGL_TEXTURE_2D, EGL_TEXTURE_FORMAT, EGL_TEXTURE_RGBA,
      EGL_NONE,
  };
  surface_ = eglCreatePbufferFromClientBuffer(
      display_, EGL_D3D_TEXTURE_2D_SHARE_HANDLE_ANGLE, internal_handle_,
      config_, buffer_attributes);
  if (surface_ == EGL_NO_SURFACE) return false;

  // Binds the pbuffer surface as a GL texture. Ported as-is from the
  // media_kit/Flutter engine reference; the generated texture name itself is
  // discarded (not read elsewhere) -- this call's effect on `surface_`
  // itself, not the returned texture object, is what subsequent rendering
  // via MakeCurrent(true)+FBO 0 relies on.
  GLuint texture = 0;
  glGenTextures(1, &texture);
  glBindTexture(GL_TEXTURE_2D, texture);
  eglBindTexImage(display_, surface_, EGL_BACK_BUFFER);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
  return true;
}
