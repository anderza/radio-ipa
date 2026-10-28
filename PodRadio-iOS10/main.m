// PodRadio Lite для старых iPad/iPhone (iOS 10+, armv7 и arm64).
// Интерфейс — страница www/index.html в WKWebView; звук играет AVPlayer (в фоне и на экране блокировки),
// название трека берётся из ICY/ID3-метаданных потока.
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>

@interface PlayerVC : UIViewController <WKScriptMessageHandler, WKUIDelegate, WKNavigationDelegate, UIDocumentPickerDelegate>
- (void)importFile:(NSURL *)src;
@end

@implementation PlayerVC {
    WKWebView *web;
    AVPlayer *player;
    AVPlayerItem *item;
    NSString *url, *station, *track;
    BOOL want;          // пользователь хочет, чтобы играло
    int retries;
}

- (void)loadView {
    UIView *root = [UIView new];
    root.backgroundColor = [UIColor colorWithRed:0x3c/255.0 green:0x3a/255.0 blue:0x38/255.0 alpha:1];
    WKWebViewConfiguration *c = [WKWebViewConfiguration new];
    [c.userContentController addScriptMessageHandler:self name:@"rrn"];
    c.allowsInlineMediaPlayback = YES;
    web = [[WKWebView alloc] initWithFrame:CGRectZero configuration:c];
    web.UIDelegate = self;
    web.navigationDelegate = self;
    web.opaque = NO;
    web.backgroundColor = root.backgroundColor;
    web.scrollView.bounces = NO;
    [root addSubview:web];
    self.view = root;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat top = self.topLayoutGuide.length;
    web.frame = CGRectMake(0, top, self.view.bounds.size.width, self.view.bounds.size.height - top);
}

- (void)viewDidLoad {
    [super viewDidLoad];
    NSURL *u = [[NSBundle mainBundle] URLForResource:@"index" withExtension:@"html" subdirectory:@"www"];
    [web loadFileURL:u allowingReadAccessToURL:[u URLByDeletingLastPathComponent]];
    [self setupRemote];
}

- (UIStatusBarStyle)preferredStatusBarStyle { return UIStatusBarStyleLightContent; }

#pragma mark - страница → приложение

- (void)userContentController:(WKUserContentController *)uc didReceiveScriptMessage:(WKScriptMessage *)m {
    if (![m.body isKindOfClass:[NSDictionary class]]) return;
    NSDictionary *d = m.body;
    NSString *cmd = d[@"cmd"];
    if ([cmd isEqualToString:@"play"]) {
        station = d[@"title"] ?: @"PodRadio";
        track = @"";
        retries = 0;
        [self play:d[@"url"]];
    } else if ([cmd isEqualToString:@"pause"]) {
        want = NO;
        [player pause];
        [self js:@"rrnState('stop')"];
        [self nowPlaying];
    } else if ([cmd isEqualToString:@"np"]) {
        track = d[@"title"] ?: @"";
        [self nowPlaying];
    } else if ([cmd isEqualToString:@"playFile"]) {
        NSString *name = [d[@"name"] lastPathComponent];
        if (!name.length) return;
        station = d[@"title"] ?: name;
        track = @"";
        retries = 0;
        [self play:[NSURL fileURLWithPath:[[self docs] stringByAppendingPathComponent:name]].absoluteString];
    } else if ([cmd isEqualToString:@"files"]) {
        [self sendFiles];
    } else if ([cmd isEqualToString:@"delFile"]) {
        NSString *name = [d[@"name"] lastPathComponent];
        if (name.length) [[NSFileManager defaultManager] removeItemAtPath:[[self docs] stringByAppendingPathComponent:name] error:nil];
        [self sendFiles];
    } else if ([cmd isEqualToString:@"pick"]) {
        UIDocumentPickerViewController *p = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.audio"] inMode:UIDocumentPickerModeImport];
        p.delegate = self;
        p.modalPresentationStyle = UIModalPresentationFormSheet;
        [self presentViewController:p animated:YES completion:nil];
    }
}

#pragma mark - свои файлы («Папка»): папка «Документы» приложения, её видно и в iTunes на компьютере

- (NSString *)docs {
    return NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
}

- (void)sendFiles {
    NSArray *ext = @[@"mp3", @"m4a", @"aac", @"wav", @"aif", @"aiff", @"caf", @"mp4", @"m4b", @"flac"];
    NSMutableArray *out = [NSMutableArray new];
    NSArray *names = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:[self docs] error:nil]
                      sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
    for (NSString *n in names) {
        if (![ext containsObject:n.pathExtension.lowercaseString]) continue;
        NSDictionary *a = [[NSFileManager defaultManager] attributesOfItemAtPath:[[self docs] stringByAppendingPathComponent:n] error:nil];
        [out addObject:@{@"name": n, @"size": @([a fileSize])}];
    }
    NSData *j = [NSJSONSerialization dataWithJSONObject:out options:0 error:nil];
    [self js:[NSString stringWithFormat:@"window.rrnFiles&&rrnFiles(%@)", [[NSString alloc] initWithData:j encoding:NSUTF8StringEncoding]]];
}

- (void)importFile:(NSURL *)src {
    NSString *name = src.lastPathComponent;
    NSString *dst = [[self docs] stringByAppendingPathComponent:name];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (int k = 2; [fm fileExistsAtPath:dst]; k++)
        dst = [[self docs] stringByAppendingPathComponent:[NSString stringWithFormat:@"%@ (%d).%@", name.stringByDeletingPathExtension, k, name.pathExtension]];
    if (![fm moveItemAtURL:src toURL:[NSURL fileURLWithPath:dst] error:nil])
        [fm copyItemAtURL:src toURL:[NSURL fileURLWithPath:dst] error:nil];
    [self sendFiles];
}

- (void)documentPicker:(UIDocumentPickerViewController *)c didPickDocumentAtURL:(NSURL *)u {
    [self importFile:u];
}

- (void)js:(NSString *)s { [web evaluateJavaScript:s completionHandler:nil]; }

- (NSString *)jsStr:(NSString *)s {
    NSData *j = [NSJSONSerialization dataWithJSONObject:@[s ?: @""] options:0 error:nil];
    NSString *a = [[NSString alloc] initWithData:j encoding:NSUTF8StringEncoding];
    return [a substringWithRange:NSMakeRange(1, a.length - 2)];
}

#pragma mark - воспроизведение

- (void)play:(NSString *)u {
    if (!u.length) return;
    url = u;
    want = YES;
    [[AVAudioSession sharedInstance] setActive:YES error:nil];
    [self dropItem];
    item = [AVPlayerItem playerItemWithURL:[NSURL URLWithString:u]];
    [item addObserver:self forKeyPath:@"status" options:0 context:nil];
    [item addObserver:self forKeyPath:@"timedMetadata" options:0 context:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(broken:) name:AVPlayerItemFailedToPlayToEndTimeNotification object:item];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(broken:) name:AVPlayerItemPlaybackStalledNotification object:item];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(ended:) name:AVPlayerItemDidPlayToEndTimeNotification object:item];
    if (!player) {
        player = [AVPlayer playerWithPlayerItem:item];
        [player addObserver:self forKeyPath:@"timeControlStatus" options:0 context:nil];
    } else {
        [player replaceCurrentItemWithPlayerItem:item];
    }
    [player play];
    [self nowPlaying];
}

- (void)dropItem {
    if (!item) return;
    [item removeObserver:self forKeyPath:@"status"];
    [item removeObserver:self forKeyPath:@"timedMetadata"];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:nil object:item];
    item = nil;
}

// свой файл доиграл — следующий
- (void)ended:(NSNotification *)n {
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self->url hasPrefix:@"file:"]) [self js:@"window.rrnEnded&&rrnEnded()"];
        else [self broken:n];
    });
}

// обрыв потока: до 3 переподключений
- (void)broken:(NSNotification *)n {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self->want || !self->url) return;
        if (self->retries++ < 3) {
            NSString *u = self->url;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * self->retries * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (self->want && [u isEqualToString:self->url]) [self play:u];
            });
        } else {
            self->want = NO;
            [self js:@"rrnState('err')"];
        }
    });
}

- (void)observeValueForKeyPath:(NSString *)k ofObject:(id)o change:(NSDictionary *)ch context:(void *)ctx {
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([k isEqualToString:@"timeControlStatus"]) {
            AVPlayerTimeControlStatus s = self->player.timeControlStatus;
            if (s == AVPlayerTimeControlStatusPlaying) { self->retries = 0; [self js:@"rrnState('play')"]; }
            else if (s == AVPlayerTimeControlStatusWaitingToPlayAtSpecifiedRate) [self js:@"rrnState('load')"];
            else if (!self->want) [self js:@"rrnState('stop')"];
            [self nowPlaying];
        } else if ([k isEqualToString:@"status"] && o == self->item) {
            if (self->item.status == AVPlayerItemStatusFailed) [self broken:nil];
        } else if ([k isEqualToString:@"timedMetadata"] && o == self->item) {
            for (AVMetadataItem *m in self->item.timedMetadata) {
                NSString *v = m.stringValue;
                if (!v.length) continue;
                NSString *key = [m.key isKindOfClass:[NSString class]] ? (NSString *)m.key : @"";
                if ([key isEqualToString:@"StreamTitle"] || [m.commonKey isEqualToString:AVMetadataCommonKeyTitle] || !key.length) {
                    [self js:[NSString stringWithFormat:@"rrnTrack(%@)", [self jsStr:v]]];
                    break;
                }
            }
        }
    });
}

#pragma mark - экран блокировки и наушники

- (void)nowPlaying {
    NSMutableDictionary *i = [NSMutableDictionary new];
    i[MPMediaItemPropertyTitle] = track.length ? track : (station ?: @"PodRadio");
    i[MPMediaItemPropertyArtist] = track.length ? (station ?: @"PodRadio") : @"PodRadio";
    i[MPNowPlayingInfoPropertyPlaybackRate] = @(want ? 1.0 : 0.0);
    UIImage *art = [UIImage imageNamed:@"AppIcon76x76"];
    if (art) i[MPMediaItemPropertyArtwork] = [[MPMediaItemArtwork alloc] initWithBoundsSize:art.size requestHandler:^UIImage *(CGSize s) { return art; }];
    [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = i;
}

- (void)setupRemote {
    MPRemoteCommandCenter *c = [MPRemoteCommandCenter sharedCommandCenter];
    __weak PlayerVC *w = self;
    [c.playCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) { [w js:@"rrnKey('play')"]; return MPRemoteCommandHandlerStatusSuccess; }];
    [c.pauseCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) { [w js:@"rrnKey('pause')"]; return MPRemoteCommandHandlerStatusSuccess; }];
    [c.togglePlayPauseCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) { [w js:@"rrnKey('toggle')"]; return MPRemoteCommandHandlerStatusSuccess; }];
    [c.nextTrackCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) { [w js:@"rrnKey('next')"]; return MPRemoteCommandHandlerStatusSuccess; }];
    [c.previousTrackCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) { [w js:@"rrnKey('prev')"]; return MPRemoteCommandHandlerStatusSuccess; }];
}

#pragma mark - окна alert / confirm / prompt страницы

- (void)webView:(WKWebView *)v runJavaScriptAlertPanelWithMessage:(NSString *)msg initiatedByFrame:(WKFrameInfo *)f completionHandler:(void (^)(void))done {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:nil message:msg preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { done(); }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)webView:(WKWebView *)v runJavaScriptConfirmPanelWithMessage:(NSString *)msg initiatedByFrame:(WKFrameInfo *)f completionHandler:(void (^)(BOOL))done {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:nil message:msg preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Отмена" style:UIAlertActionStyleCancel handler:^(UIAlertAction *x) { done(NO); }]];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { done(YES); }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)webView:(WKWebView *)v runJavaScriptTextInputPanelWithPrompt:(NSString *)p defaultText:(NSString *)t initiatedByFrame:(WKFrameInfo *)f completionHandler:(void (^)(NSString *))done {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:nil message:p preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.text = t; }];
    [a addAction:[UIAlertAction actionWithTitle:@"Отмена" style:UIAlertActionStyleCancel handler:^(UIAlertAction *x) { done(nil); }]];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { done(a.textFields.firstObject.text); }]];
    [self presentViewController:a animated:YES completion:nil];
}

@end

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (strong, nonatomic) UIWindow *window;
@end

@implementation AppDelegate
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)opts {
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
    [app beginReceivingRemoteControlEvents];
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.rootViewController = [PlayerVC new];
    [self.window makeKeyAndVisible];
    return YES;
}

// «Открыть в PodRadio» из другого приложения: файл попадает в «Папку»
- (BOOL)application:(UIApplication *)app openURL:(NSURL *)u options:(NSDictionary *)o {
    if (u.isFileURL) [(PlayerVC *)self.window.rootViewController importFile:u];
    return YES;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }
}
