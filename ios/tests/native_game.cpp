#include "../../th11_web/cpp/game/GameSession.hpp"
#include <cassert>
#include <cstdio>
#include <fstream>
#include <iterator>
#include <cmath>
using namespace th11;
struct ClockGraphics:ZunGraphics {
    touhou::graphics::PipelineState state{};
    touhou::graphics::PipelineState& pipeline()override{return state;}
    u32 texture(const AnmResource&,u32 n)override{return n+1;}
    void bind_texture(u32)override{}
    void set_layout(touhou::graphics::VertexLayout)override{}
    void set_matrix(touhou::graphics::MatrixKind,const Matrix4&)override{}
    void triangles(u32,const void*,u32)override{}
    void primitives(touhou::graphics::Topology,u32,const void*,u32)override{}
    bool select_target(const AnmResource*,u32)override{return true;}
    bool clear_target(u32,const GraphicsViewport*)override{return true;}
};
static void menu_checks(GameResources& source,ClockGraphics& graphics){
    auto game=std::make_unique<GameSession>();assert(game->open_title(source,false));
    AnmRenderer renderer(graphics);renderer.viewport={0,0,640,480,0,1};
    auto tick=[&](u32 held=0){
        if(!game->update({held})||!game->draw(renderer)){
            std::fprintf(stderr,"menu phase=%s error=%s\n",game->phase_name(),game->error.c_str());std::abort();
        }
        if(game->title&&game->title->replay_scan_requested)game->title->replay_scan_complete();
        renderer.flush();
    };
    auto wait=[&](unsigned frames=40){for(unsigned i=0;i<frames;i++)tick();};
    auto press=[&](u32 key){tick(key);tick();};
    auto ready=[&](TitleScreen screen){wait();assert(game->title&&game->title->screen==screen&&game->title->substate==2);};
    auto enter=[&](int choice,TitleScreen screen){
        ready(TitleScreen::Main);
        for(unsigned i=0;i<8&&game->title->cursor.selected!=choice;i++)press(32);
        assert(game->title->cursor.selected==choice);press(1);ready(screen);
    };
    wait(100);
    // Fresh scores retain the original Extra unlock. Navigation skips it.
    assert(!game->title->unlocked());press(32);assert(game->title->cursor.selected==2);
    enter(6,TitleScreen::Options);
    const int music=game->config.music_volume();press(64);assert(game->config.music_volume()==music-5);
    press(32);const int sound=game->config.sound_volume();press(64);assert(game->config.sound_volume()==sound-5);
    press(32);press(1);ready(TitleScreen::Keys);
    game->title->controller_buttons=1u<<7;tick();game->title->controller_buttons=0;
    assert(game->title->edited_buttons[0]==7);
    // iOS X/back cancels from any controller row and discards pending edits.
    press(2);ready(TitleScreen::Options);
    assert(game->title->edited_buttons[0]!=7);
    press(2);press(2);ready(TitleScreen::Main);
    std::puts("PASS menus: volume edits, controller mapping/cancel, return, locked Extra navigation");
    enter(5,TitleScreen::Music);assert(game->title->music_entries.size()>=17&&game->title->music_entries.size()<=20);
    std::printf("Music room catalog: %zu original entries\n",game->title->music_entries.size());
    tick(1);assert(game->title->music_request==0);tick();press(32);
    tick(1);assert(game->title->music_pause);tick();tick(1);assert(game->title->music_request==1);tick();
    press(2);ready(TitleScreen::Main);
    std::puts("PASS menus: music room, unheard-track confirmation, transport request, return");
    enter(4,TitleScreen::Records);press(32);press(128);press(64);press(16);press(2);ready(TitleScreen::Main);
    enter(3,TitleScreen::Replays);press(128);press(64);press(2);ready(TitleScreen::Main);
    std::puts("PASS menus: records and empty replay catalog, paging, return");
    enter(3,TitleScreen::Replays);
    std::vector<u8> demo;assert(source.read("demo0.rpy",demo));
    auto entry=std::make_shared<TitleMenu::ReplayEntry>();entry->file=demo;
    assert(entry->replay.open(demo.data(),u32(demo.size())));game->title->replay_files[0]=entry;
    game->title->cursor.select(0);press(1);wait(20);assert(game->title->substate==4);
    press(1);wait(35);assert(game->state.phase==GameSessionPhase::stage&&game->state.replay);
    assert(game->return_to_title());wait(50);assert(game->title->screen==TitleScreen::Replays);
    press(2);ready(TitleScreen::Main);
    std::puts("PASS menus: original replay stage selection, start, return to replay list");
    enter(2,TitleScreen::Difficulty);press(1);ready(TitleScreen::Character);
    press(1);ready(TitleScreen::Partner);press(1);ready(TitleScreen::Practice);
    const auto selection=game->title->selection;
    auto& records=game->scores.characters[selection.character*3+selection.partner];
    records[0x5a9+selection.difficulty*6*8]=1;
    game->title->cursor.select(0);press(1);wait(42);
    assert(game->state.phase==GameSessionPhase::stage&&game->state.practice&&game->state.stage==1);
    assert(game->return_to_title());ready(TitleScreen::Main);
    std::puts("PASS menus: practice character/partner/stage selection, start, return");
    enter(0,TitleScreen::Difficulty);press(1);ready(TitleScreen::Character);
    press(128);assert(game->title->cursor.selected==1);press(1);ready(TitleScreen::Partner);
    press(32);press(1);wait(42);
    assert(game->state.phase==GameSessionPhase::stage&&game->state.character==1&&game->state.subtype==1);
    std::puts("PASS menus: normal start with selected character and partner");
    assert(game->pause());wait(15);press(1);wait(15);assert(game->state.phase==GameSessionPhase::stage);
    assert(game->pause());wait(15);press(32);press(32);press(1);wait(35);
    assert(game->pause_menu->state==7);press(16);press(1);wait(40);
    assert(game->pause_menu->state==9);press(1);wait(12);
    assert(game->pause_menu->state==10);
    for(int i=0;i<8;i++)press(1);
    assert(game->pause_menu->name_length==8);press(1);assert(game->pause_menu->save_requested);
    std::vector<u8> saved;assert(game->save_replay(game->pause_menu->entered_name.data(),saved));
    Replay decoded;assert(decoded.open(saved.data(),u32(saved.size())));
    game->pause_menu->save_requested=false;wait(12);press(2);ready(TitleScreen::Main);
    std::puts("PASS menus: pause/resume, save-and-quit confirmation, touch-accessible name entry and replay encoding");
    for(unsigned i=0;i<8&&game->title->cursor.selected!=7;i++)press(32);
    press(1);wait(25);assert(game->state.phase==GameSessionPhase::finished&&game->title->screen==TitleScreen::Exit);
    std::puts("PASS menus: Quit reaches terminal state for native save/close handler");
}
static void feature_checks(GameResources& source,ClockGraphics& graphics){
    auto menu=std::make_unique<GameSession>();assert(menu->open_title(source,false));
    for(int i=0;i<100;++i)assert(menu->update({}));
    auto before=menu->scores;
    assert(!menu->unlock_all("wrong")&&!menu->unlock_all(nullptr));
    assert(menu->scores.characters==before.characters&&menu->scores.settings==before.settings);
    assert(menu->unlock_all("ymgjdsh"));assert(menu->update({}));
    assert(menu->title->cursor.disabled_count==0&&menu->title->unlocked());
    menu->title->cursor.select(0);menu->title->cursor.move(1);assert(menu->title->cursor.selected==1);
    for(int c=0;c<2;++c)for(int p=0;p<3;++p)assert(menu->title->available(c,p));
    for(int c=0;c<6;++c)for(int i=0;i<24;++i)assert(menu->scores.characters[c][0x5a9+i*8]);
    for(int i=0;i<17;++i)assert(menu->scores.settings[0x26+i]);
    // Preserve all existing ranking, spell and aggregate data.
    for(int c=0;c<7;++c)for(unsigned i=0;i<before.characters[c].size();++i){
        const bool availability=c<6&&i>=0x5a9&&i<=0x5a9+23*8&&(i-0x5a9)%8==0;
        if(!availability)assert(menu->scores.characters[c][i]==before.characters[c][i]);
    }
    assert(menu->begin(source,1,0,0,1));
    std::vector<u8> encoded;assert(menu->save_scores(encoded));
    GameSession restored;assert(restored.load_scores(encoded.data(),u32(encoded.size())));
    for(int c=0;c<6;++c)for(int i=0;i<24;++i)assert(restored.scores.characters[c][0x5a9+i*8]);
    for(int i=0;i<17;++i)assert(restored.scores.settings[0x26+i]);
    std::puts("PASS unlock: invalid code unchanged; six Extra routes, 144 practice flags, 17 music tracks; menu refresh and save/load preserve records");

    for(int shot=0;shot<6;++shot){
        auto game=std::make_unique<GameSession>();assert(game->begin(source,1,shot/3,shot%3,1));
        auto& b=*game->battle;auto& p=*b.player;
        game->set_developer(true);assert(game->developer_action(0));assert(game->developer_action(3));
        AnmRenderer renderer(graphics);renderer.viewport={0,0,640,480,0,1};
        for(int i=0;i<45;++i)assert(game->update({}));
        // Long alternating targets would expose Aya's old double-distance
        // overshoot and stale option positions on every frame.
        for(int frame=0;frame<90;++frame){
            auto& input=b.player_input.movement;input.touch_mode=2;
            input.touch_x=frame%2?-120:120;input.touch_y=frame%2?400:80;
            assert(game->update({})&&game->draw(renderer));renderer.flush();
            assert(p.motion.state.position.x==input.touch_x&&p.motion.state.position.y==input.touch_y);
            for(const auto& option:p.motion.options)if(option.state){
                assert(std::abs(option.x-p.motion.state.x)<128*140&&std::abs(option.y-p.motion.state.y)<128*140);
                const auto* vm=game->animations.find(option.animation);assert(vm);
                assert(std::abs(vm->position.x-(float(option.x)/128+224))<.01);
            }
            // No player trail ANMs may be generated by unlimited dragging.
            if(shot==2)for(auto* vm=game->animations.layer_first(11);vm;vm=vm->draw_next)
                assert(vm->resource!=&game->resources.core.players[0]||vm->script_index!=19);
        }
        auto& motion=p.motion.state;auto& input=b.player_input.movement;
        input.touch_mode=1;input.touch_x=motion.position.x+1;input.touch_y=motion.position.y;
        assert(game->update({}));assert(std::abs(motion.position.x-input.touch_x)<.01);
        input.touch_x=-150;input.touch_y=50;
        const auto origin=motion.position;assert(game->update({}));
        const float limit=float(motion.normal_speed)/128*(shot==2?2:1);
        assert(std::hypot(motion.position.x-origin.x,motion.position.y-origin.y)<=limit+.02);
        input.touch_mode=0;
        assert(game->developer_action(5));
        assert(game->economy.score_units==999999999&&game->economy.lives==8&&game->economy.power==game->economy.max_power&&game->economy.graze==999999);
        assert(game->developer_action(6));assert(game->update({})&&game->draw(renderer));renderer.flush();
        p.state.invincibility.set(0,&game->animations.rate);p.state.life_state=1;
        BulletState bullet{};bullet.position=motion.position;bullet.hitbox={8,8};
        assert(b.collision(bullet)>=0&&p.state.life_state==1);
        game->set_developer(false);assert(!game->developer_invincible&&!b.developer_invincible&&!game->developer_action(5));
        assert(b.collision(bullet)>=0&&p.state.life_state==4);
        std::printf("PASS features shot %d: 90 direct drags, option/body draws, limited close/long targets, max stock, clear, invincibility toggle\n",shot);
    }
    auto replay=std::make_unique<GameSession>();std::vector<u8> demo;assert(source.read("demo0.rpy",demo));
    assert(replay->begin_replay(source,demo.data(),u32(demo.size()),0,true));replay->set_developer(true);
    assert(!replay->developer_available()&&!replay->developer_action(0));
    std::puts("PASS developer: replay/demo excluded");
}
int main(int argc,char** argv){
    std::setvbuf(stdout,nullptr,_IOLBF,0);
    if(argc!=2&&argc!=3)return 2;
    std::ifstream file(argv[1],std::ios::binary);std::vector<u8> bytes((std::istreambuf_iterator<char>(file)),{});
    auto source=std::make_unique<GameResources>();assert(source->open_archive(bytes.data(),u32(bytes.size())));
    ClockGraphics graphics;unsigned long ticks=0;
    if(argc==3&&std::string(argv[2])=="--features-only"){feature_checks(*source,graphics);return 0;}
    menu_checks(*source,graphics);
    if(argc==3){assert(std::string(argv[2])=="--menus-only");return 0;}
    for(unsigned demo=0;demo<4;demo++){
        std::vector<u8> replay;const auto name=std::string("demo")+char('0'+demo)+".rpy";assert(source->read(name,replay));
        auto game=std::make_unique<GameSession>();assert(game->begin_replay(*source,replay.data(),u32(replay.size()),0,true));
        AnmRenderer renderer(graphics);renderer.viewport={0,0,640,480,0,1};
        unsigned count=0;while(game->state.phase==GameSessionPhase::stage&&count<12000){
            if(!game->update({})||!game->draw(renderer)){std::fprintf(stderr,"%s frame %u: %s\n",name.c_str(),count,game->error.c_str());return 1;}
            renderer.flush();++count;++ticks;
        }
        assert(count>3000&&count<12000);std::printf("PASS %s: %u complete playback ticks, phase %s\n",name.c_str(),count,game->phase_name());
    }
    for(unsigned stage=1;stage<=7;stage++)for(int shot=0;shot<6;shot++){
        auto game=std::make_unique<GameSession>();assert(game->begin(*source,stage,shot/3,shot%3,stage==7?4:1));
        AnmRenderer renderer(graphics);renderer.viewport={0,0,640,480,0,1};
        for(unsigned frame=0;frame<600;frame++){
            GameSessionInput input;input.held=1;
            if(frame==120){game->economy.power=game->economy.max_power;input.held|=2;}
            if(!game->update(input)||!game->draw(renderer)){std::fprintf(stderr,"stage %u shot %d frame %u: %s\n",stage,shot,frame,game->error.c_str());return 1;}
            renderer.flush();++ticks;
        }
        assert(game->pause());const auto before=game->state.frame;assert(game->update({}));assert(game->state.frame==before);assert(game->resume());
        std::vector<u8> score;assert(game->save_scores(score));ScoreFile check;assert(check.open(score.data(),u32(score.size())));
        std::vector<u8> replay;assert(game->save_replay("NATIVE",replay));Replay decoded;assert(decoded.open(replay.data(),u32(replay.size())));
        std::printf("PASS stage %u shot %d: update/draw clocks, pause/resume, score/replay roundtrip\n",stage,shot);
    }
    std::printf("PASS native TH11 integration: %lu ticks; GPU, audio and physical iOS device are separate checks\n",ticks);
}
