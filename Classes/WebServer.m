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
#import "Defaults.h"

#import "Logging.h"

#define kDisconnectLatency 1.0

@implementation WebServer

@synthesize serverDelegate=_serverDelegate;

- (id) init {
  NSString* documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
  if ((self = [self initWithUploadDirectory:documentsPath])) {
    self.delegate = self;
    self.allowedFileExtensions = [NSArray arrayWithObjects:@"pdf", @"zip", @"cbz", @"rar", @"cbr", nil];
#if !__USE_WEBDAV_SERVER__
    self.title = NSLocalizedString(@"SERVER_TITLE", nil);
    self.prologue = [NSString stringWithFormat:NSLocalizedString(@"SERVER_CONTENT", nil), [self.allowedFileExtensions componentsJoinedByString:@", "]];
    if ([[NSUserDefaults standardUserDefaults] integerForKey:kDefaultKey_ServerMode] != kServerMode_Full) {
      self.prologue = [self.prologue stringByAppendingFormat:NSLocalizedString(@"SERVER_LIMITED_CONTENT", nil), kTrialMaxUploads];
    }
    self.footer = [NSString stringWithFormat:NSLocalizedString(@"SERVER_FOOTER_FORMAT", nil),
                                             [[UIDevice currentDevice] name],
                                             [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"]];
#endif
  }
  return self;
}

- (BOOL)startWithOptions:(NSDictionary*)options {
  NSMutableDictionary* newOptions = [NSMutableDictionary dictionaryWithDictionary:options];
  NSString* name = [NSString stringWithFormat:NSLocalizedString(@"SERVER_NAME_FORMAT", nil),
                    [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"],
                    [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"]];
  [newOptions setObject:name forKey:GCDWebServerOption_ServerName];
  [newOptions setObject:[NSNumber numberWithDouble:kDisconnectLatency] forKey:GCDWebServerOption_ConnectedStateCoalescingInterval];
  return [super startWithOptions:newOptions];
}

- (BOOL) shouldUploadFileAtPath:(NSString*)path withTemporaryFile:(NSString*)tempPath {
  if ([[NSUserDefaults standardUserDefaults] integerForKey:kDefaultKey_ServerMode] == kServerMode_Limited) {
    LOG_ERROR(@"Upload rejected: web server is in limited mode");
    return NO;
  }
  return YES;
}

- (void) webServerDidConnect:(GCDWebServer*)server {
  [_serverDelegate webServerDidConnect:self];
}

#if __USE_WEBDAV_SERVER__

- (void) davServer:(GCDWebDAVServer*)server didDownloadFileAtPath:(NSString*)path {
  [_serverDelegate webServerDidDownloadComic:self];
}

- (void) davServer:(GCDWebDAVServer*)server didUploadFileAtPath:(NSString*)path {
  [_serverDelegate webServerDidUploadComic:self];
}

- (void) davServer:(GCDWebDAVServer*)server didMoveItemFromPath:(NSString*)fromPath toPath:(NSString*)toPath {
  [_serverDelegate webServerDidUpdate:self];
}

- (void) davServer:(GCDWebDAVServer*)server didCopyItemFromPath:(NSString*)fromPath toPath:(NSString*)toPath {
  [_serverDelegate webServerDidUpdate:self];
}

- (void) davServer:(GCDWebDAVServer*)server didDeleteItemAtPath:(NSString*)path {
  [_serverDelegate webServerDidUpdate:self];
}

- (void) davServer:(GCDWebDAVServer*)server didCreateDirectoryAtPath:(NSString*)path {
  [_serverDelegate webServerDidUpdate:self];
}

#else

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

#endif

- (void) webServerDidDisconnect:(GCDWebServer*)server {
  [_serverDelegate webServerDidDisconnect:self];
}

@end
