// Copyright 2011 Cooliris, Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#import "UnRAR.h"
#import "raros.hpp"
#import "dll.hpp"

#import "Logging.h"

// http://www.rarlab.com/rar_add.htm
// http://goahomepage.free.fr/article/2000_09_17_unrar_dll/UnRARDLL.html

@implementation UnRAR

@synthesize skipInvisibleFiles=_skipInvisible;

+ (BOOL) extractRARArchiveAtPath:(NSString*)inPath toPath:(NSString*)outPath {
  BOOL success = NO;
  UnRAR* archive = [[UnRAR alloc] initWithArchiveAtPath:inPath];
  if (archive) {
    success = [archive extractToPath:outPath];
    [archive release];
  }
  return success;
}

- (id) initWithArchiveAtPath:(NSString*)path {
  if ((self = [super init])) {
    _archivePath = [path copy];
    
    struct RAROpenArchiveData archiveData;
    bzero(&archiveData, sizeof(archiveData));
    archiveData.ArcName = (char*)[_archivePath fileSystemRepresentation];
    archiveData.OpenMode = RAR_OM_LIST;
    HANDLE handle = RAROpenArchive(&archiveData);
    if (handle) {
      RARCloseArchive(handle);
    } else {
      [self release];
      return nil;
    }
  }
  return self;
}

- (void) dealloc {
  [_archivePath release];
  
  [super dealloc];
}

- (NSArray*) retrieveFileList {
  NSMutableArray* array = nil;
  
  // Open archive
  struct RAROpenArchiveData archiveData;
  bzero(&archiveData, sizeof(archiveData));
  archiveData.ArcName = (char*)[_archivePath fileSystemRepresentation];
  archiveData.OpenMode = RAR_OM_LIST;
  HANDLE handle = RAROpenArchive(&archiveData);
  if (handle) {
    array = [NSMutableArray array];
    
    // Scan archive
    while (1) {
      // Retrieve current file information
      struct RARHeaderData headerData;
      bzero(&headerData, sizeof(headerData));
      int result = RARReadHeader(handle, &headerData);
      if (result != 0) {
        if (result != ERAR_END_ARCHIVE) {
          LOG_ERROR(@"UnRAR returned error %i", result);
          array = nil;
        }
        break;
      }
      NSString* path = [NSString stringWithCString:headerData.FileName encoding:NSASCIIStringEncoding];  // TODO: Is this correct?
      
      // Add current file to list if necessary
      if (_skipInvisible) {
        for (NSString* string in [path pathComponents]) {
          if ([string hasPrefix:@"."]) {
            path = nil;
            break;
          }
        }
      }
      if (path && headerData.FileCRC) {
        [array addObject:path];
      }
      
      // Find next file
      result = RARProcessFile(handle, RAR_SKIP, NULL, NULL);
      if (result != 0) {
        LOG_ERROR(@"UnRAR returned error %i", result);
        array = nil;
        break;
      }
    }
    
    // Close archive
    RARCloseArchive(handle);
  } else {
    LOG_ERROR(@"UnRAR failed opening archive");
  }
  
  return array;
}

- (BOOL) extractToPath:(NSString*)outPath {
  BOOL success = NO;
  
  // Open archive
  struct RAROpenArchiveData archiveData;
  bzero(&archiveData, sizeof(archiveData));
  archiveData.ArcName = (char*)[_archivePath fileSystemRepresentation];
  archiveData.OpenMode = RAR_OM_EXTRACT;
  HANDLE handle = RAROpenArchive(&archiveData);
  if (handle) {
    const char* destination = [outPath fileSystemRepresentation];
    success = YES;
    
    // Scan archive
    while (1) {
      // Retrieve current file information
      struct RARHeaderData headerData;
      bzero(&headerData, sizeof(headerData));
      int result = RARReadHeader(handle, &headerData);
      if (result != 0) {
        if (result != ERAR_END_ARCHIVE) {
          LOG_ERROR(@"UnRAR returned error %i", result);
          success = NO;
        }
        break;
      }
      NSString* path = [NSString stringWithCString:headerData.FileName encoding:NSASCIIStringEncoding];  // TODO: Is this correct?
      
      // Add current file to list if necessary
      if (_skipInvisible) {
        for (NSString* string in [path pathComponents]) {
          if ([string hasPrefix:@"."]) {
            path = nil;
            break;
          }
        }
      }
      
      // Extract and find next file
      result = RARProcessFile(handle, path && headerData.FileCRC ? RAR_EXTRACT : RAR_SKIP, (char*)destination, NULL);
      if (result != 0) {
        LOG_ERROR(@"UnRAR returned error %i", result);
        success = NO;
        break;
      }
    }
    
    // Close archive
    RARCloseArchive(handle);
  } else {
    LOG_ERROR(@"UnRAR failed opening archive");
  }
  
  return success;
}

- (BOOL) extractFile:(NSString*)inPath toPath:(NSString*)outPath {
  BOOL success = NO;
  
  // Open archive
  struct RAROpenArchiveData archiveData;
  bzero(&archiveData, sizeof(archiveData));
  archiveData.ArcName = (char*)[_archivePath fileSystemRepresentation];
  archiveData.OpenMode = RAR_OM_EXTRACT;
  HANDLE handle = RAROpenArchive(&archiveData);
  if (handle) {
    
    // Scan archive
    while (1) {
      // Retrieve current file information
      struct RARHeaderData headerData;
      bzero(&headerData, sizeof(headerData));
      int result = RARReadHeader(handle, &headerData);
      if (result != 0) {
        if (result != ERAR_END_ARCHIVE) {
          LOG_ERROR(@"UnRAR returned error %i", result);
        }
        break;
      }
      NSString* path = [NSString stringWithCString:headerData.FileName encoding:NSASCIIStringEncoding];  // TODO: Is this correct?
      
      // Extract if necessary and find next file
      if (headerData.FileCRC && [path isEqualToString:inPath]) {
        result = RARProcessFile(handle, RAR_EXTRACT, NULL, (char*)[outPath fileSystemRepresentation]);
        if (result != 0) {
          LOG_ERROR(@"UnRAR returned error %i", result);
        } else {
          success = YES;
        }
        break;
      } else {
        result = RARProcessFile(handle, RAR_SKIP, NULL, NULL);
        if (result != 0) {
          LOG_ERROR(@"UnRAR returned error %i", result);
          break;
        }
      }
    }
    
    // Close archive
    RARCloseArchive(handle);
  } else {
    LOG_ERROR(@"UnRAR failed opening archive");
  }
  
  return success;
}

@end
