#pragma once
#include "GraphicsDevice.hpp"
#include "../game/TextRaster.hpp"
#include "../game/Dialogue.hpp"
namespace th11::sdl {
class FontDevice {
    GraphicsDevice& graphics;TextRaster raster;bool ready=false;
public:
    explicit FontDevice(GraphicsDevice& g):graphics(g){}
    std::string error;
    u32 writes=0;
    bool initialize();
    bool text(AnmVm&,const DialogueText&);
};
}
