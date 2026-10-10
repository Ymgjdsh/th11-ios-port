#include "../../portable/sdl/PortraitPresentation.hpp"
#include "../../portable/input/TouchController.hpp"
#include <cassert>
#include <cmath>
#include <cstdio>

int main(){
    using namespace touhou::sdl;
    using namespace touhou::input;
    // iPad mini 5: preserve TH06's quarter-screen header and fill every row.
    const auto regions=portraitRegions(1536,2048);
    assert(regions[0].dh==512&&regions[2].dy==512&&regions[2].dh==1536);
    assert(regions[0].dw+regions[1].dw==1536);
    // Map a real finger displacement through the cropped presentation, then
    // exercise the gesture controller, rather than testing only the layout.
    const auto viewport=portraitTouchViewport(1536,2048);
    const auto source=portraitTouchSource;
    auto position=[&](float px,float py){return std::array<float,2>{
        source[0]+(px/1536-viewport[0])/viewport[2]*source[2],
        source[1]+(py/2048-viewport[1])/viewport[3]*source[3]};};
    TouchState state;state.context=1;state.instance=1;state.ready=true;
    state.x=0;state.y=224;state.fast=8;state.slow=4;
    state.min_x=-184;state.max_x=184;state.min_y=32;state.max_y=432;
    TouchController gestures;
    auto a=position(600,1200),b=position(720,1260);
    gestures.pointer(0,1,a[0],a[1],100,state,false);
    gestures.pointer(1,1,b[0],b[1],130,state,false);
    auto moved=gestures.sample(state,130,false,false);
    assert(moved.motion==1&&std::abs(moved.x-30)<.001);
    assert(std::abs(moved.y-(224+17.5))<.001);
    gestures.pointer(2,1,b[0],b[1],150,state,false);
    assert(!gestures.sample(state,150,false,false).motion);
    // Very tall phones and odd widths still have a single continuous field.
    for(auto size:{std::array<int,2>{750,1334},std::array<int,2>{1179,2556}}){
        auto parts=portraitRegions(size[0],size[1]);
        assert(parts[2].dy+parts[2].dh==size[1]);
        assert(parts[1].dx+parts[1].dw==size[0]);
        assert(parts[0].dh==parts[1].dh&&parts[2].dw==size[0]);
    }
    const auto phone=portraitRegions(1170,2532,132);
    assert(phone[0].dy==132&&phone[1].dy==132);
    assert(phone[0].dy+phone[0].dh==phone[2].dy);
    assert(phone[2].dy+phone[2].dh==2532);
    std::puts("PASS portrait presentation: full coverage, TH06 proportions, cropped finger movement and release");
}
