#pragma once
#import <Foundation/Foundation.h>
namespace touhou::ios {
inline NSDictionary* defaults(){return @{@"twoFinger":@YES,@"doubleTap":@YES,@"movement":@0,@"dragLimited":@YES,@"developer":@NO,@"hidden":@NO,@"toggleFire":@NO,@"toggleSlow":@NO,@"autoFire":@NO,@"autoSlow":@NO,@"dragFire":@NO,@"opacity":@1.0,@"size":@1.0,@"sensitivity":@1.0,@"deadZone":@.16,@"leftHand":@NO,@"haptics":@NO,@"fps":@60,@"smooth":@NO,@"performance":@NO};}
inline NSString* preferenceKey(NSString* key){return [@"TH11." stringByAppendingString:key];}
inline double preference(NSString* key){id value=[NSUserDefaults.standardUserDefaults objectForKey:preferenceKey(key)];return [(value?:defaults()[key]) doubleValue];}
inline void setPreference(NSString* key,id value){[NSUserDefaults.standardUserDefaults setObject:value forKey:preferenceKey(key)];}
inline void resetPreferences(){for(NSString* key in NSUserDefaults.standardUserDefaults.dictionaryRepresentation)if([key hasPrefix:@"TH11."])[NSUserDefaults.standardUserDefaults removeObjectForKey:key];}
void applyPreferences();
void editControlLayout(void (^finished)(void));
}
