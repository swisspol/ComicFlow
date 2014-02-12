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

#import <StoreKit/StoreKit.h>

#import "ApplicationDelegate.h"
#import "WebServer.h"

#define kStoreKitProductIdentifier @"web_uploader"
#ifdef NDEBUG
#define kTrialMaxUploads 50
#else
#define kTrialMaxUploads 5
#endif

@interface AppDelegate : ApplicationDelegate {
  NSTimer* _updateTimer;
  BOOL _needsUpdate;
  WebServer* _webServer;
  BOOL _serverConnected;
  BOOL _serverActive;
  UIBackgroundTaskIdentifier _backgroundTask;
  UIWindow* _dimmingWindow;
  BOOL _purchasing;
}
@property(nonatomic, getter=isScreenDimmed) BOOL screenDimmed;
+ (AppDelegate*) sharedDelegate;
- (void) updateLibrary;
@end

@interface AppDelegate (WebServer) <WebServerDelegate>
@property(nonatomic, readonly) WebServer* webServer;
- (void) enableWebServer;
- (void) disableWebServer;
@end

@interface AppDelegate (StoreKit) <SKPaymentTransactionObserver, SKProductsRequestDelegate>
- (void) purchase;
- (void) restore;
@end

@interface AppDelegate (Events)
- (void) logEvent:(NSString*)event;
- (void) logEvent:(NSString*)event withParameterName:(NSString*)name value:(NSString*)value;
- (void) logPageView;
@end
