cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME} WIN32
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
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)

# gpu-next/D3D11-capable libmpv build for the native mpv backend
# (desktop_libmpv_backend.cpp), fetched by the top-level CMakeLists.txt (see
# MPV_LIB_DIR there) the same way the open-source Plezy player fetches it.
# Named "libmpv-2.dll", not "mpv-2.dll", so it is picked up ahead of -- and
# never collides with -- the "mpv-2.dll" the media_kit_libs_windows_video
# plugin bundles for the separate MediaKit fallback adapter: that build is
# compiled for media_kit's own render-API/texture usage and cannot open a
# windowed gpu-next/D3D11 VO, which is why desktop_libmpv_backend.cpp's
# loader tries "libmpv-2.dll" first (see kMpvDllNames).
add_custom_command(TARGET ${BINARY_NAME} POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
    "${MPV_LIB_DIR}/libmpv-2.dll" "$<TARGET_FILE_DIR:${BINARY_NAME}>/libmpv-2.dll"
  COMMENT "Copying fetched libmpv-2.dll"
)
