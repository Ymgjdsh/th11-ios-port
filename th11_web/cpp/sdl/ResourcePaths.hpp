#pragma once
#include <SDL3/SDL.h>
#include <string>
namespace th11::sdl {
inline std::string resource_path(const std::string& path){
#if defined(TH11_IOS)
    return std::string(SDL_GetBasePath())+"assets/"+(path=="/th11.dat"?"game/th11.dat":path.substr(path[0]=='/'));
#else
    return path;
#endif
}
inline std::string save_path(const std::string& path){
#if defined(TH11_IOS)
    static std::string root=[](){char* p=SDL_GetPrefPath("Touhou","th11");std::string s=p?p:"";SDL_free(p);return s;}();
    return root+(path.rfind("/save",0)==0?path.substr(path.size()>5?6:5):path);
#else
    return path;
#endif
}
}
