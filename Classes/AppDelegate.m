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
#import "Extensions_UIKit.h"
#import "Logging.h"

#define kUpdateDelay 1.0
#define kNetworkingLatency 1.0
#define kScreenDimmingOpacity 0.5

@interface AppDelegate ()
- (void) setNeedsUpdate;
- (void) serverWillBegin;
- (void) serverDidEnd;
@end

@interface WebServerConnection : GCDWebServerConnection
@end

static NSString* _serverName = nil;
static dispatch_queue_t _connectionQueue = NULL;
static NSInteger _connectionCount = 0;

@implementation WebServerConnection

- (void) open {
  [super open];
  
  dispatch_sync(_connectionQueue, ^{
    DCHECK(_connectionCount >= 0);
    if (_connectionCount == 0) {
      dispatch_async(dispatch_get_main_queue(), ^{
        
        @autoreleasepool {
          [(AppDelegate*)[[UIApplication sharedApplication] delegate] serverWillBegin];
        }
        
      });
    }
    _connectionCount += 1;
  });
}

- (void) close {
  dispatch_sync(_connectionQueue, ^{
    DCHECK(_connectionCount > 0);
    _connectionCount -= 1;
    if (_connectionCount == 0) {
      dispatch_async(dispatch_get_main_queue(), ^{
        
        @autoreleasepool {
          [(AppDelegate*)[[UIApplication sharedApplication] delegate] serverDidEnd];
        }
        
      });
    }
  });
  
  [super close];
}

@end

@implementation WebServer

+ (void) initialize {
  if (_serverName == nil) {
    _serverName = [[NSString alloc] initWithFormat:NSLocalizedString(@"SERVER_NAME_FORMAT", nil),
                                                   [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"],
                                                   [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"]];
  }
  if (_connectionQueue == NULL) {
    _connectionQueue = dispatch_queue_create(NULL, DISPATCH_QUEUE_SERIAL);
  }
}

+ (Class) connectionClass {
  return [WebServerConnection class];
}

+ (NSString*) serverName {
  return _serverName;
}

- (BOOL) start {
  NSSet* allowedFileExtensions = [NSSet setWithObjects:@"pdf", @"zip", @"cbz", @"rar", @"cbr", nil];
  NSString* websitePath = [[NSBundle mainBundle] pathForResource:@"Website" ofType:nil];
  NSString* footer = [NSString stringWithFormat:NSLocalizedString(@"SERVER_FOOTER_FORMAT", nil),
                                                [[UIDevice currentDevice] name],
                                                [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"]];
  NSDictionary* baseVariables = [NSDictionary dictionaryWithObjectsAndKeys:footer, @"footer", nil];
  
  [self addHandlerForBasePath:@"/" localPath:websitePath indexFilename:nil cacheAge:3600];
  
  [self addHandlerForMethod:@"GET" path:@"/" requestClass:[GCDWebServerRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request) {
    
    // Called from GCD thread
    return [GCDWebServerResponse responseWithRedirect:[NSURL URLWithString:@"index.html" relativeToURL:request.URL] permanent:NO];
    
  }];
  [self addHandlerForMethod:@"GET" path:@"/index.html" requestClass:[GCDWebServerRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request) {
    
    // Called from GCD thread
    NSMutableDictionary* variables = [NSMutableDictionary dictionaryWithDictionary:baseVariables];
    return [GCDWebServerDataResponse responseWithHTMLTemplate:[websitePath stringByAppendingPathComponent:request.path] variables:variables];
    
  }];
  
  [self addHandlerForMethod:@"GET" path:@"/download.html" requestClass:[GCDWebServerRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request) {
    
    // Called from GCD thread
    GCDWebServerResponse* response = nil;
    LibraryConnection* connection = [[LibraryConnection alloc] initWithDatabaseAtPath:[LibraryConnection libraryDatabasePath] readWrite:NO];
    if (connection) {
      NSMutableDictionary* variables = [NSMutableDictionary dictionaryWithDictionary:baseVariables];
      
      NSMutableString* content = [[NSMutableString alloc] init];
      NSString* statement = @"SELECT collections.name AS collection, comics.name AS name, comics._id_ AS id FROM comics \
                              LEFT JOIN collections ON comics.collection=collections._id_ \
                              ORDER BY collection ASC, name ASC";
      for (NSDictionary* row in [connection executeRawSQLStatement:statement usingRowClass:[NSMutableDictionary class] primaryKey:nil]) {
        NSString* collection = [row objectForKey:@"collection"];
        [content appendFormat:@"<tr><td>%@</td><td><a href=\"download?id=%@\">%@</a></td></tr>", collection ? collection : @"", [row objectForKey:@"id"], [row objectForKey:@"name"]];
      }
      [variables setObject:content forKey:@"content"];
      [content release];
      
      response = [GCDWebServerDataResponse responseWithHTMLTemplate:[websitePath stringByAppendingPathComponent:request.path] variables:variables];
      [connection release];
    }
    return response;
    
  }];
  [self addHandlerForMethod:@"GET" path:@"/download" requestClass:[GCDWebServerRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request) {
    
    // Called from GCD thread
    GCDWebServerResponse* response = nil;
    DatabaseSQLRowID rowID = [[request.query objectForKey:@"id"] integerValue];
    if (rowID) {
      LibraryConnection* connection = [[LibraryConnection alloc] initWithDatabaseAtPath:[LibraryConnection libraryDatabasePath] readWrite:NO];
      if (connection) {
        Comic* comic = [connection fetchObjectOfClass:[Comic class] withSQLRowID:rowID];
        NSString* path = comic ? [connection pathForComic:comic] : nil;
        if (path) {
          response = [GCDWebServerFileResponse responseWithFile:path isAttachment:YES];
        } else {
          response = [GCDWebServerResponse responseWithStatusCode:404];
        }
        [connection release];
      }
    }
    return response;
    
  }];
  
  [self addHandlerForMethod:@"GET" path:@"/upload.html" requestClass:[GCDWebServerRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request) {
    
    // Called from GCD thread
    NSMutableDictionary* variables = [NSMutableDictionary dictionaryWithDictionary:baseVariables];
    return [GCDWebServerDataResponse responseWithHTMLTemplate:[websitePath stringByAppendingPathComponent:request.path] variables:variables];
    
  }];
  [self addHandlerForMethod:@"POST" path:@"/upload" requestClass:[GCDWebServerMultiPartFormRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request) {
    
    // Called from GCD thread
    NSString* html = NSLocalizedString(@"SERVER_STATUS_SUCCESS", nil);
    GCDWebServerMultiPartFile* file = [[(GCDWebServerMultiPartFormRequest*)request files] objectForKey:@"file"];
    NSString* fileName = file.fileName;
    NSString* temporaryPath = file.temporaryPath;
    GCDWebServerMultiPartArgument* collection = [[(GCDWebServerMultiPartFormRequest*)request arguments] objectForKey:@"collection"];
    NSString* collectionName = [collection string];
    if (fileName.length && ![fileName hasPrefix:@"."]) {
      NSString* extension = [[fileName pathExtension] lowercaseString];
      if (extension && [allowedFileExtensions containsObject:extension]) {
        
        NSString* directoryPath = [LibraryConnection libraryRootPath];
        if (collectionName.length) {
          for (NSString* directory in [[NSFileManager defaultManager] directoriesInDirectoryAtPath:directoryPath includeInvisible:NO]) {
            if ([directory caseInsensitiveCompare:collectionName] == NSOrderedSame) {
              collectionName = directory;
              break;
            }
          }
          directoryPath = [directoryPath stringByAppendingPathComponent:collectionName];
          [[NSFileManager defaultManager] createDirectoryAtPath:directoryPath withIntermediateDirectories:NO attributes:nil error:NULL];
        }
        
        for (NSString* file in [[NSFileManager defaultManager] filesInDirectoryAtPath:directoryPath includeInvisible:NO includeSymlinks:NO]) {
          if ([file caseInsensitiveCompare:fileName] == NSOrderedSame) {
            fileName = file;
            break;
          }
        }
        NSString* filePath = [directoryPath stringByAppendingPathComponent:fileName];
        [[NSFileManager defaultManager] removeItemAtPath:filePath error:NULL];
        
        NSError* error = nil;
        if ([[NSFileManager defaultManager] moveItemAtPath:temporaryPath toPath:filePath error:&error]) {
          LOG_VERBOSE(@"Uploaded comic file \"%@\" in collection \"%@\"", fileName, collectionName);
          
          dispatch_async(dispatch_get_main_queue(), ^{
            [(AppDelegate*)[[UIApplication sharedApplication] delegate] setNeedsUpdate];
          });
        } else {
          LOG_ERROR(@"Failed adding uploaded comic file \"%@\": %@", fileName, error);
          html = NSLocalizedString(@"SERVER_STATUS_ERROR", nil);
        }
        
      } else {
        LOG_WARNING(@"Ignoring uploaded comic file \"%@\" with unsupported type", fileName);
        html = NSLocalizedString(@"SERVER_STATUS_UNSUPPORTED", nil);
      }
    } else {
      LOG_WARNING(@"Ignoring uploaded comic file without name");
      html = NSLocalizedString(@"SERVER_STATUS_INVALID", nil);
    }
    return [GCDWebServerDataResponse responseWithHTML:html];
    
  }];
  
  if (![self startWithRunloop:[NSRunLoop mainRunLoop] port:8080 bonjourName:nil]) {
    [self removeAllHandlers];
    return NO;
  }
  
  return YES;
}

- (void) stop {
  [super stop];
  
  [self removeAllHandlers];  // Required to break release cycles (since handler blocks can hold references to server)
}

@end

@implementation AppDelegate

@synthesize webServer=_webServer;

+ (void) initialize {
  // Setup initial user defaults
  NSMutableDictionary* defaults = [[NSMutableDictionary alloc] init];
  [defaults setObject:[NSNumber numberWithBool:NO] forKey:kDefaultKey_ScreenDimmed];
  [defaults setObject:[NSNumber numberWithBool:NO] forKey:kDefaultKey_ServerEnabled];
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

- (void) setNeedsUpdate {
  _needsUpdate = YES;
}

- (void) serverWillBegin {
  _serverActive = YES;
  
  if (_networking == NO) {
    [[UIApplication sharedApplication] setIdleTimerDisabled:YES];
    [[UIApplication sharedApplication] showNetworkActivityIndicator];
    _networking = YES;
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
