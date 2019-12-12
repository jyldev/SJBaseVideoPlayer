//
//  SJAliyunVodPlaybackController.m
//  Demo
//
//  Created by BlueDancer on 2019/11/13.
//  Copyright © 2019 SanJiang. All rights reserved.
//

#import "SJAliyunVodPlaybackController.h"
#import "SJAliyunVodPlayer.h"
#import "SJAliyunVodPlayerDefinitionLoader.h"

NS_ASSUME_NONNULL_BEGIN
@interface SJAliyunVodPlaybackController ()<SJAliyunVodPlayerDefinitionLoaderDataSource>
@property (nonatomic, strong, nullable) SJAliyunVodPlayer *player;
@property (nonatomic, strong, nullable) id periodicTimeObserver;
@property (nonatomic, strong, nullable) SJAliyunVodPlayerDefinitionLoader *definitionLoader;
@end

@implementation SJAliyunVodPlaybackController
@synthesize pauseWhenAppDidEnterBackground = _pauseWhenAppDidEnterBackground;
@synthesize periodicTimeInterval = _periodicTimeInterval;
@synthesize minBufferedDuration = _minBufferedDuration;
@synthesize delegate = _delegate;
@synthesize volume = _volume;
@synthesize rate = _rate;
@synthesize muted = _muted;
@synthesize media = _media;

- (instancetype)init {
    self = [super init];
    if ( self ) {
        _rate = 1;
        _volume = 1;
        _pauseWhenAppDidEnterBackground = YES;
        _periodicTimeInterval = 0.5;
        [self _initObservations];
    }
    return self;
}

- (void)dealloc {
#ifdef DEBUG
    NSLog(@"%d - %s", (int)__LINE__, __func__);
#endif
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)pause {
    [self.player pause];
}

- (void)play {
    [self.player play];
}

- (void)prepareToPlay {
    dispatch_async(dispatch_get_main_queue(), ^{
        if ( self.media.aliyunMedia != nil ) {
            self.player = [SJAliyunVodPlayer.alloc initWithMedia:self.media.aliyunMedia specifyStartTime:self.media.specifyStartTime];
        }
    });
}

- (void)refresh {
    self.player = nil;
    [self prepareToPlay];
    dispatch_async(dispatch_get_main_queue(), ^{    
        [self play];
    });
}

- (void)replay {
    [self.player replay];
}

- (nullable UIImage *)screenshot {
    return nil;
}

- (void)seekToTime:(NSTimeInterval)secs completionHandler:(void (^ _Nullable)(BOOL))completionHandler {
    [self.player seekToTime:CMTimeMakeWithSeconds(secs, NSEC_PER_SEC) completionHandler:completionHandler];
}

- (void)seekToTime:(CMTime)time toleranceBefore:(CMTime)toleranceBefore toleranceAfter:(CMTime)toleranceAfter completionHandler:(void (^ _Nullable)(BOOL))completionHandler {
    [self seekToTime:CMTimeGetSeconds(time) completionHandler:completionHandler];
}

- (void)stop {
    [_definitionLoader cancel];
    _definitionLoader = nil;
    
    [self _removePeriodicTimeObserver];
    self.player = nil;
}

- (SJAssetStatus)assetStatus {
    return _player.assetStatus;
}

- (SJPlaybackTimeControlStatus)timeControlStatus {
    return _player.timeControlStatus;
}

- (nullable SJWaitingReason)reasonForWaitingToPlay {
    return _player.reasonForWaitingToPlay;
}

- (NSTimeInterval)currentTime {
    return _player.currentTime;
}

- (NSTimeInterval)duration {
    return _player.duration;
}

- (NSTimeInterval)durationWatched {
    return 0;
}

- (nullable NSError *)error {
    return nil;
}

- (BOOL)isPlayed {
    return _player.isPlayed;
}

- (BOOL)isReplayed {
    return _player.isReplayed;
}

- (BOOL)isPlayedToEndTime {
    return _player.isPlayedToEndTime;
}

- (NSTimeInterval)playableDuration {
    return _player.playableDuration;
}

- (SJPlaybackType)playbackType {
    return SJPlaybackTypeUnknown;
}

@synthesize playerView = _playerView;
- (UIView *)playerView {
    if ( _playerView == nil ) {
        _playerView = [UIView.alloc initWithFrame:CGRectZero];
    }
    return _playerView;
}

- (BOOL)isReadyForDisplay {
    return _player.isReadyForDisplay;
}

- (CGSize)presentationSize {
    return _player.presentationSize;
}

@synthesize videoGravity = _videoGravity;
- (void)setVideoGravity:(SJVideoGravity)videoGravity {
    _videoGravity = videoGravity ? : AVLayerVideoGravityResizeAspect;
    _player.videoGravity = _videoGravity;
}
- (SJVideoGravity)videoGravity {
    if ( _videoGravity == nil )
        return AVLayerVideoGravityResizeAspect;
    return _videoGravity;
}

- (void)setPeriodicTimeInterval:(NSTimeInterval)periodicTimeInterval {
    _periodicTimeInterval = periodicTimeInterval;
    [self _removePeriodicTimeObserver];
    [self _addPeriodicTimeObserver];
}
 
- (void)setRate:(float)rate {
    _rate = rate;
    _player.rate = rate;
}

- (void)setVolume:(float)volume {
    _volume = volume;
    _player.volume = volume;
}

- (void)setMuted:(BOOL)muted {
    _muted = muted;
    _player.muted = muted;
}

- (void)setPauseWhenAppDidEnterBackground:(BOOL)pauseWhenAppDidEnterBackground {
    _pauseWhenAppDidEnterBackground = pauseWhenAppDidEnterBackground;
    _player.pauseWhenAppDidEnterBackground = pauseWhenAppDidEnterBackground;
}

- (void)setPlayer:(nullable SJAliyunVodPlayer *)player {
    _player = player;
    if ( player != nil ) {
        player.videoGravity = self.videoGravity;
        player.volume = self.volume;
        player.muted = self.muted;
        player.rate = self.rate;
        player.view.frame = self.playerView.bounds;
        player.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        player.pauseWhenAppDidEnterBackground = self.pauseWhenAppDidEnterBackground;
        [self.playerView addSubview:player.view];
        [self _addPeriodicTimeObserver];
    }
}

- (void)switchVideoDefinition:(SJVideoPlayerURLAsset *)media {
    if ( !media ) return;
    
    // clean
    if ( _definitionLoader != nil ) {
        [_definitionLoader cancel];
        _definitionLoader = nil;
    }
    
    // reset status
    [self _definitionSwitchingStatusDidChange:media status:SJDefinitionSwitchStatusUnknown];
    
    // begin
    [self _definitionSwitchingStatusDidChange:media status:SJDefinitionSwitchStatusSwitching];

    // prepare
    __weak typeof(self) _self = self;
    _definitionLoader = [SJAliyunVodPlayerDefinitionLoader.alloc initWithMedia:media.aliyunMedia dataSource:self completionHandler:^(SJAliyunVodPlayerDefinitionLoader * _Nonnull loader) {
        __strong typeof(_self) self = _self;
        if ( !self ) return;
        self.definitionLoader = nil;
        SJAliyunVodPlayer *_Nullable player = loader.player;
        if ( player == nil ) {
            [self _definitionSwitchingStatusDidChange:media status:SJDefinitionSwitchStatusFailed];
        }
        else {
            SJVideoPlayerURLAsset *newMedia = media;
            self.media = newMedia;
            
            SJAliyunVodPlayer *oldPlayer = self.player;
            SJAliyunVodPlayer *newPlayer = player;
            self.player = newPlayer;
            [oldPlayer pause];
            [newPlayer play];
            [newPlayer report];
            [self _definitionSwitchingStatusDidChange:media status:SJDefinitionSwitchStatusFinished];
        }
    }];
}

- (void)_definitionSwitchingStatusDidChange:(id<SJMediaModelProtocol>)media status:(SJDefinitionSwitchStatus)status {
    if ( [self.delegate respondsToSelector:@selector(playbackController:switchingDefinitionStatusDidChange:media:)] ) {
        [self.delegate playbackController:self switchingDefinitionStatusDidChange:status media:media];
    }

#ifdef DEBUG
    char *str = nil;
    switch ( status ) {
        case SJDefinitionSwitchStatusUnknown:
            str = "Unknown";
            break;
        case SJDefinitionSwitchStatusSwitching:
            str = "Switching";
            break;
        case SJDefinitionSwitchStatusFinished:
            str = "Finished";
            break;
        case SJDefinitionSwitchStatusFailed:
            str = "Failed";
            break;
    }
    printf("SJAliyunVodPlaybackController<%p>.switchStatus = %s\n", self, str);
#endif
}

- (UIView *)superview {
    return self.playerView;
}
#pragma mark -

- (void)_addPeriodicTimeObserver {
    __weak typeof(self) _self = self;
    _periodicTimeObserver = [_player addTimeObserverWithCurrentTimeDidChangeExeBlock:^(NSTimeInterval time) {
        __strong typeof(_self) self = _self;
        if ( !self ) return;
        if ( [self.delegate respondsToSelector:@selector(playbackController:currentTimeDidChange:)] ) {
            [self.delegate playbackController:self currentTimeDidChange:time];
        }
    } playableDurationDidChangeExeBlock:^(NSTimeInterval time) {
        __strong typeof(_self) self = _self;
        if ( !self ) return;
        if ( [self.delegate respondsToSelector:@selector(playbackController:playableDurationDidChange:)] ) {
            [self.delegate playbackController:self playableDurationDidChange:time];
        }
    } durationDidChangeExeBlock:^(NSTimeInterval time) {
        __strong typeof(_self) self = _self;
        if ( !self ) return;
        if ( [self.delegate respondsToSelector:@selector(playbackController:durationDidChange:)] ) {
            [self.delegate playbackController:self durationDidChange:time];
        }
    }];
}

- (void)_removePeriodicTimeObserver {
    if ( _periodicTimeObserver != nil ) {
        [_player removeTimeObserver:_periodicTimeObserver];
        _periodicTimeObserver = nil;
    }
}

- (void)_initObservations {
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(playerAssetStatusDidChange:) name:SJAliyunVodPlayerAssetStatusDidChangeNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(playerTimeControlStatusDidChange:) name:SJAliyunVodPlayerTimeControlStatusDidChangeNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(playerDidPlayToEndTime:) name:SJAliyunVodPlayerDidPlayToEndTimeNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(playerPresentationSizeDidChange:) name:SJAliyunVodPlayerPresentationSizeDidChangeNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(playerReadyForDisplay:) name:SJAliyunVodPlayerReadyForDisplayNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(playerDidReplay:) name:SJAliyunVodPlayerDidReplayNotification object:nil];
}

- (void)playerAssetStatusDidChange:(NSNotification *)note {
    if ( self.player == note.object ) {
        if ( [self.delegate respondsToSelector:@selector(playbackController:assetStatusDidChange:)] ) {
            [self.delegate playbackController:self assetStatusDidChange:self.assetStatus];
        }
    }
}

- (void)playerTimeControlStatusDidChange:(NSNotification *)note {
    if ( self.player == note.object ) {
        if ( [self.delegate respondsToSelector:@selector(playbackController:timeControlStatusDidChange:)] ) {
            [self.delegate playbackController:self timeControlStatusDidChange:self.timeControlStatus];
        }
    }
}

- (void)playerDidPlayToEndTime:(NSNotification *)note {
    if ( self.player == note.object ) {
        if ( [self.delegate respondsToSelector:@selector(mediaDidPlayToEndForPlaybackController:)] ) {
            [self.delegate mediaDidPlayToEndForPlaybackController:self];
        }
    }
}

- (void)playerPresentationSizeDidChange:(NSNotification *)note {
    if ( self.player == note.object ) {
        if ( [self.delegate respondsToSelector:@selector(playbackController:presentationSizeDidChange:)] ) {
            [self.delegate playbackController:self presentationSizeDidChange:self.presentationSize];
        }
    }
}

- (void)playerReadyForDisplay:(NSNotification *)note {
    if ( self.player == note.object ) {
        if ( [self.delegate respondsToSelector:@selector(playbackControllerIsReadyForDisplay:)] ) {
            [self.delegate playbackControllerIsReadyForDisplay:self];
        }
    }
}

- (void)playerDidReplay:(NSNotification *)note {
    if ( self.player == note.object ) {
        if ( [self.delegate respondsToSelector:@selector(playbackController:didReplay:)] ) {
            [self.delegate playbackController:self didReplay:self.media];
        }
    }
}
@end
NS_ASSUME_NONNULL_END
