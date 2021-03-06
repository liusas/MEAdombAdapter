//
//  MEAdombAdapter.m
//  MEAdvSDK
//
//  Created by 刘峰 on 2020/3/30.
//

#import "MEAdombAdapter.h"
#import <GoogleMobileAds/GoogleMobileAds.h>

@interface MEAdombAdapter ()<GADInterstitialDelegate, GADRewardedAdDelegate>
/// 插屏对象
@property (nonatomic, strong) GADInterstitial *interstitial;
/// 激励视频对象
@property (nonatomic, strong) GADRewardedAd *rewardedAd;
/// 判断激励视频是否能给奖励,每次关闭视频变false
@property (nonatomic, assign) BOOL isEarnRewarded;

/// 是否展示误点按钮
@property (nonatomic, assign) BOOL showFunnyBtn;
/// 是否需要展示
@property (nonatomic, assign) BOOL needShow;
@end

@implementation MEAdombAdapter

// MARK: - override
+ (instancetype)sharedInstance {
    static MEAdombAdapter *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[MEAdombAdapter alloc] init];
    });
    return sharedInstance;
}

+ (void)launchAdPlatformWithAppid:(NSString *)appid {
    // 初始化谷歌SDK
    [[GADMobileAds sharedInstance] startWithCompletionHandler:nil];
}

- (NSString *)networkName {
    return @"admob";
}

/// 获取广告平台类型
- (MEAdAgentType)platformType{
    return MEAdAgentTypeAdmob;
}

// MARK: - 插屏广告
- (BOOL)showInterstitialViewWithPosid:(NSString *)posid showFunnyBtn:(BOOL)showFunnyBtn {
    self.posid = posid;
    self.showFunnyBtn = showFunnyBtn;

    if (![self topVC]) {
        return NO;
    }

    if (!self.interstitial && (self.interstitial.hasBeenUsed || !self.interstitial.isReady)) {
        self.needShow = YES;
        self.interstitial = [self createAndLoadInterstitial];
    } else {
        self.needShow = NO;
        if (self.interstitial.isReady || self.interstitial.hasBeenUsed == false) {
            [self.interstitial presentFromRootViewController:[self topVC]];
        } else {
            self.needShow = YES;
            self.interstitial = [self createAndLoadInterstitial];
        }
    }

    return YES;
}

- (void)stopInterstitialWithPosid:(NSString *)posid {
    self.needShow = NO;
}

- (GADInterstitial *)createAndLoadInterstitial {
//    GADInterstitial *interstitial = [[GADInterstitial alloc] initWithAdUnitID:@"ca-app-pub-3940256099942544/4411468910"];
    GADInterstitial *interstitial = [[GADInterstitial alloc] initWithAdUnitID:self.posid];
    interstitial.delegate = self;
    [interstitial loadRequest:[GADRequest request]];
    return interstitial;
}

// MARK: - 激励视频广告
- (BOOL)showRewardVideoWithPosid:(NSString *)posid {
    self.posid = posid;
    self.isEarnRewarded = false;

    if (![self topVC]) {
        return NO;
    }

    if (self.isTheVideoPlaying == YES) {
        // 若当前有视频正在播放,则此次激励视频不播放
        return YES;
    }

    if (!self.rewardedAd || !self.rewardedAd.isReady) {
        self.rewardedAd = nil;
        self.needShow = YES;
        self.rewardedAd = [self createAndLoadRewardedAd];
    } else {
        self.needShow = NO;
        if (self.rewardedAd.isReady) {
            [self.rewardedAd presentFromRootViewController:[self topVC] delegate:self];
        } else {
            self.needShow = YES;
            self.interstitial = [self createAndLoadInterstitial];
        }
    }

    return YES;
}

- (void)stopCurrentVideoWithPosid:(NSString *)posid {
    self.needShow = NO;
    if (self.rewardedAd.isReady) {
        UIViewController *topVC = [self topVC];
        [topVC dismissViewControllerAnimated:YES completion:nil];
        //        self.rewardedVideoAd = nil;
    }
}

- (GADRewardedAd *)createAndLoadRewardedAd {
//    GADRewardedAd *rewardedAd = [[GADRewardedAd alloc] initWithAdUnitID:@"ca-app-pub-3940256099942544/1712485313"];
    GADRewardedAd *rewardedAd = [[GADRewardedAd alloc] initWithAdUnitID:self.posid];
    GADRequest *request = [GADRequest request];
    [rewardedAd loadRequest:request completionHandler:^(GADRequestError * _Nullable error) {
        if (error) {
            // Handle ad failed to load case.
            if (self.needShow && self.isTheVideoPlaying == NO && self.videoDelegate && [self.videoDelegate respondsToSelector:@selector(adapter:videoShowFailure:)]) {
                [self.videoDelegate adapter:self videoShowFailure:error];
            }
            
            // 上报日志
            MEAdLogModel *model = [MEAdLogModel new];
            model.event = AdLogEventType_Fault;
            model.st_t = AdLogAdType_RewardVideo;
            model.so_t = self.sortType;
            model.posid = self.sceneId;
            model.network = self.networkName;
            model.type = AdLogFaultType_Normal;
            model.code = error.code;
            if (error.localizedDescription != nil || error.localizedDescription.length > 0) {
                model.msg = error.localizedDescription;
            }
            model.tk = [self stringMD5:[NSString stringWithFormat:@"%@%ld%@%ld", model.posid, model.so_t, @"mobi", (long)([[NSDate date] timeIntervalSince1970]*1000)]];
            // 先保存到数据库
            [MEAdLogModel saveLogModelToRealm:model];
            // 立即上传
            [MEAdLogModel uploadImmediately];
            
        } else {
            // Ad successfully loaded.
            dispatch_async(dispatch_get_main_queue(), ^{
                if (self.needShow) {
                    self.isTheVideoPlaying = YES;
                    if (self.rewardedAd.isReady) {
                        [self.rewardedAd presentFromRootViewController:[self topVC] delegate:self];
                        
                        if (self.videoDelegate && [self.videoDelegate respondsToSelector:@selector(adapterVideoLoadSuccess:)]) {
                            [self.videoDelegate adapterVideoLoadSuccess:self];
                        }
                    }
                }
            });
            
            // 上报日志
            MEAdLogModel *model = [MEAdLogModel new];
            model.event = AdLogEventType_Load;
            model.st_t = AdLogAdType_RewardVideo;
            model.so_t = self.sortType;
            model.posid = self.sceneId;
            model.network = self.networkName;
            model.tk = [self stringMD5:[NSString stringWithFormat:@"%@%ld%@%ld", model.posid, model.so_t, @"mobi", (long)([[NSDate date] timeIntervalSince1970]*1000)]];
            // 先保存到数据库
            [MEAdLogModel saveLogModelToRealm:model];
            // 立即上传
            [MEAdLogModel uploadImmediately];
        }
    }];
    return rewardedAd;
}

// MARK: - GADRewardedAdDelegate
/// Tells the delegate that the user earned a reward.
- (void)rewardedAd:(GADRewardedAd *)rewardedAd userDidEarnReward:(GADAdReward *)reward {
    // TODO: Reward the user.
    self.isEarnRewarded = true;
}

/// Tells the delegate that the rewarded ad was presented.
- (void)rewardedAdDidPresent:(GADRewardedAd *)rewardedAd {
    if (self.videoDelegate && [self.videoDelegate respondsToSelector:@selector(adapterVideoShowSuccess:)]) {
        [self.videoDelegate adapterVideoShowSuccess:self];
    }
    
    // 上报日志
    MEAdLogModel *model = [MEAdLogModel new];
    model.event = AdLogEventType_Show;
    model.st_t = AdLogAdType_RewardVideo;
    model.so_t = self.sortType;
    model.posid = self.sceneId;
    model.network = self.networkName;
    model.tk = [self stringMD5:[NSString stringWithFormat:@"%@%ld%@%ld", model.posid, model.so_t, @"mobi", (long)([[NSDate date] timeIntervalSince1970]*1000)]];
    // 先保存到数据库
    [MEAdLogModel saveLogModelToRealm:model];
    // 立即上传
    [MEAdLogModel uploadImmediately];
}

/// Tells the delegate that the rewarded ad failed to present.
- (void)rewardedAd:(GADRewardedAd *)rewardedAd didFailToPresentWithError:(NSError *)error {
    NSLog(@"admob reward video error = %@", error);
    if (self.needShow) {
        if (self.videoDelegate && [self.videoDelegate respondsToSelector:@selector(adapter:videoShowFailure:)]) {
            [self.videoDelegate adapter:self videoShowFailure:error];
        }
    }
    
    // 上报日志
    MEAdLogModel *model = [MEAdLogModel new];
    model.event = AdLogEventType_Fault;
    model.st_t = AdLogAdType_RewardVideo;
    model.so_t = self.sortType;
    model.posid = self.sceneId;
    model.network = self.networkName;
    model.type = AdLogFaultType_Render;
    model.code = error.code;
    if (error.localizedDescription != nil || error.localizedDescription.length > 0) {
        model.msg = error.localizedDescription;
    }
    model.tk = [self stringMD5:[NSString stringWithFormat:@"%@%ld%@%ld", model.posid, model.so_t, @"mobi", (long)([[NSDate date] timeIntervalSince1970]*1000)]];
    // 先保存到数据库
    [MEAdLogModel saveLogModelToRealm:model];
    // 立即上传
    [MEAdLogModel uploadImmediately];
}

/// Tells the delegate that the rewarded ad was dismissed.
- (void)rewardedAdDidDismiss:(GADRewardedAd *)rewardedAd {
    self.isTheVideoPlaying = NO;
    self.needShow = NO;
    // 预加载
    self.rewardedAd = [self createAndLoadRewardedAd];

    // 若没达到奖励条件,则不给回调
    if (self.isEarnRewarded == false) {
        return;
    }

    if (self.videoDelegate && [self.videoDelegate respondsToSelector:@selector(adapterVideoClose:)]) {
        [self.videoDelegate adapterVideoClose:self];
    }

    // 变回默认的不给奖励
    self.isEarnRewarded = false;
}

// MARK: - GADInterstitialDelegate
/// Tells the delegate an ad request succeeded.
- (void)interstitialDidReceiveAd:(GADInterstitial *)ad {
    if (self.needShow) {
        if (self.interstitial.isReady) {
            [self.interstitial presentFromRootViewController:[self topVC]];
            
            if (self.interstitialDelegate && [self.interstitialDelegate respondsToSelector:@selector(adapterInterstitialLoadSuccess:)]) {
                [self.interstitialDelegate adapterInterstitialLoadSuccess:self];
            }
            
            // 上报日志
            MEAdLogModel *model = [MEAdLogModel new];
            model.event = AdLogEventType_Load;
            model.st_t = AdLogAdType_Interstitial;
            model.so_t = self.sortType;
            model.posid = self.sceneId;
            model.network = self.networkName;
            model.tk = [self stringMD5:[NSString stringWithFormat:@"%@%ld%@%ld", model.posid, model.so_t, @"mobi", (long)([[NSDate date] timeIntervalSince1970]*1000)]];
            // 先保存到数据库
            [MEAdLogModel saveLogModelToRealm:model];
            // 立即上传
            [MEAdLogModel uploadImmediately];
        }
    }
}

/// Tells the delegate an ad request failed.
- (void)interstitial:(GADInterstitial *)ad didFailToReceiveAdWithError:(GADRequestError *)error {
    if (self.needShow) {
        if (self.interstitialDelegate && [self.interstitialDelegate respondsToSelector:@selector(adapter:interstitialLoadFailure:)]) {
            [self.interstitialDelegate adapter:self interstitialLoadFailure:error];
        }
    }
    
    // 上报日志
    MEAdLogModel *model = [MEAdLogModel new];
    model.event = AdLogEventType_Fault;
    model.st_t = AdLogAdType_Interstitial;
    model.so_t = self.sortType;
    model.posid = self.sceneId;
    model.network = self.networkName;
    model.type = AdLogFaultType_Normal;
    model.code = error.code;
    if (error.localizedDescription != nil || error.localizedDescription.length > 0) {
        model.msg = error.localizedDescription;
    }
    model.tk = [self stringMD5:[NSString stringWithFormat:@"%@%ld%@%ld", model.posid, model.so_t, @"mobi", (long)([[NSDate date] timeIntervalSince1970]*1000)]];
    // 先保存到数据库
    [MEAdLogModel saveLogModelToRealm:model];
    // 立即上传
    [MEAdLogModel uploadImmediately];
}

/// Tells the delegate that an interstitial will be presented.
- (void)interstitialWillPresentScreen:(GADInterstitial *)ad {
    if (self.interstitialDelegate && [self.interstitialDelegate respondsToSelector:@selector(adapterInterstitialShowSuccess:)]) {
        [self.interstitialDelegate adapterInterstitialShowSuccess:self];
    }
    
    // 上报日志
    MEAdLogModel *model = [MEAdLogModel new];
    model.event = AdLogEventType_Show;
    model.st_t = AdLogAdType_Interstitial;
    model.so_t = self.sortType;
    model.posid = self.sceneId;
    model.network = self.networkName;
    model.tk = [self stringMD5:[NSString stringWithFormat:@"%@%ld%@%ld", model.posid, model.so_t, @"mobi", (long)([[NSDate date] timeIntervalSince1970]*1000)]];
    // 先保存到数据库
    [MEAdLogModel saveLogModelToRealm:model];
    // 立即上传
    [MEAdLogModel uploadImmediately];
}

/// Tells the delegate the interstitial is to be animated off the screen.
- (void)interstitialWillDismissScreen:(GADInterstitial *)ad {
    NSLog(@"interstitialWillDismissScreen");
}

- (void)interstitialDidDismissScreen:(GADInterstitial *)ad {
    if (self.interstitialDelegate && [self.interstitialDelegate respondsToSelector:@selector(adapterInterstitialCloseFinished:)]) {
        [self.interstitialDelegate adapterInterstitialCloseFinished:self];
    }

    // 在这次展示完广告后,重新加载另一个插屏广告
    self.needShow = NO;
    self.interstitial = [self createAndLoadInterstitial];
}

/// Tells the delegate that a user click will open another app
/// (such as the App Store), backgrounding the current app.
- (void)interstitialWillLeaveApplication:(GADInterstitial *)ad {
    if (self.interstitialDelegate && [self.interstitialDelegate respondsToSelector:@selector(adapterInterstitialClicked:)]) {
        [self.interstitialDelegate adapterInterstitialClicked:self];
    }
    
    // 上报日志
    MEAdLogModel *model = [MEAdLogModel new];
    model.event = AdLogEventType_Click;
    model.st_t = AdLogAdType_Interstitial;
    model.so_t = self.sortType;
    model.posid = self.sceneId;
    model.network = self.networkName;
    model.tk = [self stringMD5:[NSString stringWithFormat:@"%@%ld%@%ld", model.posid, model.so_t, @"mobi", (long)([[NSDate date] timeIntervalSince1970]*1000)]];
    // 先保存到数据库
    [MEAdLogModel saveLogModelToRealm:model];
    // 立即上传
    [MEAdLogModel uploadImmediately];
}



@end
