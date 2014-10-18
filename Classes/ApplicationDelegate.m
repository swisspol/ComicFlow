//  Copyright (C) 2010-2014 Pierre-Olivier Latour <info@pol-online.net>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.

#import "ApplicationDelegate.h"
#import "Extensions_Foundation.h"
#import "XLFunctions.h"
#import "XLDatabaseLogger.h"
#if DEBUG
#import "XLTelnetServerLogger.h"
#endif

#define kOverlayWindowLevel 100.0

#define kSpinnerBorderWidth 15.0
#define kSpinnerSpacing 10.0
#define kSpinnerFullscreenSpacing 18.0
#define kSpinnerViewAnimationDuration 0.5
#define kSpinnerFontSize 14.0
#define kSpinnerFullscreenFontSize 17.0

#define kLoggingHistoryMaxAge (7.0 * 24.0 * 60.0 * 60.0) // 7 days
#define kLoggingFontName @"Courier"
#define kLoggingFontSize 13.0

static ApplicationDelegate* _sharedInstance = nil;

@interface LogViewController : UIViewController
@end

@interface ApplicationDelegate (Internal)
- (void) _dismissAlertWithButtonIndex:(NSInteger)index;
@end

@implementation LogViewController

- (BOOL) shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
  return YES;
}

@end

@implementation ApplicationDelegate

@synthesize window=_window, viewController=_viewController;

+ (id) alloc {
  XLOG_DEBUG_CHECK(_sharedInstance == nil);
  _sharedInstance = [[super alloc] init];
  return _sharedInstance;
}

+ (id) sharedInstance {
  return _sharedInstance;
}

- (void) __alertView:(UIAlertView*)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex {
  if (alertView == _alertView) {
    [self _dismissAlertWithButtonIndex:buttonIndex];
  } else {
    XLOG_DEBUG_UNREACHABLE();
  }
}

+ (void) alertView:(UIAlertView*)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex {
  [[ApplicationDelegate sharedInstance] __alertView:alertView didDismissWithButtonIndex:buttonIndex];
}

- (BOOL) application:(UIApplication*)application didFinishLaunchingWithOptions:(NSDictionary*)launchOptions {
  // Configure logging
  [XLSharedFacility setLogsUncaughtExceptions:YES];
  [XLSharedFacility setLogsInitializedExceptions:YES];
  _databaseLogger = (XLDatabaseLogger*)[XLSharedFacility addLogger:[[XLDatabaseLogger alloc] init]];
#if DEBUG
  [XLSharedFacility addLogger:[[XLTelnetServerLogger alloc] init]];
#endif
  
  // Initialize overlay window
  _overlayWindow = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
  _overlayWindow.screen = [UIScreen mainScreen];
  _overlayWindow.windowLevel = kOverlayWindowLevel;
  _overlayWindow.userInteractionEnabled = NO;
  _overlayWindow.rootViewController = [[UIViewController alloc] init];
  _overlayWindow.rootViewController.view = [[UIView alloc] initWithFrame:_overlayWindow.bounds];
  
  return NO;
}

- (void) applicationDidEnterBackground:(UIApplication*)application {
  // Dismiss alert views
  [self dismissAlert:NO];
  
  // Save state
  [self saveState];
  
  // Make sure user defaults are synchronized
  [[NSUserDefaults standardUserDefaults] synchronize];
  
  // Purge log history
  [_databaseLogger purgeRecordsBeforeAbsoluteTime:(CFAbsoluteTimeGetCurrent() - kLoggingHistoryMaxAge)];
  
  XLOG_VERBOSE(@"Application did enter background");
}

- (void) applicationWillEnterForeground:(UIApplication*)application {
  XLOG_VERBOSE(@"Application will enter foreground");
  
  // Make sure user defaults are synchronized
  [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void) applicationWillTerminate:(UIApplication*)application {
  // Dismiss alert views
  [self dismissAlert:NO];
  
  // Save state
  [self saveState];
  
  // Make sure user defaults are synchronized
  [[NSUserDefaults standardUserDefaults] synchronize];
  
  // Purge log history
  [_databaseLogger purgeRecordsBeforeAbsoluteTime:(CFAbsoluteTimeGetCurrent() - kLoggingHistoryMaxAge)];
}

- (void) saveState {
  ;
}

@end

@implementation ApplicationDelegate (Logging)

- (void) purgeLogHistory {
  [_databaseLogger purgeAllRecords];
}

- (UIViewController*) _findTopViewController:(BOOL)skipLastModal {
  UIViewController* controller = _window.rootViewController;
  if (controller == nil) {
    controller = _viewController;
  }
  while (controller.modalViewController && (!skipLastModal || controller.modalViewController.modalViewController)) {
    controller = controller.modalViewController;
  }
  return controller;
}

- (void) _logViewControllerDone:(id)sender {
  [[self _findTopViewController:YES] dismissModalViewControllerAnimated:YES];
}

- (void) showLogViewController {
  NSMutableString* log = [NSMutableString string];
  [_databaseLogger enumerateAllRecordsBackward:YES usingBlock:^(int appVersion, XLLogRecord* record, BOOL* stop) {
    NSString* date = [[NSDate dateWithTimeIntervalSinceReferenceDate:record.absoluteTime] stringWithCachedFormat:@"yyyy-MM-dd HH:mm:ss.SSS" localIdentifier:@"en_US"];
    [log appendFormat:@"[r%i | %@ | %@] %@\n", appVersion, date, XLStringFromLogLevelName(record.level), record.message];
  }];
  
  UITextView* view = [[UITextView alloc] init];
  view.text = log;
  view.textColor = [UIColor darkGrayColor];
  view.font = [UIFont fontWithName:kLoggingFontName size:kLoggingFontSize];
  view.editable = NO;
  view.dataDetectorTypes = UIDataDetectorTypeNone;
  
  LogViewController* viewController = [[LogViewController alloc] init];
  viewController.view = view;
  viewController.navigationItem.title = NSLocalizedString(@"LOG_TITLE", nil);
  viewController.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                                                                    target:self
                                                                                                    action:@selector(_logViewControllerDone:)] autorelease];
  UINavigationController* navigationController = [[UINavigationController alloc] initWithRootViewController:viewController];
  [[self _findTopViewController:NO] presentModalViewController:navigationController animated:YES];
  [navigationController release];
  [viewController release];
  
  [view release];
}

@end

@implementation ApplicationDelegate (Alerts)

- (BOOL) isAlertVisible {
  return _alertView ? YES : NO;
}

- (void) _dismissAlertWithButtonIndex:(NSInteger)index {
  if (index == _alertView.cancelButtonIndex) {
    if (_alertDelegate && _alertCancelSelector) {
      [_alertDelegate performSelector:_alertCancelSelector withObject:_alertArgument];
    }
  } else {
    if (_alertDelegate && _alertConfirmSelector) {
      [_alertDelegate performSelector:_alertConfirmSelector withObject:_alertArgument];
    }
  }
  [_alertArgument release];
  [_alertDelegate release];
  [_alertView release];
  _alertView = nil;
}

- (void) showAlertWithTitle:(NSString*)title message:(NSString*)message button:(NSString*)button {
  [self showAlertWithTitle:title message:message button:button delegate:nil selector:NULL argument:nil];
}

- (void) showAlertWithTitle:(NSString*)title
                    message:(NSString*)message
                     button:(NSString*)button
                   delegate:(id)delegate
                   selector:(SEL)selector
                   argument:(id)argument {
  [self showAlertWithTitle:title
                   message:message
             confirmButton:button
              cancelButton:nil
                  delegate:delegate
           confirmSelector:selector
            cancelSelector:nil
                  argument:argument];
}

- (void) showAlertWithTitle:(NSString*)title
                    message:(NSString*)message
              confirmButton:(NSString*)confirmButton
               cancelButton:(NSString*)cancelButton
                   delegate:(id)delegate
            confirmSelector:(SEL)confirmSelector
             cancelSelector:(SEL)cancelSelector
                   argument:(id)argument {
  XLOG_CHECK(title);
  XLOG_CHECK(confirmButton);
  [self dismissAlert:NO];
  _alertView = [[UIAlertView alloc] initWithTitle:title
                                          message:message
                                         delegate:[ApplicationDelegate class]
                                cancelButtonTitle:cancelButton
                                otherButtonTitles:confirmButton, nil];
  _alertDelegate = [delegate retain];
  _alertConfirmSelector = confirmSelector;
  _alertCancelSelector = cancelSelector;
  _alertArgument = [argument retain];
  [_alertView show];
}

- (void) dismissAlert:(BOOL)animated {
  if (_alertView) {
    [_alertView dismissWithClickedButtonIndex:_alertView.cancelButtonIndex animated:animated];  // Doesn't call delegate on 4.2?
    if (_alertView) {
      [self _dismissAlertWithButtonIndex:_alertView.cancelButtonIndex];
    }
  }
}

@end

@implementation ApplicationDelegate (Spinner)

- (BOOL) isSpinnerVisible {
  return _spinnerView ? YES : NO;
}

- (void) showSpinnerWithMessage:(NSString*)message fullScreen:(BOOL)fullScreen animated:(BOOL)animated {
  CGRect frame;
  
  [self hideSpinner:NO];
  
  UIActivityIndicatorView* indicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
  indicator.frame = CGRectOffset(indicator.frame, kSpinnerBorderWidth, kSpinnerBorderWidth);
  indicator.hidesWhenStopped = NO;
  [indicator autorelease];
  CGSize size = indicator.frame.size;
  frame.size.width = size.width + 2.0 * kSpinnerBorderWidth;
  frame.size.height = size.height + 2.0 * kSpinnerBorderWidth;
  
  UILabel* label = nil;
  if (message) {
    label = [[UILabel alloc] init];
    label.backgroundColor = nil;
    label.opaque = NO;
    label.font = [UIFont boldSystemFontOfSize:(fullScreen ? kSpinnerFullscreenFontSize : kSpinnerFontSize)];
    label.textColor = [UIColor whiteColor];
    label.textAlignment = UITextAlignmentCenter;
    label.numberOfLines = 0;
    label.text = message;
    [label sizeToFit];
    [label autorelease];
    CGRect rect = label.frame;
    rect.origin.x = kSpinnerBorderWidth;
    rect.origin.y = frame.size.height - kSpinnerBorderWidth + (fullScreen ? kSpinnerFullscreenSpacing : kSpinnerSpacing);
    label.frame = rect;
    frame.size.width += rect.size.width - size.width;
    frame.size.height += rect.size.height + (fullScreen ? kSpinnerFullscreenSpacing : kSpinnerSpacing);
    CGRect temp = indicator.frame;
    temp.origin.x = roundf(temp.origin.x - temp.size.width / 2.0 + rect.size.width / 2.0);
    indicator.frame = temp;
  }

  CGRect bounds = _overlayWindow.bounds;
  frame.origin.x = roundf(bounds.size.width / 2.0 - frame.size.width / 2.0);
  frame.origin.y = roundf(bounds.size.height / 2.0 - frame.size.height / 2.0);
  UIView* spinnerView = [[UIView alloc] initWithFrame:frame];
  spinnerView.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin |
                                 UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
  [spinnerView addSubview:indicator];
  if (label) {
    [spinnerView addSubview:label];
  }
  if (fullScreen) {
    _spinnerView = [[UIView alloc] initWithFrame:bounds];
    _spinnerView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [_spinnerView addSubview:spinnerView];
    [spinnerView release];
  } else {
    _spinnerView = spinnerView;
    _spinnerView.layer.cornerRadius = 10.0;
  }
  _spinnerView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.75];
  [_overlayWindow addSubview:_spinnerView];
  _overlayWindow.hidden = NO;
  if (animated) {
    _spinnerView.alpha = 0.0;
    [UIView beginAnimations:nil context:NULL];
    [UIView setAnimationCurve:UIViewAnimationCurveEaseOut];
    [UIView setAnimationDuration:kSpinnerViewAnimationDuration];
    _spinnerView.alpha = 1.0;
    [UIView commitAnimations];
  }
  
  [indicator startAnimating];
}

- (void) _spinnerAnimationDidStop:(NSString*)animationID finished:(NSNumber*)finished context:(void*)context {
  [(UIView*)context removeFromSuperview];
  _overlayWindow.hidden = YES;
  [(UIView*)context release];
}

- (void) hideSpinner:(BOOL)animated {
  if (_spinnerView) {
    if (animated) {
      [UIView beginAnimations:nil context:[_spinnerView retain]];
      [UIView setAnimationDelegate:self];
      [UIView setAnimationDidStopSelector:@selector(_spinnerAnimationDidStop:finished:context:)];
      [UIView setAnimationCurve:UIViewAnimationCurveEaseIn];
      [UIView setAnimationDuration:kSpinnerViewAnimationDuration];
      _spinnerView.alpha = 0.0;
      [UIView commitAnimations];
    } else {
      [_spinnerView removeFromSuperview];
      _overlayWindow.hidden = YES;
    }
    [_spinnerView release];
    _spinnerView = nil;
  }
}

@end
