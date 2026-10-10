#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#include <SDL3/SDL.h>
#include <SDL3/SDL_main.h>
#include <SDL3/SDL_system.h>
#include "NativeHost.hpp"
#include "Lifecycle.hpp"
#include "Diagnostics.hpp"
#include "Preferences.hpp"
#include "Joystick.hpp"
#include "NativePerformance.hpp"
#include <cstdio>
#include <ctime>
#include <cstring>
#include <algorithm>
#include <cstdlib>

static uint32_t bombSerial=0, pauseSerial=0;
static bool shooting=false, focusing=false;
static float stickX=0,stickY=0;
static bool stickMode=false;
static touhou::ios::Lifecycle lifecycle;
static uint64_t frames=0;
static bool smoke=false;
static void showSettings(UIButton* button);
static void showDeveloper();
static void controls(){
    const bool autoFire=touhou::ios::preference(@"autoFire"),autoSlow=touhou::ios::preference(@"autoSlow"),dragFire=touhou::ios::preference(@"dragFire");
    sdl_native_options(autoFire,autoSlow,dragFire,0,0);
    sdl_touch_options(1,!touhou::ios::preference(@"dragLimited"),float(touhou::ios::preference(@"sensitivity")));
    sdl_touch_gestures(touhou::ios::preference(@"twoFinger"),touhou::ios::preference(@"doubleTap"));
    if(!stickMode)sdl_touch_mode((uint32_t)touhou::ios::preference(@"movement"));
    sdl_touch_controls(shooting||autoFire,focusing||autoSlow,bombSerial,pauseSerial,stickX*32767,stickY*32767);
}
static void audioSession(){
    NSError* error=nil;
    AVAudioSession* session=AVAudioSession.sharedInstance;
    BOOL category=[session setCategory:AVAudioSessionCategoryPlayback error:&error];
    if(!category)touhou::ios::diagnostic(@"Audio category error: %@",error);
    error=nil;BOOL enabled=[session setActive:YES error:&error];
    touhou::ios::diagnostic(@"Audio session: active=%d sampleRate=%.0f buffer=%.4f error=%@",enabled,session.sampleRate,session.IOBufferDuration,error);
}
static void buttonAppearance(UIButton* button,bool held){
    const bool action=button.tag<7,rose=button.tag==4||button.tag==6;
    button.backgroundColor=rose?[UIColor colorWithRed:.20 green:.07 blue:.13 alpha:held?.88:.58]:
                                 [UIColor colorWithRed:.09 green:.13 blue:.21 alpha:held?.88:.58];
    button.layer.borderColor=(rose?[UIColor colorWithRed:.86 green:.32 blue:.49 alpha:held?.95:.68]:
                                   [UIColor colorWithRed:.61 green:.75 blue:.88 alpha:held?.95:.62]).CGColor;
    button.transform=action&&held?CGAffineTransformMakeScale(.90,.90):CGAffineTransformIdentity;
    button.alpha=touhou::ios::preference(@"hidden")&&button.tag<7?0:touhou::ios::preference(@"opacity");
}
@interface TH11Joystick : UIControl
@property(nonatomic,strong) UIView* thumb;
@property(nonatomic,strong) UIView* innerRing;
@property(nonatomic) BOOL engaged;
@property(nonatomic) touhou::ios::JoystickSample sample;
- (void)reset;
@end
@implementation TH11Joystick
- (instancetype)initWithFrame:(CGRect)frame {
    self=[super initWithFrame:frame];if(!self)return nil;
    self.multipleTouchEnabled=NO;self.exclusiveTouch=NO;
    self.backgroundColor=[UIColor colorWithRed:.18 green:.16 blue:.32 alpha:.29];
    self.layer.borderWidth=1.5;self.layer.borderColor=[UIColor colorWithRed:.61 green:.70 blue:.84 alpha:.48].CGColor;
    self.innerRing=[[UIView alloc] initWithFrame:CGRectZero];self.innerRing.userInteractionEnabled=NO;
    self.innerRing.backgroundColor=[UIColor colorWithRed:.28 green:.42 blue:.58 alpha:.23];
    self.innerRing.layer.borderWidth=1;self.innerRing.layer.borderColor=[UIColor colorWithRed:.60 green:.73 blue:.88 alpha:.25].CGColor;
    [self addSubview:self.innerRing];
    self.thumb=[[UIView alloc] initWithFrame:CGRectZero];self.thumb.userInteractionEnabled=NO;
    self.thumb.backgroundColor=[UIColor colorWithRed:.68 green:.78 blue:.96 alpha:.58];
    self.thumb.layer.borderWidth=1;self.thumb.layer.borderColor=[UIColor colorWithRed:.86 green:.91 blue:1 alpha:.70].CGColor;
    [self addSubview:self.thumb];
    self.isAccessibilityElement=YES;self.accessibilityLabel=@"移动摇杆";
    self.accessibilityHint=@"按住并拖动以移动角色或选择菜单";
    self.accessibilityIdentifier=@"th11.joystick";
    self.accessibilityTraits=UIAccessibilityTraitAllowsDirectInteraction;
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];CGFloat size=std::min(self.bounds.size.width,self.bounds.size.height);
    self.layer.cornerRadius=size/2;self.thumb.bounds=CGRectMake(0,0,56,56);self.thumb.layer.cornerRadius=28;
    self.innerRing.bounds=CGRectMake(0,0,size*.78,size*.78);self.innerRing.layer.cornerRadius=size*.39;
    self.innerRing.center=CGPointMake(CGRectGetMidX(self.bounds),CGRectGetMidY(self.bounds));
    self.thumb.backgroundColor=self.engaged?[UIColor colorWithRed:.82 green:.90 blue:.96 alpha:.83]:
                                          [UIColor colorWithRed:.68 green:.78 blue:.96 alpha:.58];
    self.thumb.transform=self.engaged?CGAffineTransformMakeScale(1.10,1.10):CGAffineTransformIdentity;
    const CGFloat radius=std::max(CGFloat(1),(size-56)/2);
    self.thumb.center=CGPointMake(CGRectGetMidX(self.bounds)+self.sample.knobX*radius,CGRectGetMidY(self.bounds)+self.sample.knobY*radius);
}
- (void)updateTouch:(UITouch*)touch {
    const CGPoint point=[touch locationInView:self];
    const CGFloat radius=std::max(CGFloat(1),(std::min(self.bounds.size.width,self.bounds.size.height)-56)/2);
    self.sample=touhou::ios::joystickSample(float(point.x-CGRectGetMidX(self.bounds)),float(point.y-CGRectGetMidY(self.bounds)),float(radius),float(touhou::ios::preference(@"deadZone")));
    [self setNeedsLayout];[self sendActionsForControlEvents:UIControlEventValueChanged];
}
- (BOOL)beginTrackingWithTouch:(UITouch*)touch withEvent:(UIEvent*)event {
    if(!lifecycle.running())return NO;
    self.engaged=YES;[self updateTouch:touch];return YES;
}
- (BOOL)continueTrackingWithTouch:(UITouch*)touch withEvent:(UIEvent*)event {
    if(!lifecycle.running()){[self reset];return NO;}
    // UIControl keeps ownership of its original finger outside the bounds.
    // Clamp the vector at full travel and release only on up/cancel/lifecycle.
    [self updateTouch:touch];return YES;
}
- (void)endTrackingWithTouch:(UITouch*)touch withEvent:(UIEvent*)event {[super endTrackingWithTouch:touch withEvent:event];[self reset];}
- (void)cancelTrackingWithEvent:(UIEvent*)event {[super cancelTrackingWithEvent:event];[self reset];}
- (void)reset {
    self.engaged=NO;self.sample=touhou::ios::JoystickSample{};[self setNeedsLayout];[self sendActionsForControlEvents:UIControlEventValueChanged];
}
@end
@interface TH11Controls : UIView
@property(nonatomic,strong) NSArray* buttons;
@property(nonatomic,strong) TH11Joystick* joystick;
@property(nonatomic) CGRect layoutBounds;
@property(nonatomic) UIEdgeInsets layoutInsets;
@property(nonatomic) uint32_t pressedButtons;
@property(nonatomic) BOOL editing;
@property(nonatomic) BOOL portraitGameplay;
@property(nonatomic,strong) UIButton* editDone;
@property(nonatomic,strong) UILabel* performanceLabel;
@property(nonatomic,strong) UIButton* developerButton;
@property(nonatomic,copy) void (^layoutFinished)(void);
- (void)releaseInputs;
@end
@implementation TH11Controls
- (instancetype)initWithFrame:(CGRect)frame {
    self=[super initWithFrame:frame]; if(!self)return nil;
    self.multipleTouchEnabled=YES; self.backgroundColor=UIColor.clearColor;
    self.joystick=[[TH11Joystick alloc] initWithFrame:CGRectZero];
    [self.joystick addTarget:self action:@selector(joystickChanged:) forControlEvents:UIControlEventValueChanged];
    [self addSubview:self.joystick];
    NSArray* titles=@[@"Z",@"S",@"X",@"",@""];
    NSArray* labels=@[@"射击／确认",@"低速",@"Bomb",@"暂停／返回",@"设置"];
    NSArray* identifiers=@[@"th11.fire",@"th11.slow",@"th11.bomb",@"th11.pause",@"th11.settings"];
    NSMutableArray* all=[NSMutableArray array];
    for(NSInteger i=0;i<titles.count;i++){
        UIButton* button=[UIButton buttonWithType:UIButtonTypeSystem];button.tag=i+4;
        [button setTitle:titles[i] forState:UIControlStateNormal];
        [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        button.titleLabel.font=[UIFont systemFontOfSize:24 weight:UIFontWeightSemibold];
        button.accessibilityLabel=labels[i];button.accessibilityIdentifier=identifiers[i];
        if(i>=3){
            UIImageSymbolConfiguration* config=[UIImageSymbolConfiguration configurationWithPointSize:19 weight:UIImageSymbolWeightSemibold];
            [button setImage:[UIImage systemImageNamed:i==3?@"pause.fill":@"gearshape" withConfiguration:config] forState:UIControlStateNormal];
            button.tintColor=UIColor.whiteColor;
        }
        button.layer.borderWidth=i<3?1.5:1;buttonAppearance(button,false);
        button.multipleTouchEnabled=NO;button.exclusiveTouch=NO;
        [button addTarget:self action:@selector(down:) forControlEvents:UIControlEventTouchDown];
        [button addTarget:self action:@selector(reenter:) forControlEvents:UIControlEventTouchDragEnter];
        [button addTarget:self action:@selector(up:) forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside|UIControlEventTouchCancel|UIControlEventTouchDragExit];
        [self addSubview:button];[all addObject:button];
    }self.buttons=all;
    self.editDone=[UIButton buttonWithType:UIButtonTypeSystem];[self.editDone setTitle:@"保存布局" forState:UIControlStateNormal];
    self.editDone.backgroundColor=UIColor.systemBackgroundColor;self.editDone.layer.cornerRadius=12;self.editDone.hidden=YES;
    [self.editDone addTarget:self action:@selector(finishLayout) forControlEvents:UIControlEventTouchUpInside];[self addSubview:self.editDone];
    self.performanceLabel=[[UILabel alloc]init];self.performanceLabel.font=[UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightRegular];self.performanceLabel.textColor=UIColor.whiteColor;
    self.performanceLabel.backgroundColor=[UIColor colorWithWhite:0 alpha:.65];self.performanceLabel.textAlignment=NSTextAlignmentCenter;[self addSubview:self.performanceLabel];
    self.developerButton=[UIButton buttonWithType:UIButtonTypeSystem];
    [self.developerButton setTitle:@"开发" forState:UIControlStateNormal];
    [self.developerButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.developerButton.titleLabel.font=[UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    self.developerButton.backgroundColor=[UIColor colorWithRed:.31 green:.12 blue:.34 alpha:.82];
    self.developerButton.layer.cornerRadius=24;self.developerButton.layer.borderWidth=1;
    self.developerButton.layer.borderColor=[UIColor colorWithRed:.95 green:.64 blue:.86 alpha:.9].CGColor;
    self.developerButton.accessibilityLabel=@"开发者功能";self.developerButton.accessibilityHint=@"点击打开功能，拖动调整位置";
    self.developerButton.accessibilityIdentifier=@"th11.developer";self.developerButton.hidden=YES;
    [self.developerButton addTarget:self action:@selector(developerTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.developerButton addGestureRecognizer:[[UIPanGestureRecognizer alloc]initWithTarget:self action:@selector(developerPan:)]];
    [self addSubview:self.developerButton];
    for(UIView* control in [self.buttons arrayByAddingObject:self.joystick]){
        UIPanGestureRecognizer* pan=[[UIPanGestureRecognizer alloc]initWithTarget:self action:@selector(layoutPan:)];pan.enabled=NO;[control addGestureRecognizer:pan];
    }
    return self;
}
- (UIView*)hitTest:(CGPoint)point withEvent:(UIEvent*)event {UIView* hit=[super hitTest:point withEvent:event];return hit==self?nil:hit;}
- (void)layoutSubviews {
    [super layoutSubviews];UIEdgeInsets insets=self.safeAreaInsets;
    if(!CGRectEqualToRect(self.layoutBounds,self.bounds)||!UIEdgeInsetsEqualToEdgeInsets(self.layoutInsets,insets)){
        // Rotation invalidates both UIKit button tracking and SDL drag origins.
        [self releaseInputs];self.layoutBounds=self.bounds;self.layoutInsets=insets;
    }
    CGFloat left=insets.left+16,right=self.bounds.size.width-insets.right-16,bottom=self.bounds.size.height-insets.bottom-16;
    // Follow the earlier TH07 port: large Z at the right thumb, smaller X to
    // its left and S above, with a concentric joystick for the left thumb.
    const CGFloat scale=touhou::ios::preference(@"size");
    const CGFloat radius=std::clamp(std::min(self.bounds.size.width,self.bounds.size.height)*.064*scale,CGFloat(30),CGFloat(70));
    const CGFloat joystickRadius=std::max(CGFloat(60),radius*1.48);
    self.joystick.frame=CGRectMake(left,bottom-joystickRadius*2,joystickRadius*2,joystickRadius*2);
    const CGFloat actionX=right-radius*1.06,actionY=bottom-radius*1.06;
    float vx=0,vy=0,vw=1,vh=1;sdl_viewport_rect(&vx,&vy,&vw,&vh);
    const CGFloat utilityY=self.portraitGameplay?std::max(insets.top+32,vy*self.bounds.size.height+28):insets.top+32;
    const CGPoint centers[]={CGPointMake(actionX,actionY),CGPointMake(actionX-radius*.80,actionY-radius*1.95),
                             CGPointMake(actionX-radius*2.0,actionY),CGPointMake(right-22,utilityY),CGPointMake(left+22,utilityY)};
    const CGFloat diameters[]={radius*2.12,radius*1.68,radius*1.72,44,44};
    for(NSUInteger i=0;i<self.buttons.count;i++){
        UIButton* button=self.buttons[i];button.bounds=CGRectMake(0,0,diameters[i],diameters[i]);button.center=centers[i];
        button.layer.cornerRadius=diameters[i]/2;
        if(i<3)button.titleLabel.font=[UIFont systemFontOfSize:std::clamp(diameters[i]*.36,CGFloat(22),CGFloat(32)) weight:UIFontWeightSemibold];
    }
    NSArray* editables=[self.buttons arrayByAddingObject:self.joystick];
    NSString* direction=self.bounds.size.height>=self.bounds.size.width?@"portrait":@"landscape";
    for(NSUInteger i=0;i<editables.count;i++){
        UIView* control=editables[i];NSString* key=[NSString stringWithFormat:@"TH11.layout.%@.%lu",direction,(unsigned long)i];
        NSArray* saved=[NSUserDefaults.standardUserDefaults arrayForKey:key];
        if(saved.count==2)control.center=CGPointMake([saved[0] doubleValue]*self.bounds.size.width,[saved[1] doubleValue]*self.bounds.size.height);
        else if(touhou::ios::preference(@"leftHand"))control.center=CGPointMake(self.bounds.size.width-control.center.x,control.center.y);
        CGFloat mx=control.bounds.size.width/2,my=control.bounds.size.height/2;
        control.center=CGPointMake(std::clamp(control.center.x,insets.left+mx,self.bounds.size.width-insets.right-mx),std::clamp(control.center.y,insets.top+my,self.bounds.size.height-insets.bottom-my));
        BOOL action=i<3||control==self.joystick;
        control.alpha=self.editing?1:(action&&touhou::ios::preference(@"hidden")?0:(action?touhou::ios::preference(@"opacity"):1));
        control.userInteractionEnabled=self.editing||(!action||!touhou::ios::preference(@"hidden"));
        if(control==self.joystick&&touhou::ios::preference(@"movement")==1&&!self.editing){control.alpha=0;control.userInteractionEnabled=NO;}
    }
    self.editDone.frame=CGRectMake(CGRectGetMidX(self.bounds)-70,insets.top+10,140,44);
    self.performanceLabel.frame=CGRectMake(CGRectGetMidX(self.bounds)-125,insets.top+58,250,24);
    self.performanceLabel.hidden=!touhou::ios::preference(@"performance");
    NSArray* developerPosition=[NSUserDefaults.standardUserDefaults arrayForKey:[NSString stringWithFormat:@"TH11.developerPosition.%@",direction]];
    CGPoint developerCenter=CGPointMake(right-22,utilityY+60);
    if(developerPosition.count==2)developerCenter=CGPointMake([developerPosition[0] doubleValue]*self.bounds.size.width,[developerPosition[1] doubleValue]*self.bounds.size.height);
    self.developerButton.bounds=CGRectMake(0,0,48,48);
    self.developerButton.center=CGPointMake(std::clamp(developerCenter.x,insets.left+24,self.bounds.size.width-insets.right-24),std::clamp(developerCenter.y,insets.top+24,self.bounds.size.height-insets.bottom-24));
    self.developerButton.hidden=self.editing||!touhou::ios::preference(@"developer")||!sdl_developer_available();
    // Every orientation fills the display; safe areas constrain controls only.
    // During portrait battle the renderer places the original HUD above the
    // cropped playfield, and uses the identical rectangle for touch conversion.
    sdl_set_viewport(0,0,1,1);
    sdl_set_safe_top(self.bounds.size.height>0?float(insets.top/self.bounds.size.height):0);
}
- (void)joystickChanged:(TH11Joystick*)joystick {
    // Shared mode 3 suppresses viewport dragging. Use it while the joystick
    // owns movement, then restore mode 0 so normal area dragging still works.
    const bool engaged=joystick.engaged&&lifecycle.running();
    if(engaged!=stickMode){stickMode=engaged;sdl_touch_mode(engaged?3:0);}
    stickX=engaged?joystick.sample.x:0;stickY=engaged?joystick.sample.y:0;
    controls();
}
- (void)developerTapped {if(!self.editing&&lifecycle.running())showDeveloper();}
- (void)developerPan:(UIPanGestureRecognizer*)pan {
    if(self.editing||!lifecycle.running())return;
    if(pan.state==UIGestureRecognizerStateBegan)[self releaseInputs];
    CGPoint delta=[pan translationInView:self];UIEdgeInsets insets=self.safeAreaInsets;
    self.developerButton.center=CGPointMake(std::clamp(self.developerButton.center.x+delta.x,insets.left+24,self.bounds.size.width-insets.right-24),std::clamp(self.developerButton.center.y+delta.y,insets.top+24,self.bounds.size.height-insets.bottom-24));
    [pan setTranslation:CGPointZero inView:self];
    if(pan.state==UIGestureRecognizerStateEnded){
        NSString* direction=self.bounds.size.height>=self.bounds.size.width?@"portrait":@"landscape";
        [NSUserDefaults.standardUserDefaults setObject:@[@(self.developerButton.center.x/self.bounds.size.width),@(self.developerButton.center.y/self.bounds.size.height)] forKey:[NSString stringWithFormat:@"TH11.developerPosition.%@",direction]];
    }
}
- (void)layoutPan:(UIPanGestureRecognizer*)pan {
    if(!self.editing)return;UIView* view=pan.view;CGPoint delta=[pan translationInView:self];
    CGFloat marginX=view.bounds.size.width/2,marginY=view.bounds.size.height/2;
    view.center=CGPointMake(std::clamp(view.center.x+delta.x,marginX,self.bounds.size.width-marginX),std::clamp(view.center.y+delta.y,marginY+self.safeAreaInsets.top,self.bounds.size.height-marginY-self.safeAreaInsets.bottom));
    [pan setTranslation:CGPointZero inView:self];
}
- (void)finishLayout {
    NSString* direction=self.bounds.size.height>=self.bounds.size.width?@"portrait":@"landscape";
    NSArray* controls=[self.buttons arrayByAddingObject:self.joystick];
    for(NSUInteger i=0;i<controls.count;i++){
        UIView* view=controls[i];NSString* key=[NSString stringWithFormat:@"TH11.layout.%@.%lu",direction,(unsigned long)i];
        [NSUserDefaults.standardUserDefaults setObject:@[@(view.center.x/self.bounds.size.width),@(view.center.y/self.bounds.size.height)] forKey:key];
        for(UIGestureRecognizer* g in view.gestureRecognizers)g.enabled=NO;
    }
    self.editing=NO;self.editDone.hidden=YES;[self setNeedsLayout];void (^finished)(void)=self.layoutFinished;self.layoutFinished=nil;if(finished)finished();
}
- (void)down:(UIButton*)button {
    if(self.editing)return;
    // Diagnostics remain available after a terminal frame result.
    if(button.tag==8){showSettings(button);return;}
    if(!lifecycle.running()||(self.pressedButtons&(1u<<button.tag)))return;
    self.pressedButtons|=1u<<button.tag;
    if(touhou::ios::preference(@"haptics")){UIImpactFeedbackGenerator* feedback=[[UIImpactFeedbackGenerator alloc]initWithStyle:UIImpactFeedbackStyleLight];[feedback impactOccurred];}
    if(button.tag==4){shooting=touhou::ios::preference(@"toggleFire")&&sdl_game_status()[0]==7?!shooting:true;sdl_key("KeyZ",shooting);}
    else if(button.tag==5){focusing=touhou::ios::preference(@"toggleSlow")?!focusing:true;}
    else if(button.tag==6){++bombSerial;sdl_key("KeyX",1);}
    else {++pauseSerial;}
    controls();buttonAppearance(button,true);
}
- (void)reenter:(UIButton*)button {
    // Continuous controls may be re-entered; a Bomb/pause touch fires once.
    if((button.tag==4&&touhou::ios::preference(@"toggleFire")&&sdl_game_status()[0]==7)||(button.tag==5&&touhou::ios::preference(@"toggleSlow")))return;
    if(button.tag<6)[self down:button];
}
- (void)up:(UIButton*)button {
    self.pressedButtons&=~(1u<<button.tag);
    if(button.tag==4&&(!touhou::ios::preference(@"toggleFire")||sdl_game_status()[0]!=7)){shooting=false;sdl_key("KeyZ",0);}
    else if(button.tag==5&&!touhou::ios::preference(@"toggleSlow"))focusing=false;
    else if(button.tag==6)sdl_key("KeyX",0);
    controls();buttonAppearance(button,button.tag==4?shooting:button.tag==5?focusing:false);
}
- (void)releaseInputs {
    self.pressedButtons=0;shooting=focusing=false;
    [self.joystick cancelTrackingWithEvent:nil];
    stickX=stickY=0;
    sdl_keys_clear();controls();
    SDL_FlushEvents(SDL_EVENT_FINGER_DOWN,SDL_EVENT_FINGER_CANCELED);
    for(UIButton* button in self.buttons){
        [button cancelTrackingWithEvent:nil];button.highlighted=NO;buttonAppearance(button,false);
    }
}
@end
static TH11Controls* overlay;
namespace touhou::ios {
void editControlLayout(void (^finished)(void)){
    [overlay releaseInputs];overlay.editing=YES;overlay.layoutFinished=finished;overlay.editDone.hidden=NO;
    for(UIView* control in [overlay.buttons arrayByAddingObject:overlay.joystick])for(UIGestureRecognizer* pan in control.gestureRecognizers)pan.enabled=YES;
    [overlay setNeedsLayout];
}
}
static bool settingsShowing=false;
static bool developerShowing=false;
static void pauseFor(touhou::ios::Lifecycle::Reason reason,bool paused){
    const bool changed=lifecycle.set(reason,paused);
    touhou::ios::diagnostic(@"Lifecycle reason=%u paused=%d running=%d changed=%d",unsigned(reason),paused,lifecycle.running(),changed);
    // Clear every pause source, including a second source while already paused.
    if(paused||changed)[overlay releaseInputs];
    if(!changed)return;
    if(lifecycle.running())audioSession();
    sdl_loop_pause(lifecycle.running()?0:1);
    touhou::ios::diagnosticsState(@"lifecycle transition / save");
    touhou::ios::diagnosticsFlush();
}
static void showSettings(UIButton* button){
    if(settingsShowing||developerShowing)return;settingsShowing=true;
    pauseFor(touhou::ios::Lifecycle::settings,true);
    touhou::ios::presentSettings(overlay.window.rootViewController,button,^{
        settingsShowing=false;pauseFor(touhou::ios::Lifecycle::settings,false);
    });
}
static void showDeveloper(){
    if(settingsShowing||developerShowing||!sdl_developer_available())return;developerShowing=true;
    pauseFor(touhou::ios::Lifecycle::developer,true);
    touhou::ios::presentDeveloper(overlay.window.rootViewController,^{
        developerShowing=false;pauseFor(touhou::ios::Lifecycle::developer,false);
    });
}
#if TH11_DIAGNOSTICS
@interface TH11DiagnosticTouch : UITouch
@property(nonatomic) CGPoint point;
@end
@implementation TH11DiagnosticTouch
- (CGPoint)locationInView:(UIView*)view {return self.point;}
@end
static void controlsSmoke(unsigned attempt=0){
    if(sdl_game_status()[0]!=7||!lifecycle.running()){
        if(attempt<60)dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{controlsSmoke(attempt+1);});
        else touhou::ios::diagnostic(@"CONTROLS_SMOKE FAIL battle never started");
        return;
    }
    touhou::ios::setPreference(@"toggleFire",@YES);touhou::ios::setPreference(@"toggleSlow",@YES);
    touhou::ios::setPreference(@"fps",@30);touhou::ios::setPreference(@"smooth",@YES);
    touhou::ios::applyPreferences();
    [overlay layoutIfNeeded];
    TH11Joystick* joystick=overlay.joystick;
    TH11DiagnosticTouch* touch=[[TH11DiagnosticTouch alloc]init];
    const CGFloat radius=(std::min(joystick.bounds.size.width,joystick.bounds.size.height)-56)/2;
    CGPoint center=CGPointMake(CGRectGetMidX(joystick.bounds),CGRectGetMidY(joystick.bounds));
    touch.point=CGPointMake(center.x+radius*.12,center.y);
    touhou::ios::setPreference(@"deadZone",@0);
    bool tracked=[joystick beginTrackingWithTouch:touch withEvent:nil];
    bool deadZoneOK=joystick.sample.x>.1;
    touhou::ios::setPreference(@"deadZone",@.4);
    [joystick continueTrackingWithTouch:touch withEvent:nil];deadZoneOK=deadZoneOK&&joystick.sample.x==0;
    touch.point=CGPointMake(joystick.bounds.size.width+180,center.y);
    tracked=tracked&&[joystick continueTrackingWithTouch:touch withEvent:nil]&&joystick.engaged&&joystick.sample.x>.99&&stickX>.99;
    [joystick endTrackingWithTouch:touch withEvent:nil];tracked=tracked&&!joystick.engaged&&stickX==0;
    touhou::ios::setPreference(@"deadZone",@.23);
    touhou::ios::applyPreferences();
    touhou::ios::diagnostic(@"JOYSTICK_SMOKE %@ outsideBounds=%d deadZoneLive=%d release=%d savedDeadZone=%.2f",tracked&&deadZoneOK?@"PASS":@"FAIL",tracked,deadZoneOK,!joystick.engaged,touhou::ios::preference(@"deadZone"));
    UIButton* z=overlay.buttons[0];UIButton* s=overlay.buttons[1];
    [overlay down:z];[overlay up:z];[overlay reenter:z];bool fireOK=shooting;
    [overlay down:z];[overlay up:z];fireOK=fireOK&&!shooting;
    [overlay down:s];[overlay up:s];[overlay reenter:s];bool slowOK=focusing;
    [overlay down:s];[overlay up:s];slowOK=slowOK&&!focusing;
    touhou::ios::editControlLayout(nil);[overlay layoutIfNeeded];
    CGPoint position=z.center;position.x=std::max(z.bounds.size.width/2,position.x-20);z.center=position;
    [overlay finishLayout];
    NSString* direction=overlay.bounds.size.height>=overlay.bounds.size.width?@"portrait":@"landscape";
    NSArray* saved=[NSUserDefaults.standardUserDefaults arrayForKey:[NSString stringWithFormat:@"TH11.layout.%@.0",direction]];
    bool layoutOK=saved.count==2&&fabs([saved[0] doubleValue]-position.x/overlay.bounds.size.width)<.0001;
    pauseFor(touhou::ios::Lifecycle::inactive,true);bool pauseOK=sdl_loop_is_paused()&&!shooting&&!focusing;
    pauseFor(touhou::ios::Lifecycle::inactive,false);pauseOK=pauseOK&&!sdl_loop_is_paused();
    touhou::ios::diagnostic(@"CONTROLS_SMOKE %@ toggleFire=%d toggleSlow=%d layoutSaved=%d pauseRelease=%d prefsFPS=%.0f smooth=%.0f",fireOK&&slowOK&&layoutOK&&pauseOK?@"PASS":@"FAIL",fireOK,slowOK,layoutOK,pauseOK,touhou::ios::preference(@"fps"),touhou::ios::preference(@"smooth"));
    touhou::ios::diagnosticsFlush();
}
static void dragSmokeStep(unsigned step=0){
    if(step==0){
        touhou::ios::setPreference(@"dragLimited",@NO);touhou::ios::setPreference(@"developer",@YES);touhou::ios::applyPreferences();
        sdl_developer_action(0);sdl_developer_action(3);sdl_touch(0,991,.5,.8);
    }else{
        const float* p=sdl_diagnostic_player();
        touhou::ios::diagnostic(@"DRAG_SMOKE step=%u x=%.2f y=%.2f playerTrails=%.0f bodyScript=%.0f",step,p[0],p[1],p[2],p[3]);
        if(p[2])touhou::ios::diagnostic(@"DRAG_SMOKE FAIL overlapping player trail");
        if(step==10){sdl_touch(2,991,.3,.9);touhou::ios::diagnostic(@"DRAG_SMOKE complete; native checks separately verify exact positions");touhou::ios::diagnosticsFlush();return;}
        sdl_touch(1,991,step%2?.7:.3,step%2?.3:.9);
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{dragSmokeStep(step+1);});
}
#endif
static void installControls(SDL_Window* window){
    UIWindow* native=(__bridge UIWindow*)SDL_GetPointerProperty(SDL_GetWindowProperties(window),SDL_PROP_WINDOW_UIKIT_WINDOW_POINTER,nullptr);
    UIView* parent=native.rootViewController.view;
    overlay=[[TH11Controls alloc] initWithFrame:parent.bounds];
    overlay.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    [parent addSubview:overlay];
#if TH11_DIAGNOSTICS
    if([NSProcessInfo.processInfo.arguments containsObject:@"--controls-smoke"])
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,10*NSEC_PER_SEC),dispatch_get_main_queue(),^{controlsSmoke();});
    if([NSProcessInfo.processInfo.arguments containsObject:@"--drag-smoke"])
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,8*NSEC_PER_SEC),dispatch_get_main_queue(),^{dragSmokeStep();});
    if([NSProcessInfo.processInfo.arguments containsObject:@"--landscape-smoke"]){
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{
            if(@available(iOS 16.0,*)){
                UIWindowSceneGeometryPreferencesIOS* geometry=[[UIWindowSceneGeometryPreferencesIOS alloc] initWithInterfaceOrientations:UIInterfaceOrientationMaskLandscapeLeft];
                [native.windowScene requestGeometryUpdateWithPreferences:geometry errorHandler:^(NSError* error){
                    touhou::ios::diagnostic(@"Landscape smoke rotation failed: %@",error);
                }];
            }
        });
    }
#endif
    NSNotificationCenter* center=NSNotificationCenter.defaultCenter;
    [center addObserverForName:@"TH11PreferencesChanged" object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification*){
        [overlay releaseInputs];[overlay setNeedsLayout];
    }];
    [center addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification*){
        pauseFor(touhou::ios::Lifecycle::inactive,true);
    }];
    [center addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification*){
        pauseFor(touhou::ios::Lifecycle::inactive,true);
    }];
    [center addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification*){
        pauseFor(touhou::ios::Lifecycle::inactive,false);
    }];
    [center addObserverForName:AVAudioSessionInterruptionNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification* note){
        NSNumber* type=note.userInfo[AVAudioSessionInterruptionTypeKey];
        if(!type)return;
        touhou::ios::diagnostic(@"Audio interruption: type=%@ options=%@",type,note.userInfo[AVAudioSessionInterruptionOptionKey]);
        if(type.unsignedIntegerValue==AVAudioSessionInterruptionTypeBegan)
            pauseFor(touhou::ios::Lifecycle::audioInterruption,true);
        else if(type.unsignedIntegerValue==AVAudioSessionInterruptionTypeEnded)
            pauseFor(touhou::ios::Lifecycle::audioInterruption,false);
    }];
    [center addObserverForName:AVAudioSessionRouteChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification* note){
        touhou::ios::diagnostic(@"Audio route changed: reason=%@",note.userInfo[AVAudioSessionRouteChangeReasonKey]);
        if(lifecycle.running())audioSession();
    }];
    [center addObserverForName:UIApplicationDidReceiveMemoryWarningNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification*){
        touhou::ios::diagnosticsState(@"memory warning");touhou::ios::diagnosticsFlush();
    }];
    [center addObserverForName:UIApplicationWillTerminateNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification*){
        touhou::ios::diagnostic(@"Application will terminate");touhou::ios::diagnosticsFlush();
    }];
    pauseFor(touhou::ios::Lifecycle::inactive,UIApplication.sharedApplication.applicationState!=UIApplicationStateActive);
}
static void frame(void*){
    @autoreleasepool {
        if(!lifecycle.running())return;
#if TH11_DIAGNOSTICS
        if(smoke){
            const bool battle=sdl_game_status()[0]==7;
            const bool confirm=frames>=20&&((frames-20)%45)<3;
            sdl_key("KeyZ",battle||confirm);
        }
#endif
        const double started=double(SDL_GetTicksNS())/1000000000.;
        const uint64_t ticksBefore=touhou::sdl::nativePerformance.ticks;
        int result=sdl_loop_frame(started);
        if(sdl_game_status()[7]){
            touhou::ios::diagnostic(@"Original Quit menu selected; saving and closing");
            sdl_loop_stop();touhou::ios::diagnosticsFlush();std::exit(0);
        }
        BOOL portraitGameplay=sdl_game_status()[6];
        overlay.developerButton.hidden=overlay.editing||!touhou::ios::preference(@"developer")||!sdl_developer_available();
        if(overlay.portraitGameplay!=portraitGameplay){overlay.portraitGameplay=portraitGameplay;[overlay setNeedsLayout];}
        if(result){touhou::ios::diagnostic(@"TH11 frame result %d",result);pauseFor(touhou::ios::Lifecycle::stopped,true);}
        static double perfStart=0;static uint64_t perfFrames=0,perfTicks=0;
        if(!perfStart)perfStart=started;++perfFrames;
        perfTicks+=touhou::sdl::nativePerformance.ticks-ticksBefore;
        if(started-perfStart>=1){overlay.performanceLabel.text=[NSString stringWithFormat:@"%.0f 回调/s · %.0f 更新/s",perfFrames/(started-perfStart),perfTicks/(started-perfStart)];perfStart=started;perfFrames=perfTicks=0;}
        touhou::ios::diagnosticsFrame(started,double(SDL_GetTicksNS())/1000000000.-started,++frames);
    }
}
int main(int argc,char** argv){
    @autoreleasepool {
        touhou::ios::diagnosticsStart();
#if TH11_DIAGNOSTICS
        bool stageSmoke=false;
        int diagnosticShot=0;
        for(int i=1;i<argc;i++){if(!strcmp(argv[i],"--smoke"))smoke=true;if(!strcmp(argv[i],"--stage-smoke"))stageSmoke=true;if(!strcmp(argv[i],"--aya-smoke"))diagnosticShot=2;}
#endif
        SDL_SetHint(SDL_HINT_ORIENTATIONS,"LandscapeLeft LandscapeRight Portrait");
        SDL_SetHint(SDL_HINT_TOUCH_MOUSE_EVENTS,"0");
        SDL_SetHint(SDL_HINT_MOUSE_TOUCH_EVENTS,"0");
        touhou::ios::diagnostic(@"SDL initialization begins; smoke=%d",smoke);
        if(!SDL_Init(SDL_INIT_VIDEO|SDL_INIT_AUDIO|SDL_INIT_EVENTS|SDL_INIT_JOYSTICK)){touhou::ios::diagnostic(@"SDL initialization failed: %s",SDL_GetError());touhou::ios::diagnosticsFlush();return 1;}
        touhou::ios::diagnostic(@"SDL initialized; opening Japanese TH11 game");
        audioSession();UIApplication.sharedApplication.idleTimerDisabled=YES;
        auto* game=sdl_game_open(0,smoke?12345:uint32_t(std::time(nullptr)));
        if(!game){touhou::ios::diagnostic(@"TH11 initialization failed: %s file=%s",SDL_GetError(),sdl_file_error());touhou::ios::diagnosticsFlush();return 2;}
        auto* window=static_cast<SDL_Window*>(sdl_window());
        if(!window){touhou::ios::diagnostic(@"TH11 window missing");touhou::ios::diagnosticsFlush();return 3;}
#if TH11_DIAGNOSTICS
        if(stageSmoke){
            const bool ok=sdl_diagnostic_stage(diagnosticShot);
            touhou::ios::diagnostic(@"STAGE_SMOKE %@ direct first stage: %s",ok?@"PASS":@"FAIL",sdl_file_error());
            if(!ok){touhou::ios::diagnosticsFlush();return 5;}
        }
#endif
        sdl_touch_options(1,0,1);sdl_touch_gestures(0,0);controls();
        sdl_loop_start(game);installControls(window);touhou::ios::applyPreferences();
        if(!SDL_SetiOSAnimationCallback(window,1,frame,nullptr)){touhou::ios::diagnostic(@"TH11 display callback failed: %s",SDL_GetError());touhou::ios::diagnosticsFlush();return 4;}
        touhou::ios::diagnostic(@"TH11 native started, Japanese, logic=60Hz, ARM64 device / simulator diagnostic separated");
        touhou::ios::diagnostic(@"Preferences startup fps=%.0f smooth=%.0f deadZone=%.2f; fullscreen with portrait top HUD",touhou::ios::preference(@"fps"),touhou::ios::preference(@"smooth"),touhou::ios::preference(@"deadZone"));
#if TH11_DIAGNOSTICS
        touhou::ios::diagnostic(@"FEATURES_STARTUP dragLimited=%.0f developer=%.0f state=%d",touhou::ios::preference(@"dragLimited"),touhou::ios::preference(@"developer"),sdl_diagnostic_features());
#endif
        touhou::ios::diagnosticsState(@"startup complete");touhou::ios::diagnosticsFlush();
        return 0;
    }
}
