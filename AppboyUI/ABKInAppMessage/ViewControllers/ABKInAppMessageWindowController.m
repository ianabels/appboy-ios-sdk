#import "ABKInAppMessageWindowController.h"
#import "ABKInAppMessageWindow.h"
#import "ABKInAppMessageView.h"
#import "ABKInAppMessageModal.h"
#import "ABKInAppMessageFull.h"
#import "ABKInAppMessageHTMLFull.h"
#import "ABKInAppMessageHTML.h"
#import "ABKInAppMessageHTMLBase.h"
#import "ABKInAppMessageHTMLBaseViewController.h"
#import "ABKInAppMessageImmersiveViewController.h"
#import "ABKInAppMessageSlideupViewController.h"
#import "ABKInAppMessageViewController.h"
#import "ABKURLDelegate.h"
#import "ABKUIURLUtils.h"
#import "ABKUIUtils.h"

static CGFloat const MinimumInAppMessageDismissVelocity = 20.0;

@implementation ABKInAppMessageWindowController

- (instancetype)initWithInAppMessage:(ABKInAppMessage *)inAppMessage
          inAppMessageViewController:(ABKInAppMessageViewController *)inAppMessageViewController
                inAppMessageDelegate:(id<ABKInAppMessageUIDelegate>)delegate {
  if (self = [super init]) {
    _inAppMessage = inAppMessage;
    _inAppMessageViewController = inAppMessageViewController;
    _inAppMessageUIDelegate = (id<ABKInAppMessageUIDelegate>)delegate;
    
    _inAppMessageWindow = [self createInAppMessageWindow];
    _inAppMessageWindow.backgroundColor = [UIColor clearColor];
    _inAppMessageWindow.autoresizingMask = UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleRightMargin;
    _inAppMessageIsTapped = NO;
    _clickedButtonId = -1;
    return self;
  } else {
    return nil;
  }
}

#pragma mark - Lifecycle Methods

- (void)viewDidLoad {
  [super viewDidLoad];
  [self addChildViewController:self.inAppMessageViewController];
  [self.inAppMessageViewController didMoveToParentViewController:self];
  self.view.backgroundColor = [UIColor clearColor];

  if ([self.inAppMessage isKindOfClass:[ABKInAppMessageSlideup class]]) {
    
    // Note: this gestureRecognizer won't catch taps which occur during the animation.
    UITapGestureRecognizer *inAppSlideupTapGesture = [[UITapGestureRecognizer alloc]
                                                      initWithTarget:self
                                                              action:@selector(inAppMessageTapped:)];
    [self.inAppMessageViewController.view addGestureRecognizer:inAppSlideupTapGesture];
    UIPanGestureRecognizer *inAppSlideupPanGesture = [[UIPanGestureRecognizer alloc]
                                                      initWithTarget:self
                                                              action:@selector(inAppSlideupWasPanned:)];
    [self.inAppMessageViewController.view addGestureRecognizer:inAppSlideupPanGesture];
    // We want to detect the pan gesture first, so we only recognize a tap when the pan recognizer fails.
    [inAppSlideupTapGesture requireGestureRecognizerToFail:inAppSlideupPanGesture];
  } else if ([self.inAppMessage isKindOfClass:[ABKInAppMessageImmersive class]]) {
    if (![ABKUIUtils objectIsValidAndNotEmpty:((ABKInAppMessageImmersive *)self.inAppMessage).buttons]) {
      UITapGestureRecognizer *inAppImmersiveInsideTapGesture = [[UITapGestureRecognizer alloc]
                                                                initWithTarget:self
                                                                        action:@selector(inAppMessageTapped:)];
      [self.inAppMessageViewController.view addGestureRecognizer:inAppImmersiveInsideTapGesture];
    }

    if ([self.inAppMessage isKindOfClass:[ABKInAppMessageModal class]]) {
      self.inAppMessageWindow.handleAllTouchEvents = YES;
    }
  }
  [self.view addSubview:self.inAppMessageViewController.view];
}

- (BOOL)prefersStatusBarHidden {
  if (self.inAppMessageViewController.overrideApplicationStatusBarHiddenState) {
    return self.inAppMessageViewController.prefersStatusBarHidden;
  }
  return [UIApplication sharedApplication].statusBarHidden;
}

#pragma mark - Rotation

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
  return self.supportedOrientationMask;
}

- (BOOL)shouldAutorotate {
  if ([UIDevice currentDevice].userInterfaceIdiom != UIUserInterfaceIdiomPad &&
      self.inAppMessage.orientation != ABKInAppMessageOrientationAny &&
      !self.inAppMessageWindow.hidden) {
    return NO;
  } else {
    return YES;
  }
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
  if (self.preferredOrientation != UIInterfaceOrientationUnknown) {
    return self.preferredOrientation;
  }
  return [ABKUIUtils getInterfaceOrientation];
}

#pragma mark - Gesture Recognizers

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
  return ![touch.view isKindOfClass:[ABKInAppMessageView class]];
}

- (void)inAppSlideupWasPanned:(UIPanGestureRecognizer *)panGestureRecognizer {
  ABKInAppMessageSlideupViewController *slideupVC = (ABKInAppMessageSlideupViewController *)self.inAppMessageViewController;
  
  switch (panGestureRecognizer.state) {
    case UIGestureRecognizerStateBegan: {
      self.slideupConstraintMaxValue = slideupVC.slideConstraint.constant;
      self.inAppMessagePreviousPanPosition = [panGestureRecognizer locationInView:self.inAppMessageViewController.view];
      break;
    }
      
    case UIGestureRecognizerStateChanged: {
      CGPoint position = [panGestureRecognizer locationInView:self.inAppMessageViewController.view];
      CGFloat direction = ((ABKInAppMessageSlideup *)self.inAppMessage).inAppMessageSlideupAnchor
                          == ABKInAppMessageSlideupFromBottom ? 1.0f : -1.0f;
      CGFloat diffY = (position.y - self.inAppMessagePreviousPanPosition.y) * direction;
      
      if (diffY > 0) {
        // The in-ap message is moved toward the near edge of the screen. The user is attempting to
        // dismiss the in-app message.
        slideupVC.slideConstraint.constant -= diffY * 2.0f;
      } else {
        // The in-app message is moved away from the near edge of the screen. The user is NOT attempting
        // to dismiss the in-app message.
        CGFloat moveY = -diffY * 0.3f;
        if (slideupVC.slideConstraint.constant + moveY <= self.slideupConstraintMaxValue) {
          slideupVC.slideConstraint.constant += moveY;
        } else {
          slideupVC.slideConstraint.constant = self.slideupConstraintMaxValue;
        }
      }
      self.inAppMessagePreviousPanPosition = position;
      break;
    }
      
    case UIGestureRecognizerStateEnded:
    case UIGestureRecognizerStateCancelled: {
      // The panning is finished. If the in-app messaged moved more than 25% of the distance towards the
      // edge, dismiss the in-app message.
      if ((self.slideupConstraintMaxValue - slideupVC.slideConstraint.constant) >
          self.slideupConstraintMaxValue / 4) {
        [self invalidateSlideAwayTimer];
        
        if ([self.inAppMessageUIDelegate respondsToSelector:@selector(onInAppMessageDismissed:)]) {
          [self.inAppMessageUIDelegate onInAppMessageDismissed:self.inAppMessage];
        }
        
        CGFloat velocity = [panGestureRecognizer velocityInView:self.inAppMessageViewController.view].y;
        velocity = fabs(velocity) > MinimumInAppMessageDismissVelocity ?
                   velocity : MinimumInAppMessageDismissVelocity;
        NSTimeInterval animationDuration = slideupVC.slideConstraint.constant / velocity;
        [self.inAppMessageViewController beforeMoveInAppMessageViewOffScreen];
        [UIView animateWithDuration:animationDuration
                              delay:0
                            options:UIViewAnimationOptionBeginFromCurrentState
                         animations:^{
                           [self.inAppMessageViewController moveInAppMessageViewOffScreen];
                         }
                         completion:^(BOOL finished){
                           if (finished) {
                             [self hideInAppMessageWindow];
                           }
                         }];
      } else {
        // The in-app message hasn't moved enough to be dismissed. Move it back to the original position.
        slideupVC.slideConstraint.constant = self.slideupConstraintMaxValue;
        [UIView animateWithDuration:0.2f animations:^{
          [self.view layoutIfNeeded];
        }];
      }
      break;
    }
      
    default:
      break;
  }
}

- (void)inAppMessageTapped:(id)sender {
  [self invalidateSlideAwayTimer];
  self.inAppMessageIsTapped = YES;
  
  if (![self delegateHandlesInAppMessageClick]) {
    [self inAppMessageClickedWithActionType:self.inAppMessage.inAppMessageClickActionType
                                        URL:self.inAppMessage.uri
                           openURLInWebView:self.inAppMessage.openUrlInWebView];
  }
}

#pragma mark - Timer

- (void)invalidateSlideAwayTimer {
  if (self.slideAwayTimer != nil) {
    [self.slideAwayTimer invalidate];
    self.slideAwayTimer = nil;
  }
}

- (void)inAppMessageTimerFired:(NSTimer *)timer {
  if ([self.inAppMessageUIDelegate respondsToSelector:@selector(onInAppMessageDismissed:)]) {
    [self.inAppMessageUIDelegate onInAppMessageDismissed:self.inAppMessage];
  }
  [self hideInAppMessageViewWithAnimation:self.inAppMessage.animateOut];
}

#pragma mark - Keyboard

- (void)keyboardWasShown {
  if (![self.inAppMessageViewController isKindOfClass:[ABKInAppMessageHTMLBaseViewController class]]
      && !self.inAppMessageWindow.hidden) {
    // If the keyboard is shown while an in-app message is on the screen, we hide the in-app message
    [self hideInAppMessageWindow];
  }
}

#pragma mark - Display and Hide In-app Message

- (void)displayInAppMessageViewWithAnimation:(BOOL)withAnimation {
  dispatch_async(dispatch_get_main_queue(), ^{
    // Set the root view controller after the inAppMessagewindow becomes the key window so it gets the
    // correct window size during and after rotation.
    [self.inAppMessageWindow makeKeyWindow];
    self.inAppMessageWindow.rootViewController = self;
    self.inAppMessageWindow.hidden = NO;

    if (self.inAppMessage.inAppMessageDismissType == ABKInAppMessageDismissAutomatically) {
      self.slideAwayTimer = [NSTimer scheduledTimerWithTimeInterval:self.inAppMessage.duration + InAppMessageAnimationDuration
                                                             target:self
                                                           selector:@selector(inAppMessageTimerFired:)
                                                           userInfo:nil repeats:NO];
    }
    [self.view layoutIfNeeded];
    [self.inAppMessageViewController beforeMoveInAppMessageViewOnScreen];
    if (withAnimation) {
      [UIView animateWithDuration:InAppMessageAnimationDuration
                            delay:0
                          options:UIViewAnimationOptionBeginFromCurrentState
                       animations:^{
                         [self.inAppMessageViewController moveInAppMessageViewOnScreen];
                       }
                       completion:^(BOOL finished){
                         [self.inAppMessage logInAppMessageImpression];
                       }];
    } else {
      [self.inAppMessageViewController moveInAppMessageViewOnScreen];
      [self.inAppMessage logInAppMessageImpression];
    }
  });
}

- (void)hideInAppMessageViewWithAnimation:(BOOL)withAnimation {
  [self hideInAppMessageViewWithAnimation:withAnimation completionHandler:nil];
}

- (void)hideInAppMessageViewWithAnimation:(BOOL)withAnimation
                        completionHandler:(void (^ __nullable)(void))completionHandler {
  [self.slideAwayTimer invalidate];
  self.slideAwayTimer = nil;
  [self.view layoutIfNeeded];
  [self.inAppMessageViewController beforeMoveInAppMessageViewOffScreen];
  if (withAnimation) {
    [UIView animateWithDuration:InAppMessageAnimationDuration
                          delay:0
                        options:UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
                       [self.inAppMessageViewController moveInAppMessageViewOffScreen];
                     }
                     completion:^(BOOL finished){
                       if (completionHandler) {
                         completionHandler();
                       }
                       [self hideInAppMessageWindow];
                     }];
  } else {
    [self.inAppMessageViewController moveInAppMessageViewOffScreen];
    [self hideInAppMessageWindow];
  }
}

- (void)hideInAppMessageWindow {
  [self.slideAwayTimer invalidate];
  self.slideAwayTimer = nil;

  self.inAppMessageWindow = nil;
  [[NSNotificationCenter defaultCenter] postNotificationName:ABKNotificationInAppMessageWindowDismissed
                                                      object:self
                                                    userInfo:nil];
  if (self.clickedButtonId >= 0) {
    [(ABKInAppMessageImmersive *)self.inAppMessage logInAppMessageClickedWithButtonID:self.clickedButtonId];
  } else if (self.inAppMessageIsTapped) {
    [self.inAppMessage logInAppMessageClicked];
  } else if ([ABKUIUtils objectIsValidAndNotEmpty:self.clickedHTMLButtonId]) {
    [(ABKInAppMessageHTMLBase *)self.inAppMessage logInAppMessageHTMLClickWithButtonID:self.clickedHTMLButtonId];
  }
}

#pragma mark - In-app Message and Button Clicks

- (BOOL)delegateHandlesInAppMessageClick {
  if ([self.inAppMessageUIDelegate respondsToSelector:@selector(onInAppMessageClicked:)]) {
    if ([self.inAppMessageUIDelegate onInAppMessageClicked:self.inAppMessage]) {
      NSLog(@"No in-app message click action will be performed by Braze as inAppMessageDelegate %@ returned YES in onInAppMessageClicked:", self.inAppMessageUIDelegate);
      return YES;
    }
  }
  return NO;
}

- (void)inAppMessageClickedWithActionType:(ABKInAppMessageClickActionType)actionType
                                      URL:(NSURL *)url
                         openURLInWebView:(BOOL)openUrlInWebView {
  [self invalidateSlideAwayTimer];
  switch (actionType) {
    case ABKInAppMessageNoneClickAction:
      break;
    case ABKInAppMessageDisplayNewsFeed:
      [self displayModalFeedView];
      break;
    case ABKInAppMessageRedirectToURI:
      if ([ABKUIUtils objectIsValidAndNotEmpty:url]) {
        [self handleInAppMessageURL:url inWebView:openUrlInWebView];
      }
      break;
  }
  [self hideInAppMessageViewWithAnimation:self.inAppMessage.animateOut];
}

#pragma mark - Display News Feed

- (void)displayModalFeedView {
  Class ModalFeedViewControllerClass = [ABKUIUtils getModalFeedViewControllerClass];
  if (ModalFeedViewControllerClass != nil) {
    UIViewController *topmostViewController =
      [ABKUIURLUtils topmostViewControllerWithRootViewController:ABKUIUtils.activeApplicationViewController];
    [topmostViewController presentViewController:[[ModalFeedViewControllerClass alloc] init]
                                                 animated:YES
                                               completion:nil];
  }
}

#pragma mark - URL Handling

- (void)handleInAppMessageURL:(NSURL *)url inWebView:(BOOL)openUrlInWebView {
  if (![self delegateHandlesInAppMessageURL:url]) {
    [self openInAppMessageURL:url inWebView:openUrlInWebView];
  }
}

- (BOOL)delegateHandlesInAppMessageURL:(NSURL *)url {
  return [ABKUIURLUtils URLDelegate:[Appboy sharedInstance].appboyUrlDelegate
                           handlesURL:url
                          fromChannel:ABKInAppMessageChannel
                           withExtras:self.inAppMessage.extras];
}

- (void)openInAppMessageURL:(NSURL *)url inWebView:(BOOL)openUrlInWebView {
  if ([ABKUIURLUtils URL:url shouldOpenInWebView:openUrlInWebView]) {
    UIViewController *topmostViewController =
      [ABKUIURLUtils topmostViewControllerWithRootViewController:ABKUIUtils.activeApplicationViewController];
    [ABKUIURLUtils displayModalWebViewWithURL:url topmostViewController:topmostViewController];
  } else {
    [ABKUIURLUtils openURLWithSystem:url fromChannel:ABKInAppMessageChannel];
  }
}

#pragma mark - Helpers

/*!
 * Creates and setups the ABKInAppMessageWindow used to display the in-app message
 *
 * @discussion First tries to create the window with the current UIWindowScene if available, then fallbacks
 *             to create the window with a frame.
 */
- (ABKInAppMessageWindow *)createInAppMessageWindow {
  ABKInAppMessageWindow *window;
  
  if (@available(iOS 13.0, *)) {
    UIWindowScene *windowScene = ABKUIUtils.activeWindowScene;
    if (windowScene) {
      window = [[ABKInAppMessageWindow alloc] initWithWindowScene:windowScene];
    }
  }
  
  if (!window) {
    window = [[ABKInAppMessageWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
  }
  
  window.backgroundColor = UIColor.clearColor;
  window.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                            UIViewAutoresizingFlexibleHeight;
  
  return window;
}

@end
