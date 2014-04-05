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
        [server.serverDelegate webServerDidConnect:server];
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
        [server.serverDelegate webServerDidDisconnect:server];
      });
    }
  });
  
  [super close];
}

@end

@implementation WebServer

@synthesize serverDelegate=_serverDelegate;

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

- (id) init {
  NSString* documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
  if ((self = [self initWithUploadDirectory:documentsPath])) {
    self.delegate = self;
    self.allowedFileExtensions = [NSArray arrayWithObjects:@"pdf", @"zip", @"cbz", @"rar", @"cbr", nil];
    self.title = NSLocalizedString(@"SERVER_TITLE", nil);
    self.prologue = [NSString stringWithFormat:NSLocalizedString(@"SERVER_CONTENT", nil), [self.allowedFileExtensions componentsJoinedByString:@", "]];
    if ([[NSUserDefaults standardUserDefaults] integerForKey:kDefaultKey_ServerMode] != kServerMode_Full) {
      self.prologue = [self.prologue stringByAppendingFormat:NSLocalizedString(@"SERVER_LIMITED_CONTENT", nil), kTrialMaxUploads];
    }
    self.footer = [NSString stringWithFormat:NSLocalizedString(@"SERVER_FOOTER_FORMAT", nil),
                                             [[UIDevice currentDevice] name],
                                             [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"]];
  }
  return self;
}

- (BOOL) shouldUploadFileAtPath:(NSString*)path withTemporaryFile:(NSString*)tempPath {
  if ([[NSUserDefaults standardUserDefaults] integerForKey:kDefaultKey_ServerMode] == kServerMode_Limited) {
    LOG_ERROR(@"Web Server is in limited mode");
    return NO;
  }
  return YES;
}

- (void) webUploader:(GCDWebUploader*)uploader didDownloadFileAtPath:(NSString*)path {
  [_serverDelegate webServerDidDownloadComic:self];
}

- (void) webUploader:(GCDWebUploader*)uploader didUploadFileAtPath:(NSString*)path {
  [_serverDelegate webServerDidUploadComic:self];
}

- (void) webUploader:(GCDWebUploader*)uploader didMoveItemFromPath:(NSString*)fromPath toPath:(NSString*)toPath {
  [_serverDelegate webServerDidUpdate:self];
}

- (void) webUploader:(GCDWebUploader*)uploader didDeleteItemAtPath:(NSString*)path {
  [_serverDelegate webServerDidUpdate:self];
}

- (void) webUploader:(GCDWebUploader*)uploader didCreateDirectoryAtPath:(NSString*)path {
  [_serverDelegate webServerDidUpdate:self];
}

@end
