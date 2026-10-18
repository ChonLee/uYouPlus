#import "uYouPlus.h"
#import <YouTubeHeader/MLHAMQueuePlayer.h>
#import <YouTubeHeader/YTMainAppControlsOverlayView.h>
#import <YouTubeHeader/YTMainAppVideoPlayerOverlayViewController.h>
#import <YouTubeHeader/YTPlayerViewController.h>
#import <YouTubeHeader/YTSingleVideoController.h>
#import <YouTubeHeader/YTVarispeedSwitchControllerDelegate.h>

// [−] 1.25x [+] speed controls on the left of the player, stepping 0.25x from 0.25x up to 5x.
// Tapping the speed label resets to 1x. Also lifts YouTube's own playback rate cap to 5x.

#define SPEED_STEP 0.25f
#define SPEED_MIN 0.25f
#define SPEED_MAX 5.0f
#define SPEED_BUTTON_SIZE 32.0f
#define SPEED_LABEL_WIDTH 54.0f
#define SPEED_CONTAINER_HEIGHT 34.0f

static NSString *const SpeedStepRateDidChangeNotification = @"SpeedStepRateDidChangeNotification";
static float lastKnownRate = 1.0f;

@interface YTPlaybackSpeedUtils : NSObject
@end

@interface YTMainAppControlsOverlayView (SpeedStep)
@property (retain, nonatomic) UIView *speedStepContainer;
@property (retain, nonatomic) UIButton *speedStepLabel;
@property (assign, nonatomic) BOOL speedStepVisible;
- (void)speedStepDidPressMinus:(id)sender;
- (void)speedStepDidPressPlus:(id)sender;
- (void)speedStepDidPressReset:(id)sender;
- (void)speedStepRefresh:(id)arg;
@end

static NSString *speedStepText(float rate) {
    return [NSString stringWithFormat:@"%.2fx", rate];
}

static YTMainAppVideoPlayerOverlayViewController *speedStepController(YTMainAppControlsOverlayView *self) {
    @try {
        return [self valueForKey:@"_eventsDelegate"];
    } @catch (id ex) {
        return nil;
    }
}

static UIView *speedStepIvarView(YTMainAppControlsOverlayView *self, NSString *ivar) {
    @try {
        return [self valueForKey:ivar];
    } @catch (id ex) {
        return nil;
    }
}

static float speedStepCurrentRate(YTMainAppVideoPlayerOverlayViewController *c) {
    if ([c respondsToSelector:@selector(currentPlaybackRate)]) {
        float rate = [c currentPlaybackRate];
        if (rate > 0) return rate;
    }
    return lastKnownRate;
}

static void speedStepApplyRate(YTMainAppVideoPlayerOverlayViewController *c, float rate) {
    rate = MIN(MAX(rate, SPEED_MIN), SPEED_MAX);
    id delegate = c.delegate;
    if ([delegate respondsToSelector:@selector(varispeedSwitchController:didSelectRate:)])
        [(id <YTVarispeedSwitchControllerDelegate>)delegate varispeedSwitchController:nil didSelectRate:rate];
    else if ([c respondsToSelector:@selector(setPlaybackRate:)])
        [c setPlaybackRate:rate];
    lastKnownRate = rate;
    [[NSNotificationCenter defaultCenter] postNotificationName:SpeedStepRateDidChangeNotification object:nil];
}

static UIButton *speedStepIconButton(NSString *symbol, NSString *accessibilityLabel) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightBold];
    [button setImage:[UIImage systemImageNamed:symbol withConfiguration:config] forState:UIControlStateNormal];
    button.tintColor = [UIColor whiteColor];
    button.accessibilityLabel = accessibilityLabel;
    return button;
}

static UIView *speedStepBuildContainer(YTMainAppControlsOverlayView *self) {
    CGFloat width = SPEED_BUTTON_SIZE * 2 + SPEED_LABEL_WIDTH;
    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, SPEED_CONTAINER_HEIGHT)];
    container.alpha = 0;

    UIVisualEffectView *background = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark]];
    background.frame = container.bounds;
    background.layer.cornerRadius = SPEED_CONTAINER_HEIGHT / 2;
    background.clipsToBounds = YES;
    background.userInteractionEnabled = NO;
    [container addSubview:background];

    UIButton *minus = speedStepIconButton(@"minus", @"Decrease playback speed");
    minus.frame = CGRectMake(0, (SPEED_CONTAINER_HEIGHT - SPEED_BUTTON_SIZE) / 2, SPEED_BUTTON_SIZE, SPEED_BUTTON_SIZE);
    [minus addTarget:self action:@selector(speedStepDidPressMinus:) forControlEvents:UIControlEventTouchUpInside];
    [container addSubview:minus];

    UIButton *label = [UIButton buttonWithType:UIButtonTypeCustom];
    label.frame = CGRectMake(SPEED_BUTTON_SIZE, 0, SPEED_LABEL_WIDTH, SPEED_CONTAINER_HEIGHT);
    label.titleLabel.font = [UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightSemibold];
    [label setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [label setTitle:speedStepText(speedStepCurrentRate(speedStepController(self))) forState:UIControlStateNormal];
    label.accessibilityLabel = @"Reset playback speed";
    [label addTarget:self action:@selector(speedStepDidPressReset:) forControlEvents:UIControlEventTouchUpInside];
    [container addSubview:label];

    UIButton *plus = speedStepIconButton(@"plus", @"Increase playback speed");
    plus.frame = CGRectMake(SPEED_BUTTON_SIZE + SPEED_LABEL_WIDTH, (SPEED_CONTAINER_HEIGHT - SPEED_BUTTON_SIZE) / 2, SPEED_BUTTON_SIZE, SPEED_BUTTON_SIZE);
    [plus addTarget:self action:@selector(speedStepDidPressPlus:) forControlEvents:UIControlEventTouchUpInside];
    [container addSubview:plus];

    self.speedStepLabel = label;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(speedStepRefresh:) name:SpeedStepRateDidChangeNotification object:nil];
    return container;
}

static void speedStepSetVisible(YTMainAppControlsOverlayView *self, BOOL visible) {
    self.speedStepVisible = visible;
    UIView *container = self.speedStepContainer;
    if (!container) return;
    if (visible) [self speedStepRefresh:nil];
    [UIView animateWithDuration:0.2 animations:^{
        container.alpha = visible ? 1 : 0;
    }];
}

%group SpeedStepButtons

%hook YTMainAppControlsOverlayView

%property (retain, nonatomic) UIView *speedStepContainer;
%property (retain, nonatomic) UIButton *speedStepLabel;
%property (assign, nonatomic) BOOL speedStepVisible;

- (void)layoutSubviews {
    %orig;
    if (!self.speedStepContainer) {
        self.speedStepContainer = speedStepBuildContainer(self);
        [self addSubview:self.speedStepContainer];
        self.speedStepContainer.alpha = self.speedStepVisible ? 1 : 0;
    }
    UIView *container = self.speedStepContainer;
    UIView *playPause = speedStepIvarView(self, @"_playPauseButton");
    UIView *previous = speedStepIvarView(self, @"_previousButtonView");

    CGFloat centerY = playPause.superview ? [playPause.superview convertPoint:playPause.center toView:self].y : CGRectGetMidY(self.bounds);
    CGFloat left = self.safeAreaInsets.left + 12;
    // Stay clear of the previous-video button; shrink a little on narrow players rather than overlap it.
    CGFloat limit = previous.superview && !previous.hidden && previous.alpha > 0
        ? CGRectGetMinX([previous.superview convertRect:previous.frame toView:self]) - 8
        : CGRectGetMidX(self.bounds) - 48;
    CGFloat width = SPEED_BUTTON_SIZE * 2 + SPEED_LABEL_WIDTH;
    CGFloat scale = MIN(1, MAX(0.7, (limit - left) / width));

    container.transform = CGAffineTransformIdentity;
    container.frame = CGRectMake(0, 0, width, SPEED_CONTAINER_HEIGHT);
    container.transform = CGAffineTransformMakeScale(scale, scale);
    container.center = CGPointMake(left + width * scale / 2, centerY);
    [self bringSubviewToFront:container];
}

- (void)setOverlayVisible:(BOOL)visible {
    %orig;
    speedStepSetVisible(self, visible);
}

- (void)setTopOverlayVisible:(BOOL)visible isAutonavCanceledState:(BOOL)canceledState {
    %orig;
    speedStepSetVisible(self, visible && !canceledState);
}

%new(v@:@)
- (void)speedStepDidPressMinus:(id)sender {
    YTMainAppVideoPlayerOverlayViewController *c = speedStepController(self);
    float rate = speedStepCurrentRate(c);
    speedStepApplyRate(c, ceilf(rate / SPEED_STEP - 0.001f) * SPEED_STEP - SPEED_STEP);
}

%new(v@:@)
- (void)speedStepDidPressPlus:(id)sender {
    YTMainAppVideoPlayerOverlayViewController *c = speedStepController(self);
    float rate = speedStepCurrentRate(c);
    speedStepApplyRate(c, floorf(rate / SPEED_STEP + 0.001f) * SPEED_STEP + SPEED_STEP);
}

%new(v@:@)
- (void)speedStepDidPressReset:(id)sender {
    speedStepApplyRate(speedStepController(self), 1.0f);
}

%new(v@:@)
- (void)speedStepRefresh:(id)arg {
    [self.speedStepLabel setTitle:speedStepText(speedStepCurrentRate(speedStepController(self))) forState:UIControlStateNormal];
}

%end

%hook YTPlayerViewController

- (void)singleVideo:(id)video playbackRateDidChange:(float)rate {
    %orig;
    lastKnownRate = rate;
    [[NSNotificationCenter defaultCenter] postNotificationName:SpeedStepRateDidChangeNotification object:nil];
}

%end

// YouTube clamps every rate change to a server-provided maximum.
%hook YTPlaybackSpeedUtils

+ (id)clampPlaybackRateModel:(id)model minPlaybackRate:(double)minRate maxPlaybackRate:(double)maxRate qoePingController:(id)qoePingController shouldLogError:(BOOL)shouldLogError {
    return %orig(model, MIN(minRate, SPEED_MIN), MAX(maxRate, SPEED_MAX), qoePingController, shouldLogError);
}

%end

%hook YTSingleVideoController

- (float)maximumSupportedPlaybackRate {
    return MAX(%orig, SPEED_MAX);
}

%end

%hook MLHAMQueuePlayer

- (float)maximumSupportedPlaybackRate {
    return MAX(%orig, SPEED_MAX);
}

%end

%end

%ctor {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    // Default on. Registered here rather than in uYouPlus.xm, whose %ctor runs after this one.
    if (![defaults objectForKey:kSpeedStepButtons])
        [defaults setBool:YES forKey:kSpeedStepButtons];
    if (IS_ENABLED(kSpeedStepButtons)) {
        %init(SpeedStepButtons);
    }
}
