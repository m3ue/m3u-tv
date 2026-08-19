cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME} WIN32
  "angle_surface_manager.cc"
  "desktop_libmpv_backend.cpp"
  "flutter_window.cpp"
  "main.cpp"
  "mpv/display_mode_manager.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the build version.
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

# Disable Windows macros that collide with C++ standard library functions.
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

# Add dependency libraries and include directories. Add any application-specific
# dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app flutter_wrapper_plugin)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib")
# DisplayConfig*/ChangeDisplaySettingsExW (display_mode_manager.cpp's OS-level
# HDR/refresh-rate switching) and the registry Reg* calls its crash-recovery
# journal uses.
target_link_libraries(${BINARY_NAME} PRIVATE "user32.lib" "advapi32.lib")
# angle_surface_manager.cc's D3D11 device/texture creation (d3d11.lib) and
# shared-handle retrieval via IDXGIResource/IDXGIDevice (dxgi.lib), plus the
# ANGLE import libraries themselves (GL->D3D11 translation, fetched by the
# top-level CMakeLists.txt as ANGLE_LIB_DIR) so mpv's OpenGL render API calls
# resolve at link time even though the actual libEGL.dll/libGLESv2.dll are
# loaded at runtime from next to the exe (see the POST_BUILD copy below).
target_link_libraries(${BINARY_NAME} PRIVATE "d3d11.lib" "dxgi.lib")
target_link_libraries(${BINARY_NAME} PRIVATE
  "${ANGLE_LIB_DIR}/lib/libEGL.dll.lib"
  "${ANGLE_LIB_DIR}/lib/libGLESv2.dll.lib"
)
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")
target_include_directories(${BINARY_NAME} PRIVATE "${ANGLE_LIB_DIR}/include")

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)

# gpu-next/D3D11-capable libmpv build for the native mpv backend
# (desktop_libmpv_backend.cpp), fetched by the top-level CMakeLists.txt (see
# MPV_LIB_DIR there) the same way the open-source Plezy player fetches it.
# Renamed to "libmpv-gpu-2.dll" on copy: this used to matter because the
# media_kit_libs_windows_video plugin (no longer a dependency of this
# project at all -- see kMpvDllNames in desktop_libmpv_backend.cpp for the
# full history) bundled a DLL literally named "libmpv-2.dll" into this same
# output directory, and its copy always ran after this one (Visual Studio
# builds the INSTALL project, which is where that copy happened, after every
# other target), silently overwriting ours and reintroducing the exact
# "Error opening/initializing the selected video_out (--vo) device" failure
# this fetch exists to fix. Kept distinctly named regardless, both as
# defense against any future plugin doing the same thing and because it is
# simply accurate: this is our own fetched build. See kMpvDllNames in
# desktop_libmpv_backend.cpp, which tries "libmpv-gpu-2.dll" first for the
# same reason.
add_custom_command(TARGET ${BINARY_NAME} POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
    "${MPV_LIB_DIR}/libmpv-2.dll" "$<TARGET_FILE_DIR:${BINARY_NAME}>/libmpv-gpu-2.dll"
  COMMENT "Copying fetched libmpv-2.dll as libmpv-gpu-2.dll"
)

# Runtime ANGLE DLLs for the GPU-texture rendering path
# (angle_surface_manager.cc). d3dcompiler_47.dll/zlib.dll are ANGLE's own
# runtime dependencies. Deliberately not copying ANGLE's bundled
# vk_swiftshader.dll/vulkan-1.dll (its software Vulkan fallback for machines
# with no real GPU at all) -- this project already has its own proven SW
# pixel-buffer fallback for that case (see TryLoadGpuTexture's runtime
# capability check in desktop_libmpv_backend.cpp), so ANGLE's own software
# path is never reached here.
add_custom_command(TARGET ${BINARY_NAME} POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
    "${ANGLE_LIB_DIR}/libEGL.dll" "${ANGLE_LIB_DIR}/libGLESv2.dll"
    "${ANGLE_LIB_DIR}/d3dcompiler_47.dll" "${ANGLE_LIB_DIR}/zlib.dll"
    "$<TARGET_FILE_DIR:${BINARY_NAME}>/"
  COMMENT "Copying ANGLE runtime DLLs"
)
