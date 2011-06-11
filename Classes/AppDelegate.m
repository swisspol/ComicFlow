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

#import "AppDelegate.h"
#import "Library.h"
#import "LibraryViewController.h"
#import "Defaults.h"
#import "Extensions_Foundation.h"
#import "Logging.h"

#define kUpdateDelay 5.0  // Seconds

@implementation AppDelegate

@synthesize davServer=_davServer;

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
    [[LibraryUpdater sharedUpdater] startUpdating:NO];
  }
}

- (BOOL) application:(UIApplication*)application didFinishLaunchingWithOptions:(NSDictionary*)launchOptions {
  [super application:application didFinishLaunchingWithOptions:launchOptions];
  _backgroundTask = UIBackgroundTaskInvalid;
  
  // Set TaskQueue concurrency
  [TaskQueue setDefaultConcurrency:2];
  
  // Initialize updater
  [[LibraryUpdater sharedUpdater] setDelegate:(LibraryViewController*)self.viewController];
  
  // Start WebDAV server if necessary
  if ([[NSUserDefaults standardUserDefaults] boolForKey:kDefaultKey_ServerEnabled]) {
    [self enableDAVServer];
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
    [[LibraryUpdater sharedUpdater] startUpdating:YES];
  } else {
    [[LibraryUpdater sharedUpdater] startUpdating:NO];
  }
  
  // Prepare window
  self.window.backgroundColor = nil;
  self.window.layer.contentsGravity = kCAGravityCenter;
  [(LibraryViewController*)self.viewController setWindow:self.window];
  
  // Show window
  [self.window addSubview:self.viewController.view];
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
      _needsUpdate = NO;
      [[AppDelegate sharedInstance] showAlertWithTitle:NSLocalizedString(@"INBOX_ALERT_TITLE", nil)
                                               message:[NSString stringWithFormat:NSLocalizedString(@"INBOX_ALERT_MESSAGE", nil), file]
                                                button:NSLocalizedString(@"INBOX_ALERT_BUTTON", nil)];
      return YES;
    }
  }
  return NO;
}

- (void) applicationDidEnterBackground:(UIApplication*)application {
  // Prevent WebDAV Server to accept new connections but keep current ones alive
  [_davServer stop:YES];
  
  // If there are any WebDAV connections alive, start background task
  if (_davServer.numberOfConnections) {
    _backgroundTask = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
      [[UIApplication sharedApplication] endBackgroundTask:_backgroundTask];
      _backgroundTask = UIBackgroundTaskInvalid;
      LOG_VERBOSE(@"Background task expired");
    }];
    LOG_VERBOSE(@"Background task started");
  }
  
  [super applicationDidEnterBackground:application];
}

- (void) applicationWillEnterForeground:(UIApplication*)application {
  [super applicationWillEnterForeground:application];
  
  // End background task if any
  if (_backgroundTask != UIBackgroundTaskInvalid) {
    [[UIApplication sharedApplication] endBackgroundTask:_backgroundTask];
    _backgroundTask = UIBackgroundTaskInvalid;
    LOG_VERBOSE(@"Background task stopped");
  }
  
  // Allow WebDAV server to accept new connections again
  [_davServer start];
  
  // Update library if it was updating when entering background or needs updating because of background task
  if (_needsUpdate) {
    [_updateTimer setFireDate:[NSDate dateWithTimeIntervalSinceNow:kUpdateDelay]];
    _needsUpdate = NO;
  }
}

- (void) applicationWillTerminate:(UIApplication*)application {
  // Stop WebDAV server
  [_davServer stop:NO];
  
  [super applicationWillTerminate:application];
}

- (void) saveState {
  [(LibraryViewController*)self.viewController saveState];
}

- (void) enableDAVServer {
  if (_davServer == nil) {
    NSString* documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
#ifdef NDEBUG
    NSString* password = [NSString stringWithFormat:@"%i", 100000 + random() % 899999];
#else
    NSString* password = nil;
#endif
    _davServer = [[DAVServer alloc] initWithRootDirectory:documentsPath port:8080 password:password];
    _davServer.delegate = self;
    [_davServer start];
    
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kDefaultKey_ServerEnabled];
  }
}

- (void) disableDAVServer {
  if (_davServer != nil) {
    _davServer.delegate = nil;
    [_davServer stop:NO];
    [_davServer release];
    _davServer = nil;
    
    if (_needsUpdate) {
      [_updateTimer setFireDate:[NSDate dateWithTimeIntervalSinceNow:kUpdateDelay]];
      _needsUpdate = NO;
    }
    _hasConnections = NO;
    
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:kDefaultKey_ServerEnabled];
  }
}

- (void) davServerDidUpdateNumberOfConnections:(DAVServer*)server {
  NSUInteger count = _davServer.numberOfConnections;
  if (count && !_hasConnections) {
    _hasConnections = YES;
    LOG_VERBOSE(@"WebDAV Server connected");
  } else if (!count && _hasConnections) {
    LOG_VERBOSE(@"WebDAV Server disconnected");
    if (_backgroundTask != UIBackgroundTaskInvalid) {
      [[UIApplication sharedApplication] endBackgroundTask:_backgroundTask];
      _backgroundTask = UIBackgroundTaskInvalid;
      LOG_VERBOSE(@"Background task stopped");
    }
    if (_needsUpdate && ([[UIApplication sharedApplication] applicationState] != UIApplicationStateBackground)) {
      [_updateTimer setFireDate:[NSDate dateWithTimeIntervalSinceNow:kUpdateDelay]];
      _needsUpdate = NO;
    }
    _hasConnections = NO;
  }
}

- (void) davServer:(DAVServer*)server didRespondToMethod:(NSString*)method {
  if ([method isEqualToString:@"PUT"] || [method isEqualToString:@"DELETE"] || [method isEqualToString:@"MOVE"] ||
    [method isEqualToString:@"COPY"] || [method isEqualToString:@"MKCOL"]) {
    _needsUpdate = YES;
  }
}

@end
