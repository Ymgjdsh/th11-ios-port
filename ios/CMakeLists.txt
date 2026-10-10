cmake_minimum_required(VERSION 3.20)
project(th11_ios LANGUAGES C CXX OBJC OBJCXX)
if(NOT CMAKE_SYSTEM_NAME STREQUAL "iOS")
  message(FATAL_ERROR "Configure with the iOS toolchain; see ios/build_ios.sh")
endif()
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_OBJCXX_STANDARD 17)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
get_filename_component(TH11_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/.." ABSOLUTE)
set(TH11_DEPENDENCIES "${TH11_ROOT}/.local/dependencies" CACHE PATH "Pinned SDL source dependencies")
set(TH11_ASSETS "${TH11_ROOT}/.local/assets" CACHE PATH "Private prepared resources")
set(TH11_ICON_CATALOG "${TH11_ROOT}/.local/app-icon/Assets.xcassets" CACHE PATH "Private game icon catalog")
set(TH11_BUILD_NUMBER "1" CACHE STRING "Monotonic build number")
set(TH11_BUNDLE_ID "org.th11.native" CACHE STRING "Application identifier")
option(TH11_DIAGNOSTICS "Enable scripted simulator smoke inputs" OFF)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(SDL_SHARED OFF CACHE BOOL "" FORCE)
set(SDL_STATIC ON CACHE BOOL "" FORCE)
set(SDL_TESTS OFF CACHE BOOL "" FORCE)
set(SDL_TEST_LIBRARY OFF CACHE BOOL "" FORCE)
set(SDL_EXAMPLES OFF CACHE BOOL "" FORCE)
set(SDL_GPU OFF CACHE BOOL "" FORCE)
set(SDL_METAL OFF CACHE BOOL "" FORCE)
set(SDL_VULKAN OFF CACHE BOOL "" FORCE)
set(SDL_RENDER ON CACHE BOOL "" FORCE)
set(SDL_OPENGLES ON CACHE BOOL "" FORCE)
set(SDL_HIDAPI OFF CACHE BOOL "" FORCE)
set(SDL_INSTALL OFF CACHE BOOL "" FORCE)
add_subdirectory("${TH11_DEPENDENCIES}/SDL" "${CMAKE_BINARY_DIR}/SDL")
file(GLOB GAME_SOURCES CONFIGURE_DEPENDS "${TH11_ROOT}/th11_web/cpp/game/*.cpp")
file(GLOB HOST_SOURCES CONFIGURE_DEPENDS "${TH11_ROOT}/th11_web/cpp/sdl/*.cpp")
add_executable(th11 MACOSX_BUNDLE main.mm Diagnostics.mm Preferences.mm ${GAME_SOURCES} ${HOST_SOURCES}
  "${TH11_ROOT}/portable/sdl/Renderer.cpp")
if(NOT EXISTS "${TH11_ICON_CATALOG}/AppIcon.appiconset/Contents.json")
  message(FATAL_ERROR "Prepare the private original game icon first; see ios/ICON.md")
endif()
target_sources(th11 PRIVATE "${TH11_ICON_CATALOG}")
set_source_files_properties("${TH11_ICON_CATALOG}" PROPERTIES MACOSX_PACKAGE_LOCATION Resources)
target_include_directories(th11 PRIVATE "${TH11_ROOT}/portable/sdl" "${TH11_ROOT}/portable/input" "${TH11_ROOT}/th11_web/cpp/sdl")
target_compile_definitions(th11 PRIVATE TH_SDL3=1 TH_NATIVE_PLATFORM=1 TH11_IOS=1 TH11_DEVELOPMENT_HARNESS=0)
target_compile_definitions(th11 PRIVATE TH11_DIAGNOSTICS=$<BOOL:${TH11_DIAGNOSTICS}>)
target_compile_options(th11 PRIVATE -fno-strict-aliasing -fno-fast-math -ffp-contract=off -fsigned-char
  -Wno-unknown-attributes -Wno-deprecated-declarations -Werror=unguarded-availability-new
  $<$<COMPILE_LANGUAGE:CXX>:-fno-exceptions;-fno-rtti>)
set_source_files_properties(main.mm Diagnostics.mm Preferences.mm PROPERTIES COMPILE_FLAGS "-fobjc-arc")
target_link_libraries(th11 PRIVATE SDL3::SDL3
  "-framework UIKit" "-framework Foundation" "-framework AVFoundation"
  "-framework QuartzCore" "-framework OpenGLES")
target_link_options(th11 PRIVATE "LINKER:-dead_strip")
configure_file(Info.plist.in "${CMAKE_BINARY_DIR}/TH11-Info.plist" @ONLY)
set_target_properties(th11 PROPERTIES
  MACOSX_BUNDLE_INFO_PLIST "${CMAKE_BINARY_DIR}/TH11-Info.plist"
  XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "${TH11_BUNDLE_ID}"
  XCODE_ATTRIBUTE_TARGETED_DEVICE_FAMILY "1,2"
  XCODE_ATTRIBUTE_ASSETCATALOG_COMPILER_APPICON_NAME "AppIcon"
  XCODE_ATTRIBUTE_IPHONEOS_DEPLOYMENT_TARGET "14.0"
  XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED "NO"
  XCODE_ATTRIBUTE_ENABLE_BITCODE "NO"
  XCODE_ATTRIBUTE_DEBUG_INFORMATION_FORMAT "dwarf-with-dsym")
add_custom_command(TARGET th11 POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E copy_directory "${CMAKE_CURRENT_SOURCE_DIR}/licenses" "$<TARGET_BUNDLE_DIR:th11>/licenses"
  COMMAND ${CMAKE_COMMAND} -E copy "${TH11_ROOT}/portable/sdl/third_party/miniaudio.LICENSE" "$<TARGET_BUNDLE_DIR:th11>/licenses/miniaudio.txt")
if(EXISTS "${TH11_ASSETS}/game/th11.dat")
  add_custom_command(TARGET th11 POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_directory "${TH11_ASSETS}" "$<TARGET_BUNDLE_DIR:th11>/assets")
else()
  message(FATAL_ERROR "Prepare private game resources first; see ios/ASSETS.md")
endif()
