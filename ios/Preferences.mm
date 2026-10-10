#import "Preferences.hpp"
#include "NativeHost.hpp"
namespace touhou::ios {
void applyPreferences(){
 sdl_native_options(preference(@"autoFire"),preference(@"autoSlow"),preference(@"dragFire"),0,0);
 sdl_display_options(int(preference(@"fps")),preference(@"smooth"));
 sdl_touch_options(1,!preference(@"dragLimited"),float(preference(@"sensitivity")));
 sdl_developer_enabled(preference(@"developer"));
 sdl_touch_mode(preference(@"movement")==2?3:0);
 [NSNotificationCenter.defaultCenter postNotificationName:@"TH11PreferencesChanged" object:nil];
}

}
