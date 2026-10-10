#import "Diagnostics.hpp"
#import <AVFoundation/AVFoundation.h>
#include "NativeHost.hpp"
#include "NativePerformance.hpp"
#include "Renderer.hpp"
#include "Preferences.hpp"
#include "NativeOptions.hpp"
#include <SDL3/SDL.h>
#include <algorithm>
#include <cerrno>
#include <cstdarg>
#include <cstdio>
#include <cstring>
#include <fcntl.h>
#include <mutex>
#include <signal.h>
#include <sys/stat.h>
#include <sys/sysctl.h>
#include <sys/utsname.h>
#include <unistd.h>
#include <vector>

namespace {
constexpr off_t maxLogBytes=1024*1024;
int logFD=-1,consoleFD=-1,stderrReadFD=-1;
std::mutex logMutex;
std::mutex stderrMutex;
NSURL* logDirectory;
dispatch_source_t stderrSource;
SDL_LogOutputFunction originalSDLLog=nullptr;
void* originalSDLUserdata=nullptr;
NSUncaughtExceptionHandler* originalExceptionHandler=nullptr;
constexpr int fatalSignals[]={SIGABRT,SIGSEGV,SIGBUS,SIGILL,SIGFPE};
struct sigaction originalSignalActions[5]{};
#if TH11_DIAGNOSTICS
std::uint64_t observedCallbacks=0;
void startSettingsSmoke();
void startFeaturesSmoke();
void startKeyboardSmoke();
#endif

void writeAll(int fd,const void* bytes,size_t length){
    const char* data=static_cast<const char*>(bytes);
    while(fd>=0&&length){
        const ssize_t written=write(fd,data,length);
        if(written<0&&errno==EINTR)continue;
        if(written<=0)break;
        data+=written;length-=size_t(written);
    }
}
void appendLog(const void* bytes,size_t length){
    std::lock_guard<std::mutex> guard(logMutex);
    if(logFD<0)return;
    struct stat status{};
    if(fstat(logFD,&status)==0&&status.st_size+off_t(length)>maxLogBytes){
        // Retain the startup section and the newest half MiB when bounded.
        constexpr size_t headerBytes=16*1024,tailBytes=512*1024;
        std::vector<char> header(headerBytes),tail(tailBytes);
        const ssize_t head=pread(logFD,header.data(),header.size(),0);
        const ssize_t end=pread(logFD,tail.data(),tail.size(),std::max<off_t>(headerBytes,status.st_size-tailBytes));
        if(head>=0&&end>=0&&ftruncate(logFD,0)==0){
            writeAll(logFD,header.data(),size_t(head));
            constexpr char marker[]="\n--- older middle log entries removed to bound disk usage ---\n";
            writeAll(logFD,marker,sizeof(marker)-1);
            writeAll(logFD,tail.data(),size_t(end));
        }
    }
    writeAll(logFD,bytes,length);
}
void drainStderr(){
    // Flush/export waits for a reader that already consumed pipe bytes to
    // finish appending them before it snapshots the log.
    std::lock_guard<std::mutex> guard(stderrMutex);
    char bytes[4096];
    for(unsigned block=0;block<16;block++){
        const ssize_t count=read(stderrReadFD,bytes,sizeof(bytes));
        if(count<0&&errno==EINTR)continue;
        if(count<=0)break;
        writeAll(consoleFD,bytes,size_t(count));
        appendLog(bytes,size_t(count));
    }
}
void captureStderr(){
    consoleFD=dup(STDERR_FILENO);
    int descriptors[2];
    if(consoleFD<0)return;
    const int consoleFlags=fcntl(consoleFD,F_GETFL);
    if(consoleFlags<0||fcntl(consoleFD,F_SETFL,consoleFlags|O_NONBLOCK)<0){close(consoleFD);consoleFD=-1;return;}
#ifdef F_SETNOSIGPIPE
    fcntl(consoleFD,F_SETNOSIGPIPE,1);
#endif
    if(pipe(descriptors)!=0)return;
    stderrReadFD=descriptors[0];
    const int flags=fcntl(stderrReadFD,F_GETFL);
    const int writeFlags=fcntl(descriptors[1],F_GETFL);
    // A stopped console consumer or stderr flood must never block gameplay.
    // Direct diagnostic records are still persisted if console output drops.
    if(flags<0||writeFlags<0||fcntl(stderrReadFD,F_SETFL,flags|O_NONBLOCK)<0||
       fcntl(descriptors[1],F_SETFL,writeFlags|O_NONBLOCK)<0){close(descriptors[0]);close(descriptors[1]);stderrReadFD=-1;return;}
    if(dup2(descriptors[1],STDERR_FILENO)<0){close(descriptors[0]);close(descriptors[1]);stderrReadFD=-1;return;}
    close(descriptors[1]);setvbuf(stderr,nullptr,_IONBF,0);
    stderrSource=dispatch_source_create(DISPATCH_SOURCE_TYPE_READ,uintptr_t(stderrReadFD),0,
                                       dispatch_get_global_queue(QOS_CLASS_UTILITY,0));
    if(!stderrSource){dup2(consoleFD,STDERR_FILENO);close(stderrReadFD);stderrReadFD=-1;return;}
    dispatch_source_set_event_handler(stderrSource,^{drainStderr();});
    dispatch_resume(stderrSource);
}
void SDLCALL captureSDL(void*,int category,SDL_LogPriority priority,const char* message){
    touhou::ios::diagnostic(@"SDL category=%d priority=%d %s",category,int(priority),message?message:"");
    if(originalSDLLog)originalSDLLog(originalSDLUserdata,category,priority,message);
}
void captureException(NSException* exception){
    touhou::ios::diagnostic(@"Uncaught exception %@: %@\n%@",exception.name,exception.reason,exception.callStackSymbols);
    touhou::ios::diagnosticsFlush();
    if(originalExceptionHandler)originalExceptionHandler(exception);
}
void captureFatalSignal(int number){
    // Only async-signal-safe I/O here: preserve pending stderr before abort.
    char bytes[4096];ssize_t count;
    for(unsigned block=0;block<16&&stderrReadFD>=0&&(count=read(stderrReadFD,bytes,sizeof(bytes)))>0;block++){
        writeAll(consoleFD,bytes,size_t(count));writeAll(logFD,bytes,size_t(count));
    }
    char marker[]="\nTH11 fatal signal 00 (see iOS crash report for stack)\n";
    marker[19]=char('0'+number/10);marker[20]=char('0'+number%10);
    writeAll(consoleFD,marker,sizeof(marker)-1);writeAll(logFD,marker,sizeof(marker)-1);
    if(logFD>=0)fsync(logFD);
    for(size_t i=0;i<5;i++)if(fatalSignals[i]==number){sigaction(number,&originalSignalActions[i],nullptr);break;}
    // Re-raise on the faulting thread, not an arbitrary process thread.
    raise(number);
}
NSURL* exportSnapshot(NSError** error){
    if(!logDirectory||logFD<0){
        if(error)*error=[NSError errorWithDomain:@"TH11Diagnostics" code:1 userInfo:@{NSLocalizedDescriptionKey:@"无法访问本机日志目录。请检查存储空间后重新打开游戏。"}];
        return nil;
    }
    touhou::ios::diagnosticsState(@"export requested");
    touhou::ios::diagnosticsFlush();
    NSMutableData* combined=[NSMutableData data];
    {
        std::lock_guard<std::mutex> guard(logMutex);
        for(NSString* name in @[@"previous.log",@"current.log"]){
            NSData* label=[[NSString stringWithFormat:@"\n========== %@ ==========\n",name] dataUsingEncoding:NSUTF8StringEncoding];
            [combined appendData:label];
            NSError* readError=nil;
            NSData* content=[NSData dataWithContentsOfURL:[logDirectory URLByAppendingPathComponent:name] options:0 error:&readError];
            if(!content&&([name isEqualToString:@"current.log"]||readError.code!=NSFileReadNoSuchFileError)){
                if(error)*error=readError;return nil;
            }
            [combined appendData:content?:[@"(No previous run is available.)\n" dataUsingEncoding:NSUTF8StringEncoding]];
        }
    }
    NSURL* file=[logDirectory URLByAppendingPathComponent:@"TH11-diagnostics.txt"];
    if(![combined writeToURL:file options:NSDataWritingAtomic error:error])return nil;
    return file;
}
}

namespace touhou::ios {
void diagnostic(NSString* format,...){
    @autoreleasepool {
        va_list arguments;va_start(arguments,format);
        NSString* message=[[NSString alloc] initWithFormat:format arguments:arguments];
        va_end(arguments);
        if(message.length>8192)message=[[message substringToIndex:8192] stringByAppendingString:@" [truncated]"];
        NSString* line=[NSString stringWithFormat:@"[%@] %@\n",NSDate.date,message];
        NSData* data=[line dataUsingEncoding:NSUTF8StringEncoding];
        appendLog(data.bytes,data.length);
        writeAll(consoleFD>=0?consoleFD:STDERR_FILENO,data.bytes,data.length);
    }
}
void diagnosticsFlush(){
    fflush(stderr);
    if(stderrReadFD>=0)drainStderr();
    std::lock_guard<std::mutex> guard(logMutex);
    if(logFD>=0)fsync(logFD);
}
void diagnosticsStart(){
    if(logFD>=0)return; // Reinitializing would capture our own SDL callback.
    NSFileManager* manager=NSFileManager.defaultManager;
    NSURL* documents=[manager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
    logDirectory=[documents URLByAppendingPathComponent:@"Diagnostics" isDirectory:YES];
    NSError* error=nil;
    if(![manager createDirectoryAtURL:logDirectory withIntermediateDirectories:YES attributes:nil error:&error]){
        NSLog(@"TH11 cannot create diagnostic directory: %@",error);return;
    }
    [logDirectory setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nullptr];
    NSURL* current=[logDirectory URLByAppendingPathComponent:@"current.log"];
    NSURL* previous=[logDirectory URLByAppendingPathComponent:@"previous.log"];
    if([manager fileExistsAtPath:current.path]){
        [manager removeItemAtURL:previous error:nullptr];
        if(![manager moveItemAtURL:current toURL:previous error:&error]){
            NSLog(@"TH11 cannot preserve previous diagnostic log: %@",error);return;
        }
    }
    logFD=open(current.fileSystemRepresentation,O_CREAT|O_RDWR|O_APPEND,0600);
    if(logFD<0){NSLog(@"TH11 cannot open diagnostic log: %s",std::strerror(errno));return;}
    [manager setAttributes:@{NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication}
             ofItemAtPath:current.path error:nullptr];
    captureStderr();
    SDL_GetLogOutputFunction(&originalSDLLog,&originalSDLUserdata);
    SDL_SetLogOutputFunction(captureSDL,nullptr);
    originalExceptionHandler=NSGetUncaughtExceptionHandler();
    NSSetUncaughtExceptionHandler(captureException);
    for(size_t i=0;i<5;i++){
        struct sigaction action{};action.sa_handler=captureFatalSignal;sigemptyset(&action.sa_mask);
        sigaction(fatalSignals[i],&action,&originalSignalActions[i]);
    }
    struct utsname hardware{};uname(&hardware);
    char osBuild[128]{};size_t size=sizeof(osBuild);sysctlbyname("kern.osversion",osBuild,&size,nullptr,0);
    NSDictionary* info=NSBundle.mainBundle.infoDictionary;
    diagnostic(@"TH11 session started; device=%s model=%@ OS=%@ build=%s app=%@ (%@) diagnostics=%@",
               hardware.machine,UIDevice.currentDevice.model,UIDevice.currentDevice.systemVersion,osBuild,
               info[@"CFBundleShortVersionString"],info[@"CFBundleVersion"],info[@"TH11Diagnostics"]);
    diagnostic(@"Logs are local only; current and previous runs retain at most 1 MiB each; game assets/saves are never exported.");
    diagnosticsFlush();
#if TH11_DIAGNOSTICS
    if([NSProcessInfo.processInfo.arguments containsObject:@"--settings-smoke"])startSettingsSmoke();
    if([NSProcessInfo.processInfo.arguments containsObject:@"--features-smoke"])startFeaturesSmoke();
    if([NSProcessInfo.processInfo.arguments containsObject:@"--keyboard-smoke"])startKeyboardSmoke();
#endif
}
void diagnosticsState(NSString* reason){
    const int32_t* state=sdl_game_status();
    diagnostic(@"State %@: screen=%d stage=%d error=%d lives=%d power=%d context=%d portraitHUD=%d quit=%d frame=%d phase=%d loopPaused=%d fileError=%s SDL=%s",
               reason,state[0],state[1],state[2],state[3],state[4],state[5],state[6],state[7],state[8],state[9],
               sdl_loop_is_paused(),sdl_file_error(),SDL_GetError());
    const auto* audio=th11_audio_statistics();
    diagnostic(@"Audio ready=%u buffers=%u mixedFrames=%u error=%u queued=%u track=%u",audio[0],audio[1],audio[2],audio[3],audio[4],audio[5]);
}
void diagnosticsFrame(double timestamp,double workSeconds,std::uint64_t callbacks){
#if TH11_DIAGNOSTICS
    observedCallbacks=callbacks;
#endif
    static double begin=0,previous=0,workSum=0,workMax=0,gapMax=0;
    static unsigned count=0;
    if(!begin)begin=timestamp;
    if(previous)gapMax=std::max(gapMax,timestamp-previous);
    previous=timestamp;workSum+=workSeconds;workMax=std::max(workMax,workSeconds);++count;
    if(callbacks<=3||timestamp-begin>=10){
        diagnostic(@"Frame callbacks=%llu sample=%u wall=%.3fs meanWork=%.2fms maxWork=%.2fms maxGap=%.2fms",
                   static_cast<unsigned long long>(callbacks),count,timestamp-begin,workSum/count*1000,workMax*1000,gapMax*1000);
        const auto& perf=touhou::sdl::nativePerformance;
        const double ticks=std::max(1.,double(perf.ticks)),draws=std::max(1.,double(perf.draws)),presents=std::max(1.,double(perf.callbacks));
        const auto gpu=*sdl_stats();static touhou::sdl::Statistics lastGPU{};
        diagnostic(@"Performance ticks=%llu draws=%llu logicPerTick=%.3fms drawPerFrame=%.3fms flushPerTick=%.3fms audioPerCallback=%.3fms presentPerCallback=%.3fms loadingTotal=%.2fms batches=%u uploadKB=%.1f vertexKB=%.1f readKB=%.1f bufferReplacements=%u subUpdates=%u genericBatches=%u",
                   (unsigned long long)perf.ticks,(unsigned long long)perf.draws,perf.logic/ticks,perf.draw/draws,perf.flush/ticks,
                   perf.audio/presents,perf.present/presents,perf.loading,gpu.batches-lastGPU.batches,
                   (gpu.uploadBytes-lastGPU.uploadBytes)/1024.,(gpu.vertexUploadBytes-lastGPU.vertexUploadBytes)/1024.,
                   (gpu.readBytes-lastGPU.readBytes)/1024.,gpu.bufferReplacements-lastGPU.bufferReplacements,
                   gpu.bufferSubUpdates-lastGPU.bufferSubUpdates,gpu.genericBatches-lastGPU.genericBatches);
        // These are CPU time inside GL calls, including driver waits, not GPU timestamps.
        diagnostic(@"Graphics CPU streamPerFrame=%.3fms submitPerFrame=%.3fms layouts=%u textureBinds=%u framebufferBinds=%u resamples=%u presents=%u",
                   perf.stream/draws,perf.submit/draws,gpu.layoutSetups-lastGPU.layoutSetups,
                   gpu.textureBinds-lastGPU.textureBinds,gpu.framebufferBinds-lastGPU.framebufferBinds,
                   gpu.resamples-lastGPU.resamples,gpu.presentations-lastGPU.presentations);
        touhou::sdl::nativePerformance={};lastGPU=gpu;
        diagnosticsState(@"periodic");diagnosticsFlush();
        begin=timestamp;workSum=workMax=gapMax=0;count=0;
    }
}
}


@interface TH11SettingsController : UITableViewController<UIAdaptivePresentationControllerDelegate,UIPopoverPresentationControllerDelegate>
@property(nonatomic,copy) void (^finished)(void);
@property(nonatomic) BOOL didFinish;
@property(nonatomic) BOOL closing;
@property(nonatomic,copy) NSString* unlockFeedback;
- (int)confirmUnlockPrompt:(UIAlertController*)prompt;
- (void)closeSettings;
- (void)finishSharing;
@end
@implementation TH11SettingsController
- (NSArray*)rows {
 return @[
 @[@[@"movement",@"移动模式",@"混合支持摇杆或相对拖动",@"segment"],@[@"dragLimited",@"拖拽限速",@"开启：遵循原版速度；关闭：立即跟随拖动",@"switch"],@[@"hidden",@"No Button",@"隐藏 X / S / Z 与摇杆，保留设置和暂停",@"switch"],@[@"layout",@"自由调整按键与摇杆位置",@"横屏、竖屏分别保存",@"action"],@[@"toggleFire",@"Z 点击保持射击",@"再点一次停止；菜单仍按住确认",@"switch"],@[@"toggleSlow",@"S 点击保持低速",@"再点一次恢复高速",@"switch"],@[@"autoFire",@"自动射击",@"进入战斗后自动按住 Z",@"switch"],@[@"autoSlow",@"自动低速",@"进入战斗后自动按住 S",@"switch"],@[@"autoBomb",@"自动 Bomb",@"真正中弹前自动释放，按原作消耗火力；不足则正常受击",@"switch"],@[@"dragFire",@"拖拽移动时自动射击",@"松手后恢复原有射击状态",@"switch"]],
 @[@[@"opacity",@"按键透明度",@"",@"slider"],@[@"size",@"按键与摇杆大小",@"",@"slider"],@[@"sensitivity",@"拖动灵敏度",@"",@"slider"],@[@"deadZone",@"摇杆中心死区（0–40%）",@"",@"slider"],@[@"leftHand",@"左手按键布局",@"默认位置左右互换，自定义位置优先",@"switch"],@[@"haptics",@"按键触感反馈",@"在支持触感反馈的设备上生效",@"switch"]],
 @[@[@"fps",@"显示帧率",@"",@"segment"],@[@"smooth",@"平滑缩放",@"关闭时保留清晰的像素边缘",@"switch"],@[@"performance",@"显示性能信息",@"显示回调频率与逻辑更新频率",@"switch"],],
 @[@[@"twoFinger",@"双指低速",@"在游戏区域按住两指时低速移动",@"switch"],@[@"doubleTap",@"双击 Bomb",@"战斗中在同一位置快速双击",@"switch"],@[@"export",@"导出诊断日志",@"包含本次与上次运行记录",@"action"],@[@"reset",@"恢复默认设置与按键布局",@"保留游戏成绩及解锁内容",@"action"],],
 @[@[@"developer",@"开发者功能",@"战斗中显示可拖动的开发者悬浮按钮",@"switch"],@[@"unlock",@"输入作弊码 · 解锁全部内容",self.unlockFeedback?:@"确认正确代码后永久解锁 Extra、练习关卡和音乐",@"action"]]
 ];
}
- (void)viewDidLoad {
 [super viewDidLoad];self.title=@"设置";self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"完成" style:UIBarButtonItemStyleDone target:self action:@selector(closeSettings)];self.preferredContentSize=CGSizeMake(720,760);
 UITapGestureRecognizer* back=[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(closeSettings)];back.numberOfTouchesRequired=2;[self.view addGestureRecognizer:back];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView*)tableView{return self.rows.count;}
- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section{return [self.rows[section] count];}
- (NSString*)tableView:(UITableView*)tableView titleForHeaderInSection:(NSInteger)section{return @[@"操作方式",@"摇杆与按键",@"画面与性能",@"手势与诊断",@"开发者与解锁"][section];}
- (CGFloat)tableView:(UITableView*)tableView heightForRowAtIndexPath:(NSIndexPath*)p{NSString* type=self.rows[p.section][p.row][3];return [type isEqual:@"segment"]||[type isEqual:@"slider"]?116:88;}
- (NSArray*)values:(NSString*)key{return [key isEqual:@"movement"]?@[@0,@1,@2]:[key isEqual:@"fps"]?@[@60,@30]:@[@.5,@.75,@1];}
- (NSString*)valueLabel:(NSString*)key value:(double)value{return [key isEqual:@"sensitivity"]?[NSString stringWithFormat:@"%.2f×",value]:[NSString stringWithFormat:@"%.0f%%",value*100];}
- (void)settingChanged:(UIControl*)control {
 NSArray* row=self.rows[control.tag/100][control.tag%100];NSString* key=row[0];NSNumber* value;
 if([control isKindOfClass:UISwitch.class])value=@(((UISwitch*)control).on);
 else if([control isKindOfClass:UISegmentedControl.class])value=[self values:key][((UISegmentedControl*)control).selectedSegmentIndex];
 else {value=@(((UISlider*)control).value);UILabel* label=(UILabel*)[control.superview viewWithTag:9001];label.text=[self valueLabel:key value:value.doubleValue];}
 touhou::ios::setPreference(key,value);touhou::ios::applyPreferences();
}
- (UITableViewCell*)tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)p {
 NSArray* row=self.rows[p.section][p.row];NSString* key=row[0],*type=row[3];double value=touhou::ios::preference(key);
 UITableViewCell* cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];cell.selectionStyle=UITableViewCellSelectionStyleNone;cell.accessibilityIdentifier=[@"th11.setting." stringByAppendingString:key];
 if([type isEqual:@"segment"]||[type isEqual:@"slider"]){
  UILabel* title=[[UILabel alloc] init];title.text=row[1];title.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];UIControl* control;
  if([type isEqual:@"segment"]){NSArray* labels=[key isEqual:@"movement"]?@[@"混合",@"拖动",@"摇杆"]:[key isEqual:@"fps"]?@[@"60 FPS",@"30 FPS"]:@[@"50%",@"75%",@"100%"];
   UISegmentedControl* segment=[[UISegmentedControl alloc] initWithItems:labels];NSArray* vals=[self values:key];segment.selectedSegmentIndex=0;for(NSUInteger i=0;i<vals.count;i++)if(fabs([vals[i] doubleValue]-value)<.01)segment.selectedSegmentIndex=i;control=segment;
  }else{UISlider* slider=[[UISlider alloc] init];slider.minimumValue=[key isEqual:@"opacity"]?.15:[key isEqual:@"size"]?.65:[key isEqual:@"sensitivity"]?.25:0;slider.maximumValue=[key isEqual:@"opacity"]?1:[key isEqual:@"size"]?1.5:[key isEqual:@"sensitivity"]?2.5:.4;slider.value=value;control=slider;}
  control.tag=p.section*100+p.row;[control addTarget:self action:@selector(settingChanged:) forControlEvents:UIControlEventValueChanged];UIStackView* stack=[[UIStackView alloc] initWithArrangedSubviews:@[title,control]];stack.axis=UILayoutConstraintAxisVertical;stack.spacing=8;
  if([type isEqual:@"slider"]){UILabel* label=[[UILabel alloc] init];label.tag=9001;label.text=[self valueLabel:key value:value];label.font=[UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];label.textAlignment=NSTextAlignmentRight;[stack addArrangedSubview:label];}
  stack.translatesAutoresizingMaskIntoConstraints=NO;[cell.contentView addSubview:stack];[NSLayoutConstraint activateConstraints:@[[stack.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:20],[stack.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-20],[stack.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor]]];
 }else{cell.textLabel.text=row[1];cell.detailTextLabel.text=row[2];cell.textLabel.numberOfLines=0;cell.detailTextLabel.numberOfLines=0;
  if([type isEqual:@"switch"]){UISwitch* toggle=[[UISwitch alloc] init];toggle.on=value;toggle.tag=p.section*100+p.row;[toggle addTarget:self action:@selector(settingChanged:) forControlEvents:UIControlEventValueChanged];cell.accessoryView=toggle;}
  else{cell.textLabel.textColor=tableView.tintColor;cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;cell.selectionStyle=UITableViewCellSelectionStyleDefault;}
 }return cell;
}
- (NSString*)tableView:(UITableView*)tableView titleForFooterInSection:(NSInteger)section {
 if(section==0)return @"混合：摇杆或拖动；拖动：相对移动；摇杆：仅使用摇杆。设置、切后台和旋转会释放已锁定的 Z / S。";
 if(section==1)return @"死区越大，中心附近越不易误移动；0% 无死区。手指滑出摇杆后继续追踪，抬手停止。布局编辑可拖动控件，分别保存横屏和竖屏位置。";
 if(section==2)return @"横竖屏始终铺满；竖屏战斗的信息板移到顶部。30 FPS 限制显示提交，逻辑目标为 60 Hz 更新。";
 if(section==4)return @"开发者按钮仅在自己的战斗中显示，打开菜单会暂停游戏。关闭开发者功能也会关闭无敌。恢复默认设置不会撤销已解锁的游戏内容。";
 return @"Z：射击／确认，X：Bomb／返回，S：低速。菜单滑动选择、轻点确认；对话轻点继续。战斗双击 Bomb、双指按住低速、四指触摸暂停。设置内双指轻点返回。日志仅保存在本机。";
}
- (void)finishOnce {
    if(self.didFinish)return;self.didFinish=YES;
    if(self.finished)self.finished();self.finished=nil;
}
- (void)closeSettings {
    if([self.presentedViewController isKindOfClass:UIAlertController.class])return;
    if(self.closing||self.didFinish)return;self.closing=YES;
    // Keep the completion owner alive until dismissal has released the pause.
    TH11SettingsController* controller=self;
    [self.navigationController dismissViewControllerAnimated:YES completion:^{[controller finishOnce];}];
}
- (void)finishSharing {
    UIViewController* share=self.presentedViewController;
    if(!share){[self closeSettings];return;}
    TH11SettingsController* controller=self;
    // The activity completion may arrive before its dismissal animation ends.
    if(share.isBeingDismissed&&share.transitionCoordinator){
        [share.transitionCoordinator animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context){[controller closeSettings];}];
    }else{
        [share dismissViewControllerAnimated:YES completion:^{[controller closeSettings];}];
    }
}
- (void)presentationControllerDidDismiss:(UIPresentationController*)presentationController {
    if([presentationController.presentedViewController isKindOfClass:UIActivityViewController.class])[self closeSettings];
    else [self finishOnce];
}
- (void)popoverPresentationControllerDidDismissPopover:(UIPopoverPresentationController*)popoverPresentationController {[self closeSettings];}
- (int)confirmUnlockPrompt:(UIAlertController*)prompt {
    NSString* code=[prompt.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    const int result=sdl_unlock_all(code.UTF8String);
    self.unlockFeedback=result==1?@"已解锁并永久保存：Extra、全部练习关卡及音乐。":result==0?@"作弊码不正确，请检查后重试。":@"解锁保存失败，请检查存储空间后重试。";
    [self.tableView reloadData];UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification,self.unlockFeedback);
    touhou::ios::diagnostic(@"Unlock result=%d",result);return result;
}
- (void)tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if([self.rows[indexPath.section][indexPath.row][0] isEqual:@"unlock"]){
        UIAlertController* prompt=[UIAlertController alertControllerWithTitle:@"输入作弊码" message:@"正确代码确认后，将永久解锁所有角色的 Extra、全部练习关卡和 Music Room。已有成绩会保留。" preferredStyle:UIAlertControllerStyleAlert];
        [prompt addTextFieldWithConfigurationHandler:^(UITextField* field){field.placeholder=@"作弊码";field.autocapitalizationType=UITextAutocapitalizationTypeNone;field.autocorrectionType=UITextAutocorrectionTypeNo;field.spellCheckingType=UITextSpellCheckingTypeNo;field.accessibilityIdentifier=@"th11.unlock.code";}];
        [prompt addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        __weak TH11SettingsController* controller=self;
        __weak UIAlertController* weakPrompt=prompt;
        [prompt addAction:[UIAlertAction actionWithTitle:@"确认解锁" style:UIAlertActionStyleDefault handler:^(UIAlertAction*){
            [controller confirmUnlockPrompt:weakPrompt];
        }]];
        [self presentViewController:prompt animated:YES completion:nil];return;
    }
    if([self.rows[indexPath.section][indexPath.row][0] isEqual:@"reset"]){touhou::ios::resetPreferences();touhou::ios::applyPreferences();[tableView reloadData];return;}
    if([self.rows[indexPath.section][indexPath.row][0] isEqual:@"layout"]){TH11SettingsController* controller=self;[self.navigationController dismissViewControllerAnimated:YES completion:^{touhou::ios::editControlLayout(^{[controller finishOnce];});}];return;}
    if(![self.rows[indexPath.section][indexPath.row][0] isEqual:@"export"])return;
    NSError* error=nil;NSURL* file=exportSnapshot(&error);
    if(!file){
        touhou::ios::diagnostic(@"Diagnostic export failed: %@",error);
        UIAlertController* alert=[UIAlertController alertControllerWithTitle:@"无法导出日志" message:error.localizedDescription?:@"请检查可用存储空间后重试。" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];return;
    }
    UIActivityViewController* share=[[UIActivityViewController alloc] initWithActivityItems:@[file] applicationActivities:nil];
    share.popoverPresentationController.sourceView=tableView;
    share.popoverPresentationController.sourceRect=[tableView rectForRowAtIndexPath:indexPath];
    share.popoverPresentationController.permittedArrowDirections=UIPopoverArrowDirectionAny;
    share.popoverPresentationController.delegate=self;
    share.presentationController.delegate=self;
    __weak TH11SettingsController* weakSelf=self;
    share.completionWithItemsHandler=^(UIActivityType activity,BOOL completed,NSArray* returnedItems,NSError* shareError){
        touhou::ios::diagnostic(@"Diagnostic share finished: completed=%d error=%@",completed,shareError);
        dispatch_async(dispatch_get_main_queue(),^{[weakSelf finishSharing];});
    };
    [self presentViewController:share animated:YES completion:nil];
}
@end

@interface TH11DeveloperController : UITableViewController<UIAdaptivePresentationControllerDelegate>
@property(nonatomic,copy) void (^finished)(void);
@property(nonatomic) BOOL didFinish;
@property(nonatomic,copy) NSString* feedback;
@end
@implementation TH11DeveloperController
- (void)viewDidLoad {
    [super viewDidLoad];self.title=@"开发者功能";
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithTitle:@"继续游戏" style:UIBarButtonItemStyleDone target:self action:@selector(close)];
    self.feedback=@"游戏已暂停";
}
- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section{return 7;}
- (UITableViewCell*)tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)path {
    NSArray* labels=@[@"无敌",@"最高分数",@"补满资源",@"满火力",@"满残机与 Bomb 能量",@"全部补满",@"清除弹幕与激光"];
    NSArray* details=@[@"阻止中弹死亡；再次关闭恢复正常",@"当前分数设为原版上限 9,999,999,990",@"最大得点、Graze 和通信强度",@"按当前角色的最高火力补满",@"残机补至 8，火力补满供 Bomb 使用",@"同时补满分数、资源、火力和残机",@"立即清除当前屏幕的敌方子弹与激光"];
    UITableViewCell* cell=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.textLabel.text=labels[path.row];cell.detailTextLabel.text=details[path.row];
    cell.textLabel.numberOfLines=0;cell.detailTextLabel.numberOfLines=0;
    cell.accessibilityIdentifier=[NSString stringWithFormat:@"th11.developer.action.%ld",(long)path.row];
    if(path.row==0){UISwitch* toggle=[[UISwitch alloc]init];toggle.on=sdl_developer_invincible();[toggle addTarget:self action:@selector(invincibleChanged:) forControlEvents:UIControlEventValueChanged];cell.accessoryView=toggle;}
    else cell.textLabel.textColor=tableView.tintColor;
    return cell;
}
- (CGFloat)tableView:(UITableView*)tableView heightForRowAtIndexPath:(NSIndexPath*)path{return 84;}
- (NSString*)tableView:(UITableView*)tableView titleForHeaderInSection:(NSInteger)section{return self.feedback;}
- (NSString*)tableView:(UITableView*)tableView titleForFooterInSection:(NSInteger)section{return @"地灵殿的 Bomb 消耗火力，因此补满 Bomb 能量会补满火力。关闭此面板后继续战斗；回放与演示不启用这些功能。";}
- (void)activate:(NSInteger)action {
    BOOL ok=sdl_developer_action((int)action);
    self.feedback=ok?@"已生效 · 游戏保持暂停":@"当前无法执行此功能";
    touhou::ios::diagnostic(@"Developer action=%ld result=%d invincible=%d",(long)action,ok,sdl_developer_invincible());
    [self.tableView reloadData];
}
- (void)invincibleChanged:(UISwitch*)toggle {[self activate:0];}
- (void)tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)path {[tableView deselectRowAtIndexPath:path animated:YES];[self activate:path.row];}
- (void)finishOnce {if(self.didFinish)return;self.didFinish=YES;if(self.finished)self.finished();self.finished=nil;}
- (void)close {TH11DeveloperController* controller=self;[self.navigationController dismissViewControllerAnimated:YES completion:^{[controller finishOnce];}];}
- (void)presentationControllerDidDismiss:(UIPresentationController*)presentationController {[self finishOnce];}
@end

namespace touhou::ios {
void presentDeveloper(UIViewController* presenter,void (^finished)(void)){
    if(!presenter||!presenter.view.window||presenter.presentedViewController||presenter.isBeingDismissed){if(finished)finished();return;}
    TH11DeveloperController* developer=[[TH11DeveloperController alloc]initWithStyle:UITableViewStyleInsetGrouped];developer.finished=finished;
    UINavigationController* navigation=[[UINavigationController alloc]initWithRootViewController:developer];
    navigation.modalPresentationStyle=UIModalPresentationFormSheet;navigation.preferredContentSize=CGSizeMake(560,740);
    navigation.presentationController.delegate=developer;
    [presenter presentViewController:navigation animated:YES completion:nil];
}
void presentSettings(UIViewController* presenter,UIView* anchor,void (^finished)(void)){
    if(!presenter||!presenter.view.window||presenter.presentedViewController||presenter.isBeingDismissed){if(finished)finished();return;}
    TH11SettingsController* settings=[[TH11SettingsController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    settings.finished=finished;
    UINavigationController* navigation=[[UINavigationController alloc] initWithRootViewController:settings];
    navigation.modalPresentationStyle=UIModalPresentationFormSheet;
    navigation.preferredContentSize=CGSizeMake(720,760);
    navigation.presentationController.delegate=settings;
    [presenter presentViewController:navigation animated:YES completion:nil];
}
}

#if TH11_DIAGNOSTICS
namespace {
UIButton* settingsButtonInView(UIView* view){
    if([view isKindOfClass:UIButton.class]&&[view.accessibilityIdentifier isEqualToString:@"th11.settings"])return (UIButton*)view;
    for(UIView* child in view.subviews){UIButton* found=settingsButtonInView(child);if(found)return found;}
    return nil;
}
UISlider* sliderInView(UIView* view){
    if([view isKindOfClass:UISlider.class])return (UISlider*)view;
    for(UIView* child in view.subviews){UISlider* found=sliderInView(child);if(found)return found;}
    return nil;
}
void smokeAfter(double seconds,void (^action)(void)){
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,int64_t(seconds*NSEC_PER_SEC)),dispatch_get_main_queue(),action);
}
void smokeFail(NSString* message){
    touhou::ios::diagnostic(@"SETTINGS_SMOKE FAIL: %@",message);touhou::ios::diagnosticsFlush();
}
void invokeSettingsSmoke(unsigned attempts){
    UIButton* button=nil;
    for(UIWindow* window in UIApplication.sharedApplication.windows){
        if(!window.hidden){button=settingsButtonInView(window);if(button)break;}
    }
    if(!button){
        if(attempts<30){smokeAfter(1,^{invokeSettingsSmoke(attempts+1);});return;}
        smokeFail(@"settings button never became available");return;
    }
    if(sdl_loop_is_paused()){smokeFail(@"game was already suspended before opening settings");return;}
    UIViewController* presenter=button.window.rootViewController;
    const std::uint64_t pausedCallbacks=observedCallbacks;
    [button sendActionsForControlEvents:UIControlEventTouchDown];
    touhou::ios::diagnostic(@"SETTINGS_SMOKE invoked actual settings button; callback=%llu",static_cast<unsigned long long>(pausedCallbacks));
    smokeAfter(2,^{
        UIViewController* modal=presenter.presentedViewController;
        TH11SettingsController* settings=[modal isKindOfClass:UINavigationController.class]?(TH11SettingsController*)((UINavigationController*)modal).topViewController:nil;
        if(![settings isKindOfClass:TH11SettingsController.class]||!sdl_loop_is_paused()||observedCallbacks!=pausedCallbacks){
            smokeFail(@"settings did not suspend game callbacks");
            if([settings isKindOfClass:TH11SettingsController.class])[settings closeSettings];return;
        }
        NSIndexPath* deadZoneRow=nil;
        for(NSUInteger section=0;section<settings.rows.count;section++)for(NSUInteger row=0;row<[settings.rows[section] count];row++)
            if([settings.rows[section][row][0] isEqual:@"deadZone"])deadZoneRow=[NSIndexPath indexPathForRow:row inSection:section];
        if(!deadZoneRow){smokeFail(@"dead zone setting missing");[settings closeSettings];return;}
        [settings.tableView scrollToRowAtIndexPath:deadZoneRow atScrollPosition:UITableViewScrollPositionMiddle animated:NO];
        [settings.tableView layoutIfNeeded];
        UISlider* slider=sliderInView([settings.tableView cellForRowAtIndexPath:deadZoneRow]);
        slider.value=.31;[slider sendActionsForControlEvents:UIControlEventValueChanged];
        if(!slider||fabs(touhou::ios::preference(@"deadZone")-.31)>.001){smokeFail(@"actual dead zone slider did not persist");[settings closeSettings];return;}
        touhou::ios::diagnostic(@"SETTINGS_SMOKE settings visible and suspended; actual dead-zone slider saved 31%%; invoking export row");
        NSIndexPath* exportRow=nil;
        for(NSUInteger section=0;section<settings.rows.count;section++)for(NSUInteger row=0;row<[settings.rows[section] count];row++)
            if([settings.rows[section][row][0] isEqual:@"export"])exportRow=[NSIndexPath indexPathForRow:row inSection:section];
        if(!exportRow){smokeFail(@"export setting missing");[settings closeSettings];return;}
        [settings tableView:settings.tableView didSelectRowAtIndexPath:exportRow];
        smokeAfter(2,^{
            UIViewController* modalShare=settings.presentedViewController;
            NSNumber* bytes=[NSFileManager.defaultManager attributesOfItemAtPath:[logDirectory URLByAppendingPathComponent:@"TH11-diagnostics.txt"].path error:nullptr][NSFileSize];
            if(![modalShare isKindOfClass:UIActivityViewController.class]||bytes.unsignedLongLongValue==0||!sdl_loop_is_paused()){
                smokeFail(@"share sheet/snapshot missing or simulation resumed too early");[settings finishSharing];return;
            }
            touhou::ios::diagnostic(@"SETTINGS_SMOKE share visible; exportBytes=%@; dismissing locally in 10 seconds",bytes);
            touhou::ios::diagnosticsFlush();
            smokeAfter(10,^{
                UIActivityViewController* share=(UIActivityViewController*)modalShare;
                // Exercise the same completion used by a user's cancelled
                // share; no activity or external recipient is selected.
                if(share.completionWithItemsHandler)share.completionWithItemsHandler(nil,NO,nil,nil);
                else [settings finishSharing];
                smokeAfter(3,^{
                    if(presenter.presentedViewController||sdl_loop_is_paused()||observedCallbacks<=pausedCallbacks){
                        smokeFail(@"share close did not dismiss settings and resume callbacks");return;
                    }
                    touhou::ios::diagnostic(@"SETTINGS_SMOKE PASS paused=1 exportBytes=%@ resumed=1 callbacksBefore=%llu callbacksAfter=%llu",bytes,
                                           static_cast<unsigned long long>(pausedCallbacks),static_cast<unsigned long long>(observedCallbacks));
                    touhou::ios::diagnosticsFlush();
                });
            });
        });
    });
}
void startSettingsSmoke(){
    touhou::ios::diagnostic(@"SETTINGS_SMOKE scheduled after startup; diagnostic build only");
    smokeAfter(5,^{invokeSettingsSmoke(0);});
}
UIButton* featureButton(UIView* view,NSString* identifier){
    if([view isKindOfClass:UIButton.class]&&[view.accessibilityIdentifier isEqual:identifier])return (UIButton*)view;
    for(UIView* child in view.subviews){UIButton* result=featureButton(child,identifier);if(result)return result;}return nil;
}
NSIndexPath* featureRow(TH11SettingsController* settings,NSString* key){
    for(NSUInteger s=0;s<settings.rows.count;++s)for(NSUInteger r=0;r<[settings.rows[s] count];++r)
        if([settings.rows[s][r][0] isEqual:key])return [NSIndexPath indexPathForRow:r inSection:s];return nil;
}
void typeUnlockCode(TH11SettingsController* settings,UIAlertController* prompt,unsigned step,std::uint64_t frozenCallbacks){
    UITextField* field=prompt.textFields.firstObject;
    if(settings.presentedViewController!=prompt||!field.isFirstResponder||!sdl_loop_is_paused()||observedCallbacks!=frozenCallbacks){
        smokeFail([NSString stringWithFormat:@"keyboard lost field focus/pause at step %u",step]);return;
    }
    if(step<5){[field insertText:[@"wrong" substringWithRange:NSMakeRange(step,1)]];}
    else if(step==5){
        if(![field.text isEqual:@"wrong"]||[settings confirmUnlockPrompt:prompt]!=0){smokeFail(@"keyboard wrong code altered unlock");return;}
        [field deleteBackward];
    }else if(step==6){
        if(![field.text isEqual:@"wron"]){smokeFail(@"keyboard delete failed");return;}
        [field selectAll:nil];[field insertText:@"ymgjdsh"];
    }else{
        if(![field.text isEqual:@"ymgjdsh"]||[settings confirmUnlockPrompt:prompt]!=1||(sdl_diagnostic_features()&8)==0){smokeFail(@"keyboard paste/confirmation failed");return;}
        touhou::ios::diagnostic(@"KEYBOARD_UI input PASS typed=5 delete=1 paste=7 focusRetained=1 fullUnlockSaved=1 callbacksFrozen=1");touhou::ios::diagnosticsFlush();
        smokeAfter(3,^{[prompt dismissViewControllerAnimated:YES completion:^{[settings closeSettings];
            smokeAfter(2,^{
                if(settings.didFinish&&!sdl_loop_is_paused()&&observedCallbacks>frozenCallbacks){touhou::ios::diagnostic(@"KEYBOARD_UI PASS typing/delete/paste/confirm and settings pause/resume");touhou::ios::diagnosticsFlush();}
                else smokeFail(@"keyboard settings resume failed");
            });
        }];});return;
    }
    // UIKit posts this notification for typing, paste and composition. Include
    // it explicitly when a simulator's programmatic insertText omits it.
    [NSNotificationCenter.defaultCenter postNotificationName:UITextFieldTextDidChangeNotification object:field];
    touhou::ios::diagnostic(@"KEYBOARD_UI change step=%u length=%lu focus=%d",step,(unsigned long)field.text.length,field.isFirstResponder);touhou::ios::diagnosticsFlush();
    smokeAfter(.4,^{typeUnlockCode(settings,prompt,step+1,frozenCallbacks);});
}
void invokeKeyboardSmoke(unsigned attempts){
    UIButton* button=nil;for(UIWindow* w in UIApplication.sharedApplication.windows)if(!w.hidden){button=featureButton(w,@"th11.settings");if(button)break;}
    if(!button){if(attempts<30){smokeAfter(1,^{invokeKeyboardSmoke(attempts+1);});return;}smokeFail(@"keyboard settings button missing");return;}
    UIViewController* presenter=button.window.rootViewController;
    [button sendActionsForControlEvents:UIControlEventTouchDown];
    smokeAfter(1,^{
        TH11SettingsController* settings=(TH11SettingsController*)((UINavigationController*)presenter.presentedViewController).topViewController;
        if(![settings isKindOfClass:TH11SettingsController.class]||!sdl_loop_is_paused()){smokeFail(@"keyboard settings unavailable");return;}
        NSIndexPath* bombRow=featureRow(settings,@"autoBomb");
        if(!bombRow){smokeFail(@"automatic Bomb setting missing");return;}
        [settings.tableView scrollToRowAtIndexPath:bombRow atScrollPosition:UITableViewScrollPositionMiddle animated:NO];[settings.tableView layoutIfNeeded];
        UISwitch* toggle=(UISwitch*)[settings.tableView cellForRowAtIndexPath:bombRow].accessoryView;
        if(![toggle isKindOfClass:UISwitch.class]){smokeFail(@"automatic Bomb switch missing");return;}
        for(NSNumber* value in @[@YES,@NO,@YES]){
            toggle.on=value.boolValue;[toggle sendActionsForControlEvents:UIControlEventValueChanged];
            if(touhou::sdl::nativeOptions.autoBomb!=value.boolValue||bool(touhou::ios::preference(@"autoBomb"))!=value.boolValue){smokeFail(@"automatic Bomb preference/engine mismatch");return;}
        }
        touhou::ios::diagnostic(@"AUTOBOMB_UI PASS switch on/off reached preferences and engine; saved=1");
        NSIndexPath* row=featureRow(settings,@"unlock");[settings.tableView scrollToRowAtIndexPath:row atScrollPosition:UITableViewScrollPositionMiddle animated:NO];
        [settings tableView:settings.tableView didSelectRowAtIndexPath:row];
        smokeAfter(1,^{
            UIAlertController* prompt=(UIAlertController*)settings.presentedViewController;
            if(![prompt isKindOfClass:UIAlertController.class]||prompt.textFields.count!=1){smokeFail(@"keyboard prompt missing");return;}
            [prompt.textFields.firstObject becomeFirstResponder];
            smokeAfter(.5,^{typeUnlockCode(settings,prompt,0,observedCallbacks);});
        });
    });
}
void startKeyboardSmoke(){smokeAfter(4,^{invokeKeyboardSmoke(0);});}
void invokeFeaturesSmoke(unsigned attempt){
    UIButton* button=nil;for(UIWindow* w in UIApplication.sharedApplication.windows)if(!w.hidden){button=featureButton(w,@"th11.settings");if(button)break;}
    if(!button||sdl_game_status()[0]!=7){if(attempt<40){smokeAfter(2,^{invokeFeaturesSmoke(attempt+1);});return;}smokeFail(@"features battle unavailable");return;}
    UIViewController* presenter=button.window.rootViewController;
    [button sendActionsForControlEvents:UIControlEventTouchDown];
    smokeAfter(1,^{
        TH11SettingsController* settings=(TH11SettingsController*)((UINavigationController*)presenter.presentedViewController).topViewController;
        if(![settings isKindOfClass:TH11SettingsController.class]||!sdl_loop_is_paused()){smokeFail(@"feature settings pause");return;}
        for(NSString* key in @[@"dragLimited",@"developer"]){
            NSIndexPath* row=featureRow(settings,key);[settings.tableView scrollToRowAtIndexPath:row atScrollPosition:UITableViewScrollPositionMiddle animated:NO];[settings.tableView layoutIfNeeded];
            UISwitch* toggle=(UISwitch*)[settings.tableView cellForRowAtIndexPath:row].accessoryView;
            if(![toggle isKindOfClass:UISwitch.class]){smokeFail(@"new switch missing");return;}
            toggle.on=[key isEqual:@"developer"];[toggle sendActionsForControlEvents:UIControlEventValueChanged];
        }
        if((sdl_diagnostic_features()&3)!=3){smokeFail(@"settings switches failed to reach movement/developer engine");return;}
        NSIndexPath* row=featureRow(settings,@"unlock");[settings tableView:settings.tableView didSelectRowAtIndexPath:row];
        smokeAfter(1,^{
            UIAlertController* prompt=(UIAlertController*)settings.presentedViewController;
            if(![prompt isKindOfClass:UIAlertController.class]||prompt.textFields.count!=1){smokeFail(@"unlock prompt missing");return;}
            prompt.textFields[0].text=@"wrong";if([settings confirmUnlockPrompt:prompt]!=0){smokeFail(@"wrong code accepted");return;}
            prompt.textFields[0].text=@"ymgjdsh";if([settings confirmUnlockPrompt:prompt]!=1||(sdl_diagnostic_features()&8)==0){smokeFail(@"correct code/save incomplete");return;}
            [prompt dismissViewControllerAnimated:YES completion:^{
                [settings.tableView scrollToRowAtIndexPath:row atScrollPosition:UITableViewScrollPositionMiddle animated:NO];
                touhou::ios::diagnostic(@"FEATURES_UI settings/input PASS unlimited=1 developer=1 wrongCodeRejected=1 fullUnlockSaved=1");touhou::ios::diagnosticsFlush();
                smokeAfter(5,^{[settings closeSettings];
                    smokeAfter(2,^{
                        UIButton* developer=featureButton(presenter.view,@"th11.developer");
                        if(!developer||developer.hidden||sdl_loop_is_paused()){smokeFail(@"floating button unavailable");return;}
                        [developer sendActionsForControlEvents:UIControlEventTouchUpInside];
                        smokeAfter(1,^{
                            TH11DeveloperController* panel=(TH11DeveloperController*)((UINavigationController*)presenter.presentedViewController).topViewController;
                            if(![panel isKindOfClass:TH11DeveloperController.class]||!sdl_loop_is_paused()){smokeFail(@"developer pause/panel");return;}
                            const auto frozenCallbacks=observedCallbacks;
                            for(NSInteger action=0;action<7;++action){
                                NSIndexPath* p=[NSIndexPath indexPathForRow:action inSection:0];[panel tableView:panel.tableView didSelectRowAtIndexPath:p];
                            }
                            if(!sdl_developer_invincible()||sdl_game_status()[3]!=8){smokeFail(@"developer action effect");return;}
                            touhou::ios::diagnostic(@"FEATURES_UI developer panel/actions PASS invincible=1 lives=8 paused=1");touhou::ios::diagnosticsFlush();
                            smokeAfter(7,^{
                                if(observedCallbacks!=frozenCallbacks){smokeFail(@"callbacks advanced behind developer");return;}
                                [panel close];smokeAfter(2,^{
                                    if(presenter.presentedViewController||sdl_loop_is_paused()||observedCallbacks<=frozenCallbacks){smokeFail(@"developer close/resume");return;}
                                    touhou::ios::diagnostic(@"FEATURES_UI PASS all new settings, code input/save, floating panel/actions, pause/resume state=%d",sdl_diagnostic_features());touhou::ios::diagnosticsFlush();
                                });
                            });
                        });
                    });
                });
            }];
        });
    });
}
void startFeaturesSmoke(){smokeAfter(5,^{invokeFeaturesSmoke(0);});}
}
#endif

