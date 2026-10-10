#include "ResourcePaths.hpp"
#include "FontDevice.hpp"
#include <SDL3/SDL.h>
namespace th11::sdl {
bool FontDevice::initialize(){
    if(ready)return true;
    const char* files[]={"font0.bin","font1.bin","font2.bin","font3.bin","cp932.bin","blend4444.bin"};
    for(u32 n=0;n<6;++n){const std::string path=std::string("/fonts/")+files[n];size_t size=0;auto* data=static_cast<u8*>(SDL_LoadFile(resource_path(path).c_str(),&size));const bool valid=data&&size<=UINT32_MAX&&raster.glyphs.load(n,data,u32(size));SDL_free(data);if(!valid){error="Invalid original font data: "+path;return false;}}
    ready=raster.glyphs.ready();return ready;
}
bool FontDevice::text(AnmVm& vm,const DialogueText& request){
    if(!ready||!vm.sprite||!vm.resource){error="Missing text animation";return false;}
    const u32 handle=graphics.texture(*vm.resource,vm.sprite->texture);auto* image=graphics.pixels(handle);if(!image){error="Missing text texture";return false;}
    const auto& s=*vm.sprite;TextStyle style;style.offset=request.offset;style.height=vm.rectangle_columns?vm.rectangle_columns:17;style.font=request.style;
    style.color=request.color;style.spacing=u32(request.font);style.plain=(vm.flags2&2)!=0;
    if(request.right_aligned)style.offset=i32(double(s.width)-u32((style.height-1)*request.bytes.size()/2));
    if(request.centered)style.offset=i32(s.width)/2-i32((style.height-1)*request.bytes.size()/4);
    const ImageRect rect{i32(s.x),i32(s.y),i32(s.x+s.width),i32(s.y+s.height)};
    if(!raster.write(*image,rect,request.bytes,style)){error="Original text raster bounds: "+std::to_string(style.height);return false;}
    graphics.changed(handle);vm.flags|=1;++writes;return true;
}
}
