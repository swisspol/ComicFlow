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

#import "MiniZip.h"
#import "unzip.h"

#import "Logging.h"

#define kZipExtractionBufferSize 4096

@implementation MiniZip

@synthesize skipInvisibleFiles=_skipInvisible;

+ (BOOL) extractZipArchiveAtPath:(NSString*)inPath toPath:(NSString*)outPath {
  BOOL success = NO;
  MiniZip* archive = [[MiniZip alloc] initWithArchiveAtPath:inPath];
  if (archive) {
    success = [archive extractToPath:outPath];
    [archive release];
  }
  return success;
}

+ (BOOL) extractZipArchiveData:(NSData*)inData toPath:(NSString*)outPath {
  BOOL success = NO;
  MiniZip* archive = [[MiniZip alloc] initWithArchiveData:inData];
  if (archive) {
    success = [archive extractToPath:outPath];
    [archive release];
  }
  return success;
}

- (id) initWithUnzFile:(unzFile)file {
  if (file == NULL) {
    [self release];
    return nil;
  }
  if ((self = [super init])) {
    _unzFile = file;
  }
  return self;
}

- (void) dealloc {
  if (_unzFile) {
    unzClose(_unzFile);
  }
  [_data release];
  
  [super dealloc];
}

- (id) initWithArchiveAtPath:(NSString*)path {
  return [self initWithUnzFile:unzOpen([path UTF8String])];
}

static voidpf _OpenFunction(voidpf opaque, const char* filename, int mode) {
  return opaque;  // This becomes the "stream" argument for the other callbacks
}

static uLong _ReadFunction(voidpf opaque, voidpf stream, void* buf, uLong size) {
  MiniZip* zip = (MiniZip*)opaque;
  const void* bytes = zip->_data.bytes;
  long length = zip->_data.length;
  size = MIN(size, length - zip->_offset);
  if (size) {
    bcopy((char*)bytes + zip->_offset, buf, size);
    zip->_offset += size;
  }
  return size;
}

static long _TellFuntion(voidpf opaque, voidpf stream) {
  MiniZip* zip = (MiniZip*)opaque;
  return zip->_offset;
}

static long _SeekFunction(voidpf opaque, voidpf stream, uLong offset, int origin) {
  MiniZip* zip = (MiniZip*)opaque;
  long length = zip->_data.length;
  switch (origin) {
    
    case ZLIB_FILEFUNC_SEEK_CUR:
      zip->_offset += offset;
      break;
    
    case ZLIB_FILEFUNC_SEEK_END:
      zip->_offset = length + offset;
      break;
    
    case ZLIB_FILEFUNC_SEEK_SET:
      zip->_offset = offset;
      break;
    
  }
  return (zip->_offset >= 0) && (zip->_offset <= length) ? 0 : -1;
}

static int _CloseFunction(voidpf opaque, voidpf stream) {
  return 0;
}

static int _ErrorFunction(voidpf opaque, voidpf stream) {
  return 0;
}

- (id) initWithArchiveData:(NSData*)data {
  _data = [data retain];  // -initWithUnzFile: will call -release on error
  
  zlib_filefunc_def functions;
  functions.zopen_file = _OpenFunction;
  functions.zread_file = _ReadFunction;
  functions.zwrite_file = NULL;
  functions.ztell_file = _TellFuntion;
  functions.zseek_file = _SeekFunction;
  functions.zclose_file = _CloseFunction;
  functions.zerror_file = _ErrorFunction;
  functions.opaque = self;
  return [self initWithUnzFile:unzOpen2(NULL, &functions)];
}

- (NSArray*) retrieveFileList {
  NSMutableArray* array = [NSMutableArray array];
  
  // Set current file to first file in archive
  int result = unzGoToFirstFile(_unzFile);
  while (1) {
    // Open current file
    if (result == UNZ_OK) {
      result = unzOpenCurrentFile(_unzFile);
    }
    if (result != UNZ_OK) {
      if (result != UNZ_END_OF_LIST_OF_FILE) {
        LOG_ERROR(@"MiniZip returned error %i", result);
        array = nil;
      }
      break;
    }
    
    // Retrieve current file path and convert path separators if needed
    unz_file_info fileInfo = {0};
    result = unzGetCurrentFileInfo(_unzFile, &fileInfo, NULL, 0, NULL, 0, NULL, 0);
    if (result != UNZ_OK) {
      unzCloseCurrentFile(_unzFile);
      LOG_ERROR(@"MiniZip returned error %i", result);
      array = nil;
      break;
    }
    char* filename = (char*)malloc(fileInfo.size_filename + 1);
    unzGetCurrentFileInfo(_unzFile, &fileInfo, filename, fileInfo.size_filename, NULL, 0, NULL, 0);
    for (unsigned int i = 0; i < fileInfo.size_filename; ++i) {
      if (filename[i] == '\\') {
        filename[i] = '/';
      }
    }
    filename[fileInfo.size_filename] = 0;
    NSString* path = [NSString stringWithUTF8String:filename];
    free(filename);
    
    // Add current file to list if necessary
    if (_skipInvisible) {
      for (NSString* string in [path pathComponents]) {
        if ([string hasPrefix:@"."]) {
          path = nil;
          break;
        }
      }
    }
    if (path && ![path hasSuffix:@"/"]) {
      [array addObject:path];
    }
    
    // Close current file and go to next one
    unzCloseCurrentFile(_unzFile);
    result = unzGoToNextFile(_unzFile);
  }
  
  return array;
}

// See do_extract_currentfile() from miniunz.c for reference
- (BOOL) extractToPath:(NSString*)outPath {
  BOOL success = YES;
  NSFileManager* manager = [NSFileManager defaultManager];
  
  // Set current file to first file in archive
  int result = unzGoToFirstFile(_unzFile);
  while (1) {
    // Open current file
    if (result == UNZ_OK) {
      result = unzOpenCurrentFile(_unzFile);
    }
    if (result != UNZ_OK) {
      if (result != UNZ_END_OF_LIST_OF_FILE) {
        LOG_ERROR(@"MiniZip returned error %i", result);
        success = NO;
      }
      break;
    }
    
    // Retrieve current file path and convert path separators if needed
    unz_file_info fileInfo = {0};
    result = unzGetCurrentFileInfo(_unzFile, &fileInfo, NULL, 0, NULL, 0, NULL, 0);
    if (result != UNZ_OK) {
      unzCloseCurrentFile(_unzFile);
      LOG_ERROR(@"MiniZip returned error %i", result);
      success = NO;
      break;
    }
    char* filename = (char*)malloc(fileInfo.size_filename + 1);
    unzGetCurrentFileInfo(_unzFile, &fileInfo, filename, fileInfo.size_filename, NULL, 0, NULL, 0);
    for (unsigned int i = 0; i < fileInfo.size_filename; ++i) {
      if (filename[i] == '\\') {
        filename[i] = '/';
      }
    }
    filename[fileInfo.size_filename] = 0;
    NSString* path = [NSString stringWithUTF8String:filename];
    free(filename);
    
    // Extract current file
    if (_skipInvisible) {
      for (NSString* string in [path pathComponents]) {
        if ([string hasPrefix:@"."]) {
          path = nil;
          break;
        }
      }
    }
    if (path) {
      NSString* fullPath = [outPath stringByAppendingPathComponent:path];
      
      // If current file is actually a directory, create it
      if ([path hasSuffix:@"/"]) {
        NSError* error = nil;
        if (![manager createDirectoryAtPath:fullPath withIntermediateDirectories:YES attributes:nil error:&error]) {
          LOG_ERROR(@"Failed creating directory \"%@\" from ZIP archive: %@", path, error);
          success = NO;
        }
      }
      // Otherwise extract file
      else {
        FILE* outFile = fopen((const char*)[fullPath UTF8String], "w+");
        if (outFile == NULL) {
          [manager createDirectoryAtPath:[fullPath stringByDeletingLastPathComponent]
             withIntermediateDirectories:YES
                              attributes:nil
                                   error:nil];
          outFile = fopen((const char*)[fullPath UTF8String], "w+");  // Some zip files don't contain directory alone before file
        }
        if (outFile) {
          while (1) {
            unsigned char buffer[kZipExtractionBufferSize];
            int read = unzReadCurrentFile(_unzFile, buffer, kZipExtractionBufferSize);
            if (read > 0) {
              if (fwrite(buffer, read, 1, outFile) != 1) {
                 LOG_ERROR(@"Failed writing \"%@\" from ZIP archive", path);
                 success = NO;
                 break;
              }
            } else if (read < 0) {
              LOG_ERROR(@"Failed reading \"%@\" from ZIP archive", path);
              success = NO;
              break;
            }
            else {
              break;
            }
          }
          fclose(outFile);
        } else {
          LOG_ERROR(@"Failed creating file \"%@\" from ZIP archive (%s)", fullPath, strerror(errno));
          success = NO;
        }
      }
    }
    
    // Close current file and go to next one
    unzCloseCurrentFile(_unzFile);
    if (!success) {
      break;
    }
    result = unzGoToNextFile(_unzFile);
  }
  
  return success;
}

- (BOOL) extractFile:(NSString*)inPath toPath:(NSString*)outPath {
  BOOL success = NO;
  
  // Set current file to first file in archive
  int result = unzGoToFirstFile(_unzFile);
  while (1) {
    // Open current file
    if (result == UNZ_OK) {
      result = unzOpenCurrentFile(_unzFile);
    }
    if (result != UNZ_OK) {
      if (result != UNZ_END_OF_LIST_OF_FILE) {
        LOG_ERROR(@"MiniZip returned error %i", result);
      }
      break;
    }
    
    // Retrieve current file path and convert path separators if needed
    unz_file_info fileInfo = {0};
    result = unzGetCurrentFileInfo(_unzFile, &fileInfo, NULL, 0, NULL, 0, NULL, 0);
    if (result != UNZ_OK) {
      unzCloseCurrentFile(_unzFile);
      LOG_ERROR(@"MiniZip returned error %i", result);
      break;
    }
    char* filename = (char*)malloc(fileInfo.size_filename + 1);
    unzGetCurrentFileInfo(_unzFile, &fileInfo, filename, fileInfo.size_filename, NULL, 0, NULL, 0);
    for (unsigned int i = 0; i < fileInfo.size_filename; ++i) {
      if (filename[i] == '\\') {
        filename[i] = '/';
      }
    }
    filename[fileInfo.size_filename] = 0;
    NSString* path = [NSString stringWithUTF8String:filename];  // TODO: Is this correct?
    free(filename);
    
    // If file is required one, extract it
    if (![path hasSuffix:@"/"] && [path isEqualToString:inPath]) {
      FILE* outFile = fopen((const char*)[outPath UTF8String], "w");
      if (outFile) {
        success = YES;
        while (1) {
          unsigned char buffer[kZipExtractionBufferSize];
          int read = unzReadCurrentFile(_unzFile, buffer, kZipExtractionBufferSize);
          if (read > 0) {
            if (fwrite(buffer, read, 1, outFile) != 1) {
               LOG_ERROR(@"Failed writing \"%@\" from ZIP archive", path);
               success = NO;
               break;
            }
          } else if (read < 0) {
            LOG_ERROR(@"Failed reading \"%@\" from ZIP archive", path);
            success = NO;
            break;
          }
          else {
            break;
          }
        }
        fclose(outFile);
      } else {
        LOG_ERROR(@"Failed creating \"%@\" from ZIP archive", path);
      }
      unzCloseCurrentFile(_unzFile);
      break;
    }
    
    // Close current file and go to next one
    unzCloseCurrentFile(_unzFile);
    result = unzGoToNextFile(_unzFile);
  }
  
  return success;
}

@end
