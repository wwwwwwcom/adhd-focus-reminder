#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import <CoreGraphics/CoreGraphics.h>

// ═══════════════════════════════════════════════════════════════
// Configuration
// ═══════════════════════════════════════════════════════════════
static const NSTimeInterval kIdleThreshold  = 5 * 60;
static const NSTimeInterval kSnoozeDuration = 5 * 60;
static const NSTimeInterval kPollInterval   = 2.0;

// ═══════════════════════════════════════════════════════════════
// Globals
// ═══════════════════════════════════════════════════════════════
static BOOL      gMonitoringEnabled = YES;
static NSDate   *gSnoozeUntil       = nil;
static NSDate   *gPauseDate         = nil;  // 记录暂停的日期，用于过夜自动恢复
static BOOL      gPopupShowing      = NO;
static BOOL      gNeedsActiveReset  = YES;  // 默认 YES：启动后必须等用户操作键盘/鼠标才进入监控

static NSStatusItem *gStatusItem  = nil;
static NSMenuItem   *gStatusLabel = nil;
static NSMenuItem   *gToggleItem  = nil;
static NSTimer      *gPollTimer   = nil;
static NSWindow     *gPopupWindow = nil;

// ═══════════════════════════════════════════════════════════════
// Rotating motivational phrases
// ═══════════════════════════════════════════════════════════════
static NSArray<NSString *> *gUrgePhrases = nil;

NSString *randomUrgePhrase(void) {
    if (!gUrgePhrases) {
        gUrgePhrases = @[
            @"东西写完了吗？",
            @"刚才在干什么呢？",
            @"还差多少？先回来。",
            @"别飘走了，快回来。",
            @"你刚才的思路是什么？",
            @"进度条卡住了吗？",
            @"先完成手头这件事。",
            @"回头看看屏幕。",
            @"想不起来就写一行。",
            @"一小步也行，回来吧。",
            @"你的代码还在等着你。",
            @"别让注意力跑了。",
        ];
    }
    return gUrgePhrases[arc4random_uniform((uint32_t)gUrgePhrases.count)];
}

// ═══════════════════════════════════════════════════════════════
// Custom window
// ═══════════════════════════════════════════════════════════════
@interface PopupWindow : NSWindow
@end
@implementation PopupWindow
- (BOOL)canBecomeKeyWindow    { return YES; }
- (BOOL)canBecomeMainWindow   { return YES; }
@end

// ═══════════════════════════════════════════════════════════════
// Idle detection
// ═══════════════════════════════════════════════════════════════
double systemIdleSeconds(void) {
    return CGEventSourceSecondsSinceLastEventType(
        kCGEventSourceStateCombinedSessionState,
        (CGEventType)(~0u)
    );
}

// 屏幕锁定检测
extern CFDictionaryRef CGSessionCopyCurrentDictionary(void);

BOOL isScreenLocked(void) {
    CFDictionaryRef session = CGSessionCopyCurrentDictionary();
    if (!session) return NO;  // 获取失败时保守处理：认为未锁定
    // kCGSessionOnConsoleKey 在 <CoreGraphics/CGSession.h> 中定义为宏
    CFBooleanRef onConsole = CFDictionaryGetValue(session, kCGSessionOnConsoleKey);
    BOOL locked = (onConsole == kCFBooleanFalse);
    CFRelease(session);
    return locked;
}

// ═══════════════════════════════════════════════════════════════
// Popup
// ═══════════════════════════════════════════════════════════════

void closePopup(void) {
    if (gPopupWindow) {
        [gPopupWindow close];
        gPopupWindow = nil;
    }
    gPopupShowing = NO;
}

NSString *popupHTML(int seedSec) {
    NSString *urge = randomUrgePhrase();
    return [NSString stringWithFormat:
    @"<!DOCTYPE html><html lang=\"zh-CN\"><head><meta charset=\"UTF-8\"/>"
    @"<meta name=\"viewport\" content=\"width=400,initial-scale=1.0\"/>"
    @"<style>"
    @"*{margin:0;padding:0;box-sizing:border-box}"
    @"html,body{width:400px;height:440px;overflow:hidden;background:transparent}"
    @"body{display:flex;align-items:center;justify-content:center;"
    @"font-family:-apple-system,BlinkMacSystemFont,'PingFang SC',sans-serif;"
    @"-webkit-font-smoothing:antialiased;user-select:none;-webkit-user-select:none}"
    @".card{width:100%%;height:100%%;display:flex;flex-direction:column;"
    @"align-items:center;justify-content:center;padding:40px 36px 32px;"
    @"border-radius:24px;background:rgba(28,28,30,0.96);"
    @"border:1px solid rgba(255,255,255,0.08);text-align:center;"
    @"box-shadow:0 0 0 1px rgba(255,255,255,0.03) inset,"
    @"0 2px 10px rgba(0,0,0,0.15),0 12px 40px rgba(0,0,0,0.35),0 32px 80px rgba(0,0,0,0.50);"
    @"animation:cardIn .5s cubic-bezier(.16,1,.3,1) both}"
    @"@keyframes cardIn{0%%{opacity:0;transform:scale(.92) translateY(16px)}100%%{opacity:1;transform:scale(1) translateY(0)}}"
    @".icon-wrap{position:relative;display:inline-block;margin-bottom:22px}"
    @".icon{font-size:46px;line-height:1;position:relative;z-index:2;animation:float 3.6s ease-in-out infinite}"
    @"@keyframes float{0%%,100%%{transform:translateY(0)}50%%{transform:translateY(-5px)}}"
    @".icon-glow{position:absolute;top:50%%;left:50%%;width:76px;height:76px;"
    @"transform:translate(-50%%,-50%%);border-radius:50%%;"
    @"background:radial-gradient(circle,rgba(10,132,255,.18),transparent 70%%);"
    @"animation:breathe 3.6s ease-in-out infinite}"
    @"@keyframes breathe{0%%,100%%{transform:translate(-50%%,-50%%) scale(.82);opacity:.35}50%%{transform:translate(-50%%,-50%%) scale(1.12);opacity:.85}}"
    @".title{font-size:25px;font-weight:600;letter-spacing:-.02em;color:#f5f5f7;margin-bottom:12px}"
    @".subtitle{font-size:14px;color:rgba(245,245,247,.50);line-height:1.5;margin-bottom:12px}"
    @".idle-badge{display:inline-block;margin-top:6px;padding:4px 16px;border-radius:100px;"
    @"background:rgba(255,255,255,.07);color:rgba(245,245,247,.84);font-weight:510;font-size:14px;min-width:70px}"
    @".urge{font-size:16px;font-weight:520;color:rgba(245,245,247,.66);margin-bottom:26px}"
    @".btn-group{display:flex;flex-direction:column;align-items:center;gap:8px;margin-bottom:16px}"
    @".btn{display:flex;align-items:center;justify-content:center;width:100%%;max-width:230px;"
    @"padding:11px 24px;border:none;border-radius:100px;font-family:inherit;cursor:pointer;outline:none;"
    @"transition:background .18s,transform .18s;-webkit-appearance:none}"
    @".btn:active{transform:scale(.97)}.btn:disabled{opacity:.5;pointer-events:none}"
    @".btn-primary{background:#0a84ff;color:#fff;font-size:16px;font-weight:540}"
    @".btn-primary:hover{background:#1a8fff}"
    @".btn-ghost{background:rgba(255,255,255,.06);color:rgba(245,245,247,.75);"
    @"font-size:14px;font-weight:480;border:1px solid rgba(255,255,255,.09)}"
    @".btn-ghost:hover{background:rgba(255,255,255,.10);color:#f5f5f7}"
    @".btn-muted{background:rgba(255,255,255,.04);color:rgba(245,245,247,.48);"
    @"font-size:14px;font-weight:460}"
    @".btn-muted:hover{background:rgba(255,255,255,.08);color:rgba(245,245,247,.70)}"
    @"</style></head><body>"
    @"<div class=\"card\" id=\"card\">"
    @"<div class=\"icon-wrap\"><span class=\"icon\">🧠</span><div class=\"icon-glow\"></div></div>"
    @"<h1 class=\"title\">嘿，别走神</h1>"
    @"<p class=\"subtitle\">你已经离开<br/><span class=\"idle-badge\" id=\"idleBadge\">—</span></p>"
    @"<p class=\"urge\">%@</p>"
    @"<div class=\"btn-group\">"
    @"<button class=\"btn btn-primary\" id=\"btnAck\" autofocus>我知道了</button>"
    @"<button class=\"btn btn-ghost\" id=\"btnSnooze\">等 5 分钟再提醒</button>"
    @"<button class=\"btn btn-muted\" id=\"btnPause\">暂停工作</button>"
    @"</div></div>"
    @"<script>"
    @"var startedAt=Date.now(),seedSec=%d,badge=document.getElementById('idleBadge');"
    @"function fmt(s){var m=Math.floor(s/60),h=Math.floor(m/60);"
    @"if(h>0)return h+' 小时 '+(m%%60)+' 分钟';if(m>0)return m+' 分钟';return s+' 秒';}"
    @"badge.textContent=fmt(seedSec);"
    @"setInterval(function(){badge.textContent=fmt(seedSec+Math.floor((Date.now()-startedAt)/1000));},1000);"
    @"(function(){try{var ctx=new (AudioContext||webkitAudioContext)();"
    @"if(ctx.state==='suspended')ctx.resume();var notes=[523.25,659.25,783.99];"
    @"function beep(f,st,v){var o1=ctx.createOscillator(),o2=ctx.createOscillator();"
    @"var g=ctx.createGain(),g2=ctx.createGain();o1.type='triangle';o1.frequency.value=f;"
    @"o2.type='sine';o2.frequency.value=f*2;var t=ctx.currentTime+st;"
    @"g.gain.setValueAtTime(0,t);g.gain.linearRampToValueAtTime(v,t+.02);"
    @"g.gain.exponentialRampToValueAtTime(.001,t+.40);"
    @"g2.gain.setValueAtTime(0,t);g2.gain.linearRampToValueAtTime(v*.36,t+.02);"
    @"g2.gain.exponentialRampToValueAtTime(.001,t+.22);"
    @"o1.connect(g);g.connect(ctx.destination);o2.connect(g2);g2.connect(ctx.destination);"
    @"o1.start(t);o1.stop(t+.45);o2.start(t);o2.stop(t+.28);}"
    @"notes.forEach(function(f,i){beep(f,i*.18,.35);});"
    @"notes.forEach(function(f,i){beep(f,i*.18+.90,.50);});"
    @"notes.forEach(function(f,i){beep(f*2,i*.18+1.8,.55);});}catch(_){}})();"
    @"function doAction(n){['btnAck','btnSnooze','btnPause'].forEach(function(id){document.getElementById(id).disabled=true;});"
    @"var c=document.getElementById('card');c.style.transition='opacity .35s,transform .35s';"
    @"c.style.opacity='0';c.style.transform='scale(.94)';"
    @"setTimeout(function(){try{webkit.messageHandlers.action.postMessage(n);}catch(_){}},420);}"
    @"function quitWindow(){try{webkit.messageHandlers.quit.postMessage('quit');}catch(_){}}"
    @"document.getElementById('btnAck').addEventListener('click',function(e){e.preventDefault();doAction('acknowledge');});"
    @"document.getElementById('btnSnooze').addEventListener('click',function(e){e.preventDefault();doAction('snooze');});"
    @"document.getElementById('btnPause').addEventListener('click',function(e){e.preventDefault();doAction('pause');});"
    @"document.addEventListener('keydown',function(e){"
    @"if(e.key==='1'||e.key==='Enter'){e.preventDefault();doAction('acknowledge');}"
    @"else if(e.key==='2'){e.preventDefault();doAction('snooze');}"
    @"else if(e.key==='3'){e.preventDefault();doAction('pause');}"
    @"else if(e.key==='Escape'){e.preventDefault();quitWindow();}});"
    @"document.getElementById('btnAck').focus();"
    @"</script></body></html>", urge, seedSec];
}

void showPopup(int seedSec) {
    if (gPopupShowing) return;
    gPopupShowing = YES;
    NSRect screen = [[NSScreen mainScreen] visibleFrame];
    CGFloat w = 400, h = 440;
    CGFloat x = screen.origin.x + (screen.size.width  - w) / 2;
    CGFloat y = screen.origin.y + (screen.size.height - h) / 2;

    gPopupWindow = [[PopupWindow alloc]
        initWithContentRect:NSMakeRect(x, y, w, h)
        styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskFullSizeContentView
        backing:NSBackingStoreBuffered defer:NO];
    [gPopupWindow setOpaque:NO];
    [gPopupWindow setBackgroundColor:[NSColor clearColor]];
    [gPopupWindow setHasShadow:YES];
    [gPopupWindow setLevel:NSFloatingWindowLevel];
    [gPopupWindow setCollectionBehavior:NSWindowCollectionBehaviorCanJoinAllSpaces |
                                         NSWindowCollectionBehaviorFullScreenAuxiliary];
    [gPopupWindow setReleasedWhenClosed:NO];

    WKWebViewConfiguration *cfg = [[WKWebViewConfiguration alloc] init];
    [[cfg userContentController] addScriptMessageHandler:(id<WKScriptMessageHandler>)[NSApp delegate] name:@"action"];
    [[cfg userContentController] addScriptMessageHandler:(id<WKScriptMessageHandler>)[NSApp delegate] name:@"quit"];
    [cfg.preferences setValue:@YES forKey:@"developerExtrasEnabled"];

    WKWebView *webView = [[WKWebView alloc] initWithFrame:NSMakeRect(0, 0, w, h) configuration:cfg];
    [webView setValue:@NO forKey:@"drawsBackground"];
    [webView setAllowsBackForwardNavigationGestures:NO];
    [webView setAllowsMagnification:NO];

    // ═══ Corner clipping fix: wrap WKWebView in a rounded-corner view ═══
    NSView *clip = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, w, h)];
    clip.wantsLayer = YES;
    clip.layer.cornerRadius  = 24;
    clip.layer.masksToBounds = YES;
    clip.layer.backgroundColor = [NSColor clearColor].CGColor;
    [clip addSubview:webView];
    [gPopupWindow setContentView:clip];

    [gPopupWindow center];
    [gPopupWindow makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    [webView loadHTMLString:popupHTML(seedSec) baseURL:nil];
}

// ═══════════════════════════════════════════════════════════════
// Menu Bar — IDENTICAL to original working version
// ═══════════════════════════════════════════════════════════════

void updateMenuBar(void) {
    if (gMonitoringEnabled) {
        gStatusLabel.title = @"状态：运行中";
        gToggleItem.title  = @"暂停提醒";
        gStatusItem.button.attributedTitle = [[NSAttributedString alloc]
            initWithString:@"🧠"
            attributes:@{NSFontAttributeName: [NSFont systemFontOfSize:14]}];
    } else {
        gStatusLabel.title = @"状态：已暂停";
        gToggleItem.title  = @"启用提醒";
        gStatusItem.button.attributedTitle = [[NSAttributedString alloc]
            initWithString:@"💤"
            attributes:@{NSFontAttributeName: [NSFont systemFontOfSize:14]}];
    }
}

void buildMenuBar(void) {
    gStatusItem = [[NSStatusBar systemStatusBar]
        statusItemWithLength:NSVariableStatusItemLength];
    gStatusItem.button.attributedTitle = [[NSAttributedString alloc]
        initWithString:@"🧠"
        attributes:@{NSFontAttributeName: [NSFont systemFontOfSize:14]}];

    NSMenu *menu = [[NSMenu alloc] init];
    menu.autoenablesItems = NO;
    gStatusLabel = [menu addItemWithTitle:@"状态：运行中" action:nil keyEquivalent:@""];
    gStatusLabel.enabled = NO;
    [menu addItem:[NSMenuItem separatorItem]];
    gToggleItem = [menu addItemWithTitle:@"暂停提醒" action:@selector(toggleMonitoring:) keyEquivalent:@"t"];
    gToggleItem.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"⚡ 测试弹窗" action:@selector(showTestPopup:) keyEquivalent:@""];
    NSMenuItem *quitItem = [menu addItemWithTitle:@"退出" action:@selector(quitApp:) keyEquivalent:@"q"];
    quitItem.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    gStatusItem.menu = menu;
}

// ═══════════════════════════════════════════════════════════════
// Idle Polling
// ═══════════════════════════════════════════════════════════════

void pollIdle(NSTimer *timer) {
    // 跨天自动恢复：仅在 10:00-19:00 期间恢复，避免午夜弹窗
    if (!gMonitoringEnabled && gPauseDate) {
        if (![[NSCalendar currentCalendar] isDate:gPauseDate inSameDayAsDate:[NSDate date]]) {
            NSInteger hour = [[NSCalendar currentCalendar] component:NSCalendarUnitHour fromDate:[NSDate date]];
            if (hour >= 10 && hour < 19) {
                gMonitoringEnabled = YES;
                gPauseDate = nil;
                gNeedsActiveReset = YES;  // 等用户先活跃再弹窗
                updateMenuBar();
            }
        }
        if (!gMonitoringEnabled) return;
    }
    if (!gMonitoringEnabled) return;

    // 锁屏检测：屏幕锁定时不弹窗，设置为等待活跃状态
    if (isScreenLocked()) {
        gNeedsActiveReset = YES;
        return;
    }

    double idleSec = systemIdleSeconds();

    // 睡眠唤醒检测：空闲时间异常长（超过 6 小时）说明系统刚睡醒，
    // CGEventSourceSecondsSinceLastEventType 在睡眠期间不会重置
    if (idleSec > 6 * 3600) {
        gNeedsActiveReset = YES;
    }

    if (gSnoozeUntil && [gSnoozeUntil timeIntervalSinceNow] <= 0) {
        gSnoozeUntil = nil;
        if (!gPopupShowing) { showPopup((int)idleSec); return; }
    }
    if (idleSec < kIdleThreshold) { if (gNeedsActiveReset) gNeedsActiveReset = NO; return; }
    if (!gNeedsActiveReset && !gPopupShowing && !gSnoozeUntil) showPopup((int)idleSec);
}

// ═══════════════════════════════════════════════════════════════
// App Delegate
// ═══════════════════════════════════════════════════════════════

@interface FocusBarDelegate : NSObject <NSApplicationDelegate, WKScriptMessageHandler>
@end
@implementation FocusBarDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    // status item is already created in main()
    gPollTimer = [NSTimer scheduledTimerWithTimeInterval:kPollInterval repeats:YES
        block:^(NSTimer *t) { pollIdle(t); }];

    // 监听系统唤醒：唤醒后要求用户先活跃才弹窗（防止锁屏下误弹）
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserverForName:NSWorkspaceDidWakeNotification
        object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *n) {
        gNeedsActiveReset = YES;
    }];

    // 监听屏幕休眠：屏幕关闭时标记需要重置（防止 display sleep 后误弹）
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserverForName:NSWorkspaceScreensDidSleepNotification
        object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *n) {
        gNeedsActiveReset = YES;
    }];
}

- (void)toggleMonitoring:(id)sender {
    gMonitoringEnabled = !gMonitoringEnabled;
    if (!gMonitoringEnabled) {
        closePopup(); gSnoozeUntil = nil; gNeedsActiveReset = NO;
        gPauseDate = [NSDate date];
    } else {
        gPauseDate = nil;
    }
    updateMenuBar();
}

- (void)showTestPopup:(id)sender {
    if (!gMonitoringEnabled) { gMonitoringEnabled = YES; updateMenuBar(); }
    closePopup(); gSnoozeUntil = nil; gNeedsActiveReset = NO;
    showPopup((int)systemIdleSeconds());
}

- (void)quitApp:(id)sender { [gPollTimer invalidate]; gPollTimer = nil; closePopup(); [NSApp terminate:nil]; }

- (void)userContentController:(WKUserContentController *)controller
       didReceiveScriptMessage:(WKScriptMessage *)message {
    if ([message.name isEqualToString:@"quit"]) {
        dispatch_async(dispatch_get_main_queue(), ^{ closePopup(); gNeedsActiveReset = YES; });
    } else if ([message.name isEqualToString:@"action"]) {
        NSString *action = (NSString *)message.body;
        dispatch_async(dispatch_get_main_queue(), ^{
            closePopup(); gNeedsActiveReset = YES;
            if ([action isEqualToString:@"snooze"])
                gSnoozeUntil = [NSDate dateWithTimeIntervalSinceNow:kSnoozeDuration];
            else if ([action isEqualToString:@"pause"]) { gMonitoringEnabled = NO; gPauseDate = [NSDate date]; updateMenuBar(); }
        });
    }
}

- (void)applicationWillTerminate:(NSNotification *)notification { [gPollTimer invalidate]; closePopup(); }

@end

// ═══════════════════════════════════════════════════════════════
// main
// ═══════════════════════════════════════════════════════════════

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];

        // Create status item NOW, before [NSApp run]
        // (Sequoia may require this to avoid the item being invisible)
        buildMenuBar();

        FocusBarDelegate *delegate = [[FocusBarDelegate alloc] init];
        [app setDelegate:delegate];
        [app run];
    }
    return 0;
}
