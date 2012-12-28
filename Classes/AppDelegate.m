//  This file is part of the ComicFlow application for iOS.
//  Copyright (C) 2010-2011 Pierre-Olivier Latour <info@pol-online.net>
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
#import "Logging.h"

#define kUpdateDelay 5.0  // Seconds

@implementation AppDelegate

@synthesize webServer=_webServer;

+ (void) initialize {
  // Setup initial user defaults
  NSMutableDictionary* defaults = [[NSMutableDictionary alloc] init];
  [defaults setObject:[NSNumber numberWithBool:YES] forKey:kDefaultKey_ServerEnabled];
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

- (void) awakeFromNib {
  // Reset library if necessary
  if ([[NSUserDefaults standardUserDefaults] boolForKey:@"resetLibrary"]) {
    LOG_INFO(@"Resetting library");
    [[NSFileManager defaultManager] removeItemAtPath:[LibraryConnection libraryApplicationDataPath] error:NULL];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kDefaultKey_RootTimestamp];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kDefaultKey_RootScrolling];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kDefaultKey_CurrentCollection];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kDefaultKey_CurrentComic];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kDefaultKey_SortingMode];
  }
  
  // Initialize library
  CHECK([LibraryConnection mainConnection]);
}

- (void) _update:(NSTimer*)timer {
  if ([[LibraryUpdater sharedUpdater] isUpdating]) {
    [_updateTimer setFireDate:[NSDate dateWithTimeIntervalSinceNow:kUpdateDelay]];
  } else {
    [[LibraryUpdater sharedUpdater] update:NO];
  }
}

- (BOOL) application:(UIApplication*)application didFinishLaunchingWithOptions:(NSDictionary*)launchOptions {
  [super application:application didFinishLaunchingWithOptions:launchOptions];
  
  // Start Flurry analytics
  [Flurry setAppVersion:[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"]];
  [Flurry startSession:@"2ZSSCCWQY2Z36J78MTTZ"];
  
  // Prevent backup of Documents directory as it contains only "offline data" (iOS 5.0.1 and later)
  NSString* documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
  u_int8_t value = 1;
  int result = setxattr([documentsPath fileSystemRepresentation], "com.apple.MobileBackup", &value, sizeof(value), 0, 0);
  if (result) {
    LOG_ERROR(@"Failed setting do-not-backup attribute on \"%@\": %s (%i)", documentsPath, strerror(result), result);
  }
  
  // Initialize updater
  [[LibraryUpdater sharedUpdater] setDelegate:(LibraryViewController*)self.viewController];
  
  // Start web server if necessary
  if ([[NSUserDefaults standardUserDefaults] boolForKey:kDefaultKey_ServerEnabled]) {
    [self enableWebServer];
  }
  
  // Initialize update timer
  _updateTimer = [[NSTimer alloc] initWithFireDate:[NSDate distantFuture]
                                          interval:HUGE_VAL
                                            target:self
                                          selector:@selector(_update:)
                                          userInfo:nil
                                           repeats:YES];
  [[NSRunLoop currentRunLoop] addTimer:_updateTimer forMode:NSRunLoopCommonModes];
  
  // Update library immediately
  if ([[LibraryConnection mainConnection] countObjectsOfClass:[Comic class]] == 0) {
    [[LibraryUpdater sharedUpdater] update:YES];
  } else {
    [[LibraryUpdater sharedUpdater] update:NO];
  }
  
  // Create root view controller
  self.viewController = [[[LibraryViewController alloc] initWithWindow:self.window] autorelease];
  
  // Show window
  self.window.backgroundColor = nil;
  self.window.layer.contentsGravity = kCAGravityCenter;
  self.window.rootViewController = self.viewController;
  [self.window makeKeyAndVisible];
  
  return YES;
}

- (BOOL) application:(UIApplication*)application
             openURL:(NSURL*)url
   sourceApplication:(NSString*)sourceApplication
          annotation:(id)annotation {
  LOG_VERBOSE(@"Opening \"%@\"", url);
  if ([url isFileURL]) {
    NSString* file = [[url path] lastPathComponent];
    NSString* destinationPath = [[LibraryConnection libraryRootPath] stringByAppendingPathComponent:file];
    if ([[NSFileManager defaultManager] moveItemAtPath:[url path] toPath:destinationPath error:NULL]) {
      [_updateTimer setFireDate:[NSDate dateWithTimeIntervalSinceNow:kUpdateDelay]];
      [[AppDelegate sharedInstance] showAlertWithTitle:NSLocalizedString(@"INBOX_ALERT_TITLE", nil)
                                               message:[NSString stringWithFormat:NSLocalizedString(@"INBOX_ALERT_MESSAGE", nil), file]
                                                button:NSLocalizedString(@"INBOX_ALERT_BUTTON", nil)];
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
    NSString* documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
    
    _webServer = [[WebServer alloc] init];
    [_webServer addHandlerForBasePath:@"/" localPath:documentsPath indexFilename:nil cacheAge:0];
    [_webServer startWithRunloop:[NSRunLoop mainRunLoop] port:8080 bonjourName:nil];
    
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kDefaultKey_ServerEnabled];
  }
}

- (void) disableWebServer {
  if (_webServer != nil) {
    [_webServer stop];
    [_webServer release];
    _webServer = nil;
    
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:kDefaultKey_ServerEnabled];
  }
}

@end
