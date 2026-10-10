#pragma once
#include <algorithm>
#include <array>

namespace touhou::sdl {
// Same header/playfield proportions as the TH06 iOS port. Coordinates are
// top-down, in the original 640x480 canvas; the final blit flips only the Y axis.
inline int portraitHeaderHeight(int width,int height){
    if(width<=0||height<=0)return 0;
    return std::min(height,std::max(96,std::min(width*9/25,height/4)));
}
struct PresentationRegion {int sx,sy,sw,sh,dx,dy,dw,dh;};
inline std::array<PresentationRegion,3> portraitRegions(int width,int height,int safeTop=0){
    const int header=portraitHeaderHeight(width,height),half=width/2;
    safeTop=std::clamp(safeTop,0,std::max(0,header-1));
    return {{{416,16,224,224,0,safeTop,half,header-safeTop},
             {416,240,224,224,half,safeTop,width-half,header-safeTop},
             {32,16,384,448,0,header,width,height-header}}};
}
inline std::array<float,4> portraitTouchViewport(int width,int height){
    const float header=float(portraitHeaderHeight(width,height))/height;
    return {0,header,1,1-header};
}
inline constexpr std::array<float,4> portraitTouchSource{32.f/640,16.f/480,384.f/640,448.f/480};
}
