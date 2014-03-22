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

#import "AppDelegate.h"
#import "Library.h"
#import "Defaults.h"

#import "Logging.h"
#import "Extensions_Foundation.h"

static NSString* _serverName = nil;
static dispatch_queue_t _connectionQueue = NULL;
static NSInteger _connectionCount = 0;

@implementation WebServerConnection

- (void) open {
  [super open];
  
  dispatch_sync(_connectionQueue, ^{
    DCHECK(_connectionCount >= 0);
    if (_connectionCount == 0) {
      WebServer* server = (WebServer*)self.server;
      dispatch_async(dispatch_get_main_queue(), ^{
        [server.delegate webServerDidConnect:server];
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
      WebServer* server = (WebServer*)self.server;
      dispatch_async(dispatch_get_main_queue(), ^{
        [server.delegate webServerDidDisconnect:server];
      });
    }
  });
  
  [super close];
}

@end

@implementation WebServer

@synthesize delegate=_delegate;

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
  
  [self addGETHandlerForBasePath:@"/" directoryPath:websitePath indexFilename:nil cacheAge:3600 allowRangeRequests:NO];
  
  [self addHandlerForMethod:@"GET" path:@"/" requestClass:[GCDWebServerRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request) {
    
    // Called from GCD thread
    return [GCDWebServerResponse responseWithRedirect:[NSURL URLWithString:@"index.html" relativeToURL:request.URL] permanent:NO];
    
  }];
  [self addHandlerForMethod:@"GET" path:@"/index.html" requestClass:[GCDWebServerRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request) {
    
    // Called from GCD thread
    NSMutableDictionary* variables = [NSMutableDictionary dictionaryWithDictionary:baseVariables];
    [variables setObject:[NSString stringWithFormat:@"%i", kTrialMaxUploads] forKey:@"max"];
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
          
          dispatch_async(dispatch_get_main_queue(), ^{
            [_delegate webServerDidDownloadComic:self];
          });
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
    switch ([[NSUserDefaults standardUserDefaults] integerForKey:kDefaultKey_ServerMode]) {
      
      case kServerMode_Limited:
        [variables setObject:@"0" forKey:@"remaining"];
        break;
      
      case kServerMode_Trial:
        [variables setObject:[NSString stringWithFormat:@"%i", [[NSUserDefaults standardUserDefaults] integerForKey:kDefaultKey_UploadsRemaining]] forKey:@"remaining"];
        break;
      
      case kServerMode_Full:
        [variables setObject:@"hidden" forKey:@"class"];
        break;
      
    }
    return [GCDWebServerDataResponse responseWithHTMLTemplate:[websitePath stringByAppendingPathComponent:request.path] variables:variables];
    
  }];
  [self addHandlerForMethod:@"POST" path:@"/upload" requestClass:[GCDWebServerMultiPartFormRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest* request) {
    
    // Called from GCD thread
    if ([[NSUserDefaults standardUserDefaults] integerForKey:kDefaultKey_ServerMode] != kServerMode_Limited) {
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
              [_delegate webServerDidUploadComic:self];
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
    } else {
      return [GCDWebServerResponse responseWithStatusCode:402];
    }
    
  }];
  
#if TARGET_IPHONE_SIMULATOR
  if (![self startWithPort:8080 bonjourName:@""])
#else
  if (![self startWithPort:80 bonjourName:@""])
#endif
  {
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
