#pragma once
#include <SDL3/SDL.h>
#include <cstdint>
extern "C" {
void* sdl_game_open(uint32_t language,uint32_t seed);
void sdl_loop_start(void*);int sdl_loop_frame(double);void sdl_loop_pause(uint32_t);void sdl_loop_stop();int sdl_loop_is_paused();
SDL_Window* sdl_window();void sdl_set_viewport(float,float,float,float);void sdl_viewport_rect(float*,float*,float*,float*);
void sdl_set_safe_top(float);
void sdl_key(const char*,uint32_t);void sdl_keys_clear();void sdl_touch(uint32_t,int32_t,float,float);void sdl_touch_cancel();
void sdl_touch_options(uint32_t,uint32_t,float);void sdl_touch_gestures(uint32_t,uint32_t);void sdl_touch_mode(uint32_t);
void sdl_touch_controls(uint32_t,uint32_t,uint32_t,uint32_t,float,float);
const int32_t* sdl_game_status();const char* sdl_file_error();
const unsigned* th11_audio_statistics();
void sdl_native_options(int,int,int,int,int);void sdl_display_options(int,int);
void sdl_developer_enabled(int);int sdl_developer_available();int sdl_developer_invincible();int sdl_developer_action(int);
int sdl_unlock_all(const char*);
#if TH11_DIAGNOSTICS
int sdl_diagnostic_stage(int shot);
int sdl_diagnostic_features();
const float* sdl_diagnostic_player();
#endif
}
