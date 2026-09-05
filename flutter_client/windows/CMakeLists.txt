# Project-level configuration.
cmake_minimum_required(VERSION 3.14)
project(m3u_tv LANGUAGES CXX)

# The name of the executable created for the application. Change this to change
# the on-disk name of your application.
set(BINARY_NAME "m3u_tv")

# gpu-next/D3D11-capable libmpv, fetched from our unified build repository
# (https://github.com/edde746/mpv-build), which publishes per-commit,
# content-addressed dev packages in the classic mpv-dev shape (libmpv-2.dll,
# libmpv.dll.a and include/mpv/*.h at the archive root) for every platform,
# replacing the unpinned SourceForge mpv-dev 7z this project fetched before.
# The key below is derived from the pinned sources (mpv v0.41.0, ffmpeg
# n8.0.1, the winbuild toolchain) at mpv-build commit d7c3d559; checksums
# come from that commit's mpv-build.lock.json / artifacts.json. Only the DLL
# is consumed (windows/runner/CMakeLists.txt copies it into the runner
# output directory as "libmpv-gpu-2.dll", not "libmpv-2.dll" -- see the
# comment beside that copy step for why) -- this project deliberately does
# not link against libmpv.dll.a or include mpv/client.h at build time (see
# the ABI structs hand-declared in desktop_libmpv_backend.cpp); it dlopens
# the DLL at runtime instead, so MPV_INCLUDE_DIR is unused here.
set(MPV_KEY "1da76841036d")
set(MPV_ASSET_BASE "https://github.com/edde746/mpv-build/releases/download/binaries-windows")
if(CMAKE_SYSTEM_PROCESSOR STREQUAL "ARM64")
  set(MPV_ARCH "aarch64")
  set(MPV_SHA256 "94c0e4d27794fb3bb754b0c62409c6b0cf17161fbafa16c3213d0239821a6836")
else()
  set(MPV_ARCH "x86_64")
  set(MPV_SHA256 "6a927cbbb7d44ecbefa3643ef0b435e3fa521b6a1123bb8c5d6349441ed3a760")
endif()

# Plain zips extract with CMake's built-in libarchive on every host arch, so
# both arches share the FetchContent path (the old mpv-dev 7z needed a
# 7-Zip binary on ARM64, whose libarchive lacks LZMA2).
include(FetchContent)
FetchContent_Declare(
  mpv_dev
  URL "${MPV_ASSET_BASE}/libmpv-windows-${MPV_KEY}-${MPV_ARCH}.zip"
  URL_HASH SHA256=${MPV_SHA256}
  DOWNLOAD_EXTRACT_TIMESTAMP TRUE
)
FetchContent_MakeAvailable(mpv_dev)

set(MPV_LIB_DIR "${mpv_dev_SOURCE_DIR}")

# ANGLE (GL->D3D11 translation), fetched for the GPU-texture rendering path
# (windows/runner/angle_surface_manager.{h,cc}): mpv renders through its
# OpenGL render API into a D3D11 texture via ANGLE, which is then handed to
# Flutter as a real FlutterDesktopGpuSurfaceTexture. This is the same
# pre-packaged ANGLE release the (now fully removed from this project, see
# docs/release/platform-release-matrix.md) media_kit_libs_windows_video
# package used to fetch -- a known-good, previously-shipping artifact, not a
# new unpinned dependency. MD5-verified like media_kit's own fetch, since
# unlike the libmpv fetch above this is a third-party mirror, not a project
# release feed.
set(ANGLE_FILENAME "ANGLE.7z")
set(ANGLE_URL "https://github.com/alexmercerind/flutter-windows-ANGLE-OpenGL-ES/releases/download/v1.0.1/${ANGLE_FILENAME}")
set(ANGLE_MD5 "e866f13e8d552348058afaafe869b1ed")
set(ANGLE_ARCHIVE "${CMAKE_BINARY_DIR}/${ANGLE_FILENAME}")
set(ANGLE_LIB_DIR "${CMAKE_BINARY_DIR}/angle")

if(EXISTS "${ANGLE_ARCHIVE}")
  file(MD5 "${ANGLE_ARCHIVE}" ANGLE_ARCHIVE_MD5)
  if(NOT ANGLE_MD5 STREQUAL ANGLE_ARCHIVE_MD5)
    file(REMOVE "${ANGLE_ARCHIVE}")
  endif()
endif()

if(NOT EXISTS "${ANGLE_ARCHIVE}")
  message(STATUS "Downloading ANGLE...")
  file(DOWNLOAD "${ANGLE_URL}" "${ANGLE_ARCHIVE}" SHOW_PROGRESS STATUS ANGLE_DL_STATUS)
  list(GET ANGLE_DL_STATUS 0 ANGLE_DL_RESULT)
  if(NOT ANGLE_DL_RESULT EQUAL 0)
    message(FATAL_ERROR "Failed to download ANGLE: ${ANGLE_DL_STATUS}")
  endif()
  file(MD5 "${ANGLE_ARCHIVE}" ANGLE_ARCHIVE_MD5)
  if(NOT ANGLE_MD5 STREQUAL ANGLE_ARCHIVE_MD5)
    message(FATAL_ERROR "ANGLE archive integrity check failed, please try to re-build project again.")
  endif()
endif()

if(NOT EXISTS "${ANGLE_LIB_DIR}/libEGL.dll")
  message(STATUS "Extracting ANGLE...")
  make_directory("${ANGLE_LIB_DIR}")
  # CMake's built-in tar handles this archive fine -- verified against
  # media_kit_libs_windows_video's own equivalent extraction step, which
  # uses the same command for the same archive.
  execute_process(
    COMMAND "${CMAKE_COMMAND}" -E tar xzf "${ANGLE_ARCHIVE}"
    WORKING_DIRECTORY "${ANGLE_LIB_DIR}"
    RESULT_VARIABLE ANGLE_EXTRACT_RESULT
  )
  if(NOT ANGLE_EXTRACT_RESULT EQUAL 0)
    message(FATAL_ERROR "Failed to extract ANGLE archive")
  endif()
endif()

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(VERSION 3.14...3.25)

# Define build configuration option.
get_property(IS_MULTICONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(IS_MULTICONFIG)
  set(CMAKE_CONFIGURATION_TYPES "Debug;Profile;Release"
    CACHE STRING "" FORCE)
else()
  if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE "Debug" CACHE
      STRING "Flutter build mode" FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
      "Debug" "Profile" "Release")
  endif()
endif()
# Define settings for the Profile build mode.
set(CMAKE_EXE_LINKER_FLAGS_PROFILE "${CMAKE_EXE_LINKER_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS_PROFILE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE}")
set(CMAKE_C_FLAGS_PROFILE "${CMAKE_C_FLAGS_RELEASE}")
set(CMAKE_CXX_FLAGS_PROFILE "${CMAKE_CXX_FLAGS_RELEASE}")

# Use Unicode for all projects.
add_definitions(-DUNICODE -D_UNICODE)

# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  target_compile_options(${TARGET} PRIVATE /W4 /WX /wd"4100")
  target_compile_options(${TARGET} PRIVATE /EHsc)
  target_compile_definitions(${TARGET} PRIVATE "_HAS_EXCEPTIONS=0")
  target_compile_definitions(${TARGET} PRIVATE "$<$<CONFIG:Debug>:_DEBUG>")
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")


# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)


# === Installation ===
# Support files are copied into place next to the executable, so that it can
# run in place. This is done instead of making a separate bundle (as on Linux)
# so that building and running from within Visual Studio will work.
set(BUILD_BUNDLE_DIR "$<TARGET_FILE_DIR:${BINARY_NAME}>")
# Make the "install" step default, as it's required to run.
set(CMAKE_VS_INCLUDE_INSTALL_TO_DEFAULT_BUILD 1)
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

if(PLUGIN_BUNDLED_LIBRARIES)
  install(FILES "${PLUGIN_BUNDLED_LIBRARIES}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

# Copy the native assets provided by the build.dart from all packages.
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/windows/")
install(DIRECTORY "${NATIVE_ASSETS_DIR}"
   DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
   COMPONENT Runtime)

# Fully re-copy the assets directory on each build to avoid having stale files
# from a previous install.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# Install the AOT library on non-Debug builds only.
install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  CONFIGURATIONS Profile;Release
  COMPONENT Runtime)
