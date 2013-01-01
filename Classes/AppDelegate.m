//  This file is part of the ComicFlow application for iOS.
//  Copyright (C) 2010-2013 Pierre-Olivier Latour <info@pol-online.net>
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

#import <QuartzCore/QuartzCore.h>
#import <sys/xattr.h>

#import "Flurry.h"

#import "AppDelegate.h"
#import "Library.h"
#import "LibraryViewController.h"
#import "Defaults.h"
#import "Extensions_Foundation.h"
#import "Extensions_UIKit.h"
#import "Logging.h"
#import "NetReachability.h"

#define kUpdateDelay 1.0
#define kNetworkingLatency 1.0
#define kScreenDimmingOpacity 0.5

@implementation AppDelegate (StoreKit)

- (void) _initializeStoreKit {
  [[SKPaymentQueue defaultQueue] addTransactionObserver:self];
  
  // TODO: Should we automatically call -restoreCompletedTransactions on new installs or backup restores? It seems the user can purchase again without being charged twice anyway.
  // [[SKPaymentQueue defaultQueue] restoreCompletedTransactions];
}

- (void) _startPurchase {
  _purchasing = YES;
  [self showSpinnerWithMessage:NSLocalizedString(@"PURCHASE_SPINNER", nil) fullScreen:YES animated:YES];
  self.window.userInteractionEnabled = NO;
}

- (void) _finishPurchase {
  DCHECK(_purchasing);
  self.window.userInteractionEnabled = YES;
  [self hideSpinner:YES];
  _purchasing = NO;
}

- (void) purchase {
  DCHECK([[NSUserDefaults standardUserDefaults] integerForKey:kDefaultKey_ServerMode] != kServerMode_Full);
  if (![[NetReachability sharedNetReachability] state]) {
    [self showAlertWithTitle:NSLocalizedString(@"OFFLINE_ALERT_TITLE", nil) message:NSLocalizedString(@"OFFLINE_ALERT_MESSAGE", nil) button:NSLocalizedString(@"OFFLINE_ALERT_BUTTON", nil)];
    return;
  }
  if (![SKPaymentQueue canMakePayments]) {
    [self showAlertWithTitle:NSLocalizedString(@"DISABLED_ALERT_TITLE", nil) message:NSLocalizedString(@"DISABLED_ALERT_MESSAGE", nil) button:NSLocalizedString(@"DISABLED_ALERT_BUTTON", nil)];
    return;
  }
  if (_purchasing || [[[SKPaymentQueue defaultQueue] transactions] count]) {
    [self showAlertWithTitle:NSLocalizedString(@"BUSY_ALERT_TITLE", nil) message:NSLocalizedString(@"BUSY_ALERT_MESSAGE", nil) button:NSLocalizedString(@"BUSY_ALERT_BUTTON", nil)];
    return;
  }
  SKProductsRequest* request = [[SKProductsRequest alloc] initWithProductIdentifiers:[NSSet setWithObject:kStoreKitProductIdentifier]];
  request.delegate = self;
  [request start];
  [self _startPurchase];
}

- (void) request:(SKRequest*)request didFailWithError:(NSError*)error {
  LOG_ERROR(@"App Store request failed: %@", error);
  [self showAlertWithTitle:NSLocalizedString(@"FAILED_ALERT_TITLE", nil) message:NSLocalizedString(@"FAILED_ALERT_MESSAGE", nil) button:NSLocalizedString(@"FAILED_ALERT_BUTTON", nil)];
  [self _finishPurchase];
}

- (void) productsRequest:(SKProductsRequest*)request didReceiveResponse:(SKProductsResponse*)response {
  SKProduct* product = [response.products firstObject];
  if (product) {
    SKPayment* payment = [SKPayment paymentWithProduct:product];
    [[SKPaymentQueue defaultQueue] addPayment:payment];
  } else {
    LOG_WARNING(@"Invalid App Store products: %@", response.invalidProductIdentifiers);
    [self showAlertWithTitle:NSLocalizedString(@"FAILED_ALERT_TITLE", nil) message:NSLocalizedString(@"FAILED_ALERT_MESSAGE", nil) button:NSLocalizedString(@"FAILED_ALERT_BUTTON", nil)];
    [self _finishPurchase];
  }
}

// This can be called in response to a purchase request or on app cold launch if there are unfinished transactions still pending
- (void) paymentQueue:(SKPaymentQueue*)queue updatedTransactions:(NSArray*)transactions {
  LOG_VERBOSE(@"%i App Store transactions updated", transactions.count);
  for (SKPaymentTransaction* transaction in transactions) {
    NSString* productIdentifier = transaction.payment.productIdentifier;
    DCHECK(productIdentifier);
    switch (transaction.transactionState) {
      
      case SKPaymentTransactionStatePurchasing:
        [self logEvent:@"iap.purchasing" withParameterName:@"product" value:productIdentifier];
        break;
      
      case SKPaymentTransactionStatePurchased:
      case SKPaymentTransactionStateRestored: {
        LOG_VERBOSE(@"Processing App Store transaction '%@' from %@", transaction.transactionIdentifier, transaction.transactionDate);
        if ([productIdentifier isEqualToString:kStoreKitProductIdentifier]) {
          NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
          [defaults setInteger:kServerMode_Full forKey:kDefaultKey_ServerMode];
          [defaults removeObjectForKey:kDefaultKey_UploadsRemaining];
          [defaults synchronize];
        } else {
          LOG_ERROR(@"Unexpected App Store product \"%@\"", productIdentifier);
          DNOT_REACHED();
        }
        [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
        if (transaction.transactionState == SKPaymentTransactionStatePurchased) {
          [(LibraryViewController*)self.viewController updatePurchase];
          [self showAlertWithTitle:NSLocalizedString(@"COMPLETE_ALERT_TITLE", nil) message:NSLocalizedString(@"COMPLETE_ALERT_MESSAGE", nil) button:NSLocalizedString(@"COMPLETE_ALERT_BUTTON", nil)];
          [self _finishPurchase];
          [self logEvent:@"iap.purchased" withParameterName:@"product" value:productIdentifier];
        } else {
          DCHECK(_purchasing == NO);
          [self logEvent:@"iap.restored" withParameterName:@"product" value:productIdentifier];
        }
        break;
      }
      
      case SKPaymentTransactionStateFailed: {
        NSError* error = transaction.error;
        if ([error.domain isEqualToString:SKErrorDomain] && (error.code == SKErrorPaymentCancelled)) {
          LOG_INFO(@"App Store transaction cancelled");
          [self logEvent:@"iap.cancelled" withParameterName:@"product" value:productIdentifier];
        } else {
          LOG_ERROR(@"App Store transaction failed: %@", error);
          [self showAlertWithTitle:NSLocalizedString(@"FAILED_ALERT_TITLE", nil) message:NSLocalizedString(@"FAILED_ALERT_MESSAGE", nil) button:NSLocalizedString(@"FAILED_ALERT_BUTTON", nil)];
          [self logEvent:@"iap.failed" withParameterName:@"product" value:productIdentifier];
        }
        [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
        if (_purchasing) {
          [self _finishPurchase];
        }
        break;
      }
      
    }
  }
}

@end

@implementation AppDelegate

@synthesize webServer=_webServer;

+ (void) initialize {
  // Setup initial user defaults
  NSMutableDictionary* defaults = [[NSMutableDictionary alloc] init];
  [defaults setObject:[NSNumber numberWithBool:NO] forKey:kDefaultKey_ServerEnabled];
  [defaults setObject:[NSNumber numberWithInteger:kServerMode_Trial] forKey:kDefaultKey_ServerMode];
  [defaults setObject:[NSNumber numberWithInteger:kTrialMaxUploads] forKey:kDefaultKey_UploadsRemaining];
  [defaults setObject:[NSNumber numberWithBool:NO] forKey:kDefaultKey_ScreenDimmed];
  [defaults setObject:[NSNumber numberWithDouble:0.0] forKey:kDefaultKey_RootTimestamp];
  [defaults setObject:[NSNumber numberWithInteger:0] forKey:kDefaultKey_RootScrolling];
  [defaults setObject:[NSNumber numberWithInteger:0] forKey:kDefaultKey_CurrentCollection];
  [defaults setObject:[NSNumber numberWithInteger:0] forKey:kDefaultKey_CurrentComic];
  [defaults setObject:[NSNumber numberWithInteger:kSortingMode_ByStatus] forKey:kDefaultKey_SortingMode];
  [[NSUserDefaults standardUserDefaults] registerDefaults:defaults];
  [defaults release];
  
  // Seed random generator
  srandomdev();
}

+ (AppDelegate*) sharedDelegate {
  return (AppDelegate*)[[UIApplication sharedApplication] delegate];
}

- (void) awakeFromNib {
  // Initialize library
  CHECK([LibraryConnection mainConnection]);
}

- (void) _updateTimer:(NSTimer*)timer {
  if ([[LibraryUpdater sharedUpdater] isUpdating]) {
    [_updateTimer setFireDate:[NSDate dateWithTimeIntervalSinceNow:kUpdateDelay]];
  } else {
    [[LibraryUpdater sharedUpdater] update:NO];
  }
}

- (void) updateLibrary {
  [self _updateTimer:nil];
}

- (BOOL) application:(UIApplication*)application didFinishLaunchingWithOptions:(NSDictionary*)launchOptions {
  [super application:application didFinishLaunchingWithOptions:launchOptions];
  
#if defined(NDEBUG) && !TARGET_IPHONE_SIMULATOR
  // Start Flurry analytics
  [Flurry setAppVersion:[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"]];
  [Flurry startSession:@"2ZSSCCWQY2Z36J78MTTZ"];
#endif
  
  // Prevent backup of Documents directory as it contains only "offline data" (iOS 5.0.1 and later)
  NSString* documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
  u_int8_t value = 1;
  int result = setxattr([documentsPath fileSystemRepresentation], "com.apple.MobileBackup", &value, sizeof(value), 0, 0);
  if (result) {
    LOG_ERROR(@"Failed setting do-not-backup attribute on \"%@\": %s (%i)", documentsPath, strerror(result), result);
  }
  
  // Create root view controller
  self.viewController = [[[LibraryViewController alloc] initWithWindow:self.window] autorelease];
  
  // Initialize updater
  [[LibraryUpdater sharedUpdater] setDelegate:(LibraryViewController*)self.viewController];
  
  // Update library immediately
  if ([[LibraryConnection mainConnection] countObjectsOfClass:[Comic class]] == 0) {
    [[LibraryUpdater sharedUpdater] update:YES];
  } else {
    [[LibraryUpdater sharedUpdater] update:NO];
  }
  
  // Initialize update timer
  _updateTimer = [[NSTimer alloc] initWithFireDate:[NSDate distantFuture]
                                          interval:HUGE_VAL
                                            target:self
                                          selector:@selector(_updateTimer:)
                                          userInfo:nil
                                           repeats:YES];
  [[NSRunLoop currentRunLoop] addTimer:_updateTimer forMode:NSRunLoopCommonModes];
  
  // Start web server if necessary
  if ([[NSUserDefaults standardUserDefaults] boolForKey:kDefaultKey_ServerEnabled]) {
    [self enableWebServer];
  }
  
  // Show window
  self.window.backgroundColor = nil;
  self.window.layer.contentsGravity = kCAGravityCenter;
  self.window.rootViewController = self.viewController;
  [self.window makeKeyAndVisible];
  
  // Initialize dimming window
  _dimmingWindow = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
  _dimmingWindow.userInteractionEnabled = NO;
  _dimmingWindow.windowLevel = UIWindowLevelStatusBar;
  _dimmingWindow.backgroundColor = [UIColor blackColor];
  _dimmingWindow.alpha = 0.0;
  _dimmingWindow.hidden = YES;
  if ([[NSUserDefaults standardUserDefaults] boolForKey:kDefaultKey_ScreenDimmed]) {
    [self setScreenDimmed:YES];
  }
  
  // Initialize StoreKit
  [self _initializeStoreKit];
  
  return YES;
}

- (BOOL) application:(UIApplication*)application openURL:(NSURL*)url sourceApplication:(NSString*)sourceApplication annotation:(id)annotation {
  LOG_VERBOSE(@"Opening \"%@\"", url);
  if ([url isFileURL]) {
    NSString* file = [[url path] lastPathComponent];
    NSString* destinationPath = [[LibraryConnection libraryRootPath] stringByAppendingPathComponent:file];
    if ([[NSFileManager defaultManager] moveItemAtPath:[url path] toPath:destinationPath error:NULL]) {
      [_updateTimer setFireDate:[NSDate dateWithTimeIntervalSinceNow:kUpdateDelay]];
      [[AppDelegate sharedInstance] showAlertWithTitle:NSLocalizedString(@"INBOX_ALERT_TITLE", nil)
                                               message:[NSString stringWithFormat:NSLocalizedString(@"INBOX_ALERT_MESSAGE", nil), file]
                                                button:NSLocalizedString(@"INBOX_ALERT_BUTTON", nil)];
      [self logEvent:@"app.open"];
      return YES;
    }
  }
  return NO;
}

- (void) applicationWillTerminate:(UIApplication*)application {
  // Stop web server
  [_webServer stop];
  
  [super applicationWillTerminate:application];
}

- (void) saveState {
  [(LibraryViewController*)self.viewController saveState];
}

- (void) enableWebServer {
  if (_webServer == nil) {
    _webServer = [[WebServer alloc] init];
    [_webServer start];
    
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kDefaultKey_ServerEnabled];
  }
}

- (void) serverDidStart {
  _serverActive = YES;
  
  if (_networking == NO) {
    [[UIApplication sharedApplication] setIdleTimerDisabled:YES];
    [[UIApplication sharedApplication] showNetworkActivityIndicator];
    _networking = YES;
  }
}

- (void) serverDidUpdate {
  _needsUpdate = YES;
  
  NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
  if ([defaults integerForKey:kDefaultKey_ServerMode] == kServerMode_Trial) {
    NSUInteger count = [defaults integerForKey:kDefaultKey_UploadsRemaining];
    count = count - 1;
    if (count > 0) {
      LOG_VERBOSE(@"Web Server trial has %i uploads left", count);
      [defaults setInteger:count forKey:kDefaultKey_UploadsRemaining];
    } else {
      [defaults setInteger:kServerMode_Limited forKey:kDefaultKey_ServerMode];
      [defaults removeObjectForKey:kDefaultKey_UploadsRemaining];
      LOG_VERBOSE(@"Web Server trial has ended");
    }
    [defaults synchronize];
  }
}

- (void) _serverDidEnd {
  if (_serverActive == NO) {
    if (_networking == YES) {
      [[UIApplication sharedApplication] hideNetworkActivityIndicator];
      [[UIApplication sharedApplication] setIdleTimerDisabled:NO];
      _networking = NO;
      
      if (_needsUpdate) {
        [self _updateTimer:nil];
        _needsUpdate = NO;
      }
    }
  }
}

- (void) serverDidEnd {
  _serverActive = NO;
  
  [self performSelector:@selector(_serverDidEnd) withObject:nil afterDelay:kNetworkingLatency];
}

- (void) disableWebServer {
  if (_webServer != nil) {
    [_webServer stop];
    [_webServer release];
    _webServer = nil;
    
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:kDefaultKey_ServerEnabled];
  }
}

- (BOOL) isScreenDimmed {
  return [[NSUserDefaults standardUserDefaults] boolForKey:kDefaultKey_ScreenDimmed];
}

- (void) setScreenDimmed:(BOOL)flag {
  if (flag) {
    _dimmingWindow.hidden = NO;
  }
  [UIView animateWithDuration:(1.0 / 3.0) animations:^{
    _dimmingWindow.alpha = flag ? kScreenDimmingOpacity : 0.0;
  } completion:^(BOOL finished) {
    if (!flag) {
      _dimmingWindow.hidden = YES;
    }
  }];
  [[NSUserDefaults standardUserDefaults] setBool:flag forKey:kDefaultKey_ScreenDimmed];
}

@end

@implementation AppDelegate (Events)

- (void) logEvent:(NSString*)event {
  [self logEvent:event withParameterName:nil value:nil];
}

- (void) logEvent:(NSString*)event withParameterName:(NSString*)name value:(NSString*)value {
  if (name && value) {
    LOG_VERBOSE(@"<EVENT> %@ ('%@' = '%@')", event, name, value);
    [Flurry logEvent:event withParameters:[NSDictionary dictionaryWithObject:value forKey:name]];
  } else {
    LOG_VERBOSE(@"<EVENT> %@", event);
    [Flurry logEvent:event];
  }
}

- (void) logPageView {
  LOG_VERBOSE(@"<PAGE VIEW>");
  [Flurry logPageView];
}

@end
