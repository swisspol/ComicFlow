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

#import <CoreText/CoreText.h>
#import <UIKit/UIKit.h>

#import "Library.h"
#import "Defaults.h"
#import "MiniZip.h"
#import "UnRAR.h"
#import "Extensions_Foundation.h"
#import "ImageUtilities.h"
#import "Logging.h"

#define kInboxDirectoryName @"Inbox"

#define kComicCoverX 10
#define kComicCoverY 8
#define kComicCoverWidth 117
#define kComicCoverHeight 166

#define kCollectionCoverX 30
#define kCollectionCoverY 9
#define kCollectionCoverWidth 96
#define kCollectionCoverHeight 164
#define kCollectionFontName "Helvetica-Bold"
#define kCollectionFontSize 16.0

#define kFakeRowID 0xFFFFFFFF

typedef enum {
  kArchiveType_Unknown,
  kArchiveType_ZIP,
  kArchiveType_RAR,
  kArchiveType_PDF
} ArchiveType;

@interface LibraryUpdater (Updating)
- (id) _updateLibrary:(BOOL)force;
@end

#if __STORE_THUMBNAILS_IN_DATABASE__

@implementation Thumbnail

@dynamic data;

+ (NSString*) sqlTableName {
  return @"thumbnails";
}

+ (DatabaseSQLColumnOptions) sqlColumnOptionsForProperty:(NSString*)property {
  if ([property isEqualToString:@"data"]) {
    return kDatabaseSQLColumnOption_NotNull;
  }
  return [super sqlColumnOptionsForProperty:property];
}

@end

#endif

@implementation Comic

@dynamic collection, name, thumbnail, time, status;

+ (NSString*) sqlTableName {
  return @"comics";
}

#if TARGET_OS_IPHONE && !TARGET_IPHONE_SIMULATOR

+ (DatabaseSQLColumnOptions) sqlColumnOptionsForProperty:(NSString*)property {
  if ([property isEqualToString:@"name"]) {
    return kDatabaseSQLColumnOption_CaseInsensitive_UTF8;
  }
  return [super sqlColumnOptionsForProperty:property];
}

#endif

@end

@implementation Collection

@dynamic name, thumbnail, time, status, scrolling;
@synthesize comics;

+ (NSString*) sqlTableName {
  return @"collections";
}

#if TARGET_OS_IPHONE && !TARGET_IPHONE_SIMULATOR

+ (DatabaseSQLColumnOptions) sqlColumnOptionsForProperty:(NSString*)property {
  if ([property isEqualToString:@"name"]) {
    return kDatabaseSQLColumnOption_CaseInsensitive_UTF8;
  }
  return [super sqlColumnOptionsForProperty:property];
}

#endif

- (void) dealloc {
  [comics release];
  
  [super dealloc];
}

@end

@implementation LibraryConnection

+ (DatabaseConnection*) defaultDatabaseConnection {
  DNOT_REACHED();
  return nil;
}

+ (NSString*) libraryRootPath {
  static NSString* path = nil;
  if (path == nil) {
    path = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject] copy];
  }
  return path;
}

+ (NSString*) libraryApplicationDataPath {
  static NSString* path = nil;
  if (path == nil) {
    path = [[[self libraryRootPath] stringByAppendingPathComponent:@".library"] copy];
  }
  return path;
}

+ (NSString*) libraryDatabasePath {
  static NSString* path = nil;
  if (path == nil) {
    path = [[[self libraryApplicationDataPath] stringByAppendingPathComponent:@"database.db"] copy];
  }
  return path;
}

+ (LibraryConnection*) mainConnection {
  static LibraryConnection* connection = nil;
  if (connection == nil) {
    NSString* statements = @"CREATE TRIGGER IF NOT EXISTS update_collection_status_insert AFTER INSERT ON comics BEGIN UPDATE collections SET status=(SELECT (CASE WHEN MAX(status)>0 THEN 1 ELSE (CASE WHEN MIN(status) < 0 THEN -1 ELSE 0 END) END) FROM comics WHERE collection=new.collection) WHERE _id_=new.collection; END;\n"
                            "CREATE TRIGGER IF NOT EXISTS update_collection_status_update AFTER UPDATE OF status ON comics BEGIN UPDATE collections SET status=(SELECT (CASE WHEN MAX(status)>0 THEN 1 ELSE (CASE WHEN MIN(status) < 0 THEN -1 ELSE 0 END) END) FROM comics WHERE collection=new.collection) WHERE _id_=new.collection; END;\n"
                            "CREATE TRIGGER IF NOT EXISTS update_collection_status_delete AFTER DELETE ON comics BEGIN UPDATE collections SET status=(SELECT (CASE WHEN MAX(status)>0 THEN 1 ELSE (CASE WHEN MIN(status) < 0 THEN -1 ELSE 0 END) END) FROM comics WHERE collection=old.collection) WHERE _id_=old.collection; END";
    if ([[NSFileManager defaultManager] createDirectoryAtPath:[self libraryApplicationDataPath]
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:NULL]) {
      if ([LibraryConnection initializeDatabaseAtPath:[self libraryDatabasePath] usingObjectClasses:nil extraSQLStatements:statements]) {
        connection = [[LibraryConnection alloc] initWithDatabaseAtPath:[self libraryDatabasePath]];
      }
    }
  }
  return connection;
}

- (NSArray*) fetchAllComicsByName {
  return [self fetchObjectsOfClass:[Comic class] withSQLWhereClause:@"1 ORDER BY name ASC" limit:0];
}

- (NSArray*) fetchAllComicsByDate {
  return [self fetchObjectsOfClass:[Comic class] withSQLWhereClause:@"1 ORDER BY time DESC" limit:0];
}

- (NSArray*) fetchAllComicsByStatus {
  return [self fetchObjectsOfClass:[Comic class] withSQLWhereClause:@"1 ORDER BY status>0 DESC, status==-1 DESC, name ASC" limit:0];
}

- (NSArray*) fetchComicsInCollection:(Collection*)collection {
  return [self fetchObjectsOfClass:[Comic class]
                withSQLWhereClause:[NSString stringWithFormat:@"collection=%i ORDER BY name ASC", collection.sqlRowID]
                             limit:0];
}

- (NSArray*) fetchAllCollectionsByName {
  return [self fetchObjectsOfClass:[Collection class] withSQLWhereClause:@"1 ORDER BY name ASC" limit:0];
}

- (BOOL) updateStatus:(int)status forComicsInCollection:(Collection*)collection {
  NSString* statement = [NSString stringWithFormat:@"UPDATE comics SET status=%i WHERE collection=%i", status, collection.sqlRowID];
  return [self executeRawSQLStatements:statement];
}

- (BOOL) updateStatusForAllComics:(int)status {
  NSString* statement = [NSString stringWithFormat:@"UPDATE comics SET status=%i", status];
  return [self executeRawSQLStatements:statement];
}

@end

@implementation LibraryUpdater

@synthesize delegate=_delegate, updating=_updating;

+ (LibraryUpdater*) sharedUpdater {
  static LibraryUpdater* updater = nil;
  if (updater == nil) {
    updater = [[LibraryUpdater alloc] init];
  }
  return updater;
}

- (id) init {
  if ((self = [super init])) {
    _screenScale = [[UIScreen mainScreen] scale];
    _comicBackgroundImageRef = CGImageRetain([[UIImage imageWithContentsOfFile:
                                             [[NSBundle mainBundle] pathForResource:@"Comic" ofType:@"png"]] CGImage]);
    CHECK(_comicBackgroundImageRef);
    _comicScreenImageRef = CGImageRetain([[UIImage imageWithContentsOfFile:
                                         [[NSBundle mainBundle] pathForResource:@"Comic-Screen" ofType:@"png"]] CGImage]);
    CHECK(_comicScreenImageRef);
    _collectionBackgroundImageRef = CGImageRetain([[UIImage imageWithContentsOfFile:
                                                  [[NSBundle mainBundle] pathForResource:@"Collection" ofType:@"png"]] CGImage]);
    CHECK(_collectionBackgroundImageRef);
    _collectionScreenImageRef = CGImageRetain([[UIImage imageWithContentsOfFile:
                                              [[NSBundle mainBundle] pathForResource:@"Collection-Screen" ofType:@"png"]] CGImage]);
    CHECK(_collectionScreenImageRef);
    
    DatabaseSQLRowID fakeRowID = kFakeRowID;
    _fakeData = [[NSData alloc] initWithBytes:&fakeRowID length:sizeof(DatabaseSQLRowID)];
  }
  return self;
}

- (void) update:(BOOL)force {
  if (_updating == NO) {
    LOG_VERBOSE(force ? @"Force updating library" : @"Updating library");
    [_delegate libraryUpdaterWillStart:self];
    
    if (force) {
      CFTimeInterval time = CFAbsoluteTimeGetCurrent();
#if __STORE_THUMBNAILS_IN_DATABASE__
      [[LibraryConnection mainConnection] deleteAllObjectsOfClass:[Thumbnail class]];
#endif
      [[LibraryConnection mainConnection] deleteAllObjectsOfClass:[Comic class]];
      [[LibraryConnection mainConnection] deleteAllObjectsOfClass:[Collection class]];
      [[LibraryConnection mainConnection] vacuum];
      LOG_INFO(@"Reset library in %.1f seconds", CFAbsoluteTimeGetCurrent() - time);
    }
    
    _updating = YES;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
      NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
      
      [self _updateLibrary:force];
      
      dispatch_async(dispatch_get_main_queue(), ^{
        [[NSUserDefaults standardUserDefaults] synchronize];
        [_delegate libraryUpdaterDidFinish:self];
        _updating = NO;
        LOG_VERBOSE(@"Done updating library");
      });
      
      [pool release];
    });
  }
}

@end

@implementation LibraryUpdater (Updating)

// Called from GCD thread
- (NSData*) _thumbnailDataForComicWithCoverImage:(CGImageRef)imageRef {
  size_t contextWidth = _screenScale * kLibraryThumbnailWidth;
  size_t contextHeight = _screenScale * kLibraryThumbnailHeight;
  
  CGColorSpaceRef colorspace = CGColorSpaceCreateDeviceRGB();
  CGContextRef context = CGBitmapContextCreate(NULL, contextWidth, contextHeight, 8, 0, colorspace,
                                               kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Host);
  CGContextClearRect(context, CGRectMake(0, 0, contextWidth, contextHeight));
  CGContextScaleCTM(context, _screenScale, _screenScale);
  
  CGContextSetBlendMode(context, kCGBlendModeCopy);
  CGContextDrawImage(context, CGRectMake(0, 0, kLibraryThumbnailWidth, kLibraryThumbnailHeight), _comicBackgroundImageRef);
  
  CGContextSetBlendMode(context, kCGBlendModeMultiply);
  CGContextDrawImage(context, CGRectMake(kComicCoverX, kComicCoverY, kComicCoverWidth, kComicCoverHeight), imageRef);
  
  CGContextSetBlendMode(context, kCGBlendModeScreen);
  CGContextDrawImage(context, CGRectMake(0, 0, kLibraryThumbnailWidth, kLibraryThumbnailHeight), _comicScreenImageRef);
  
  imageRef = CGBitmapContextCreateImage(context);
  UIImage* image = [[UIImage alloc] initWithCGImage:imageRef];
  NSData* data = UIImagePNGRepresentation(image);
  [image release];
  CGImageRelease(imageRef);
  CGContextRelease(context);
  CGColorSpaceRelease(colorspace);
  return data;
}

// Called from GCD thread
- (NSData*) _thumbnailDataForCollectionWithCoverImage:(CGImageRef)imageRef name:(NSString*)name {
  size_t contextWidth = _screenScale * kLibraryThumbnailWidth;
  size_t contextHeight = _screenScale * kLibraryThumbnailHeight;
  
  CGColorSpaceRef colorspace = CGColorSpaceCreateDeviceRGB();
  CGContextRef context = CGBitmapContextCreate(NULL, contextWidth, contextHeight, 8, 0, colorspace,
                                               kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Host);
  CGContextClearRect(context, CGRectMake(0, 0, contextWidth, contextHeight));
  CGContextScaleCTM(context, _screenScale, _screenScale);
  
  CGContextSetBlendMode(context, kCGBlendModeCopy);
  CGContextDrawImage(context, CGRectMake(0, 0, kLibraryThumbnailWidth, kLibraryThumbnailHeight), _collectionBackgroundImageRef);
  
  CGContextSetBlendMode(context, kCGBlendModeLuminosity);
  CGContextSetAlpha(context, 0.25);
  CGContextDrawImage(context, CGRectMake(kCollectionCoverX, kCollectionCoverY, kCollectionCoverWidth, kCollectionCoverHeight), imageRef);
  CGContextSetAlpha(context, 1.0);
  
  CGContextSetBlendMode(context, kCGBlendModeScreen);
  CGContextDrawImage(context, CGRectMake(0, 0, kLibraryThumbnailWidth, kLibraryThumbnailHeight), _collectionScreenImageRef);
  
  CGContextSetBlendMode(context, kCGBlendModeNormal);
  static NSMutableDictionary* attributes = nil;
  if (attributes == nil) {
    attributes = [[NSMutableDictionary alloc] init];
    [attributes setObject:(id)kCFBooleanTrue forKey:(id)kCTForegroundColorFromContextAttributeName];
    CTFontRef font = CTFontCreateWithName(CFSTR(kCollectionFontName), kCollectionFontSize, NULL);
    if (font) {
      [attributes setObject:(id)font forKey:(id)kCTFontAttributeName];
      CFRelease(font);
    }
    CTTextAlignment alignment = kCTCenterTextAlignment;
    CTLineBreakMode lineBreaking = kCTLineBreakByWordWrapping;
    CTParagraphStyleSetting settings[] = {
                                          {kCTParagraphStyleSpecifierAlignment, sizeof(alignment), &alignment},
                                          {kCTParagraphStyleSpecifierLineBreakMode, sizeof(lineBreaking), &lineBreaking}
                                         };
    CTParagraphStyleRef style = CTParagraphStyleCreate(settings, sizeof(settings) / sizeof(CTParagraphStyleSetting));
    if (style) {
      [attributes setObject:(id)style forKey:(id)kCTParagraphStyleAttributeName];
      CFRelease(style);
    }
  }
  CFAttributedStringRef string = CFAttributedStringCreate(kCFAllocatorDefault, (CFStringRef)name, (CFDictionaryRef)attributes);
  if (string) {
    CTFramesetterRef framesetter = CTFramesetterCreateWithAttributedString(string);
    if (framesetter) {
      CGMutablePathRef path = CGPathCreateMutable();
      CGRect rect = CGRectMake(kCollectionCoverX, kCollectionCoverY, kCollectionCoverWidth, kCollectionCoverHeight);
      CGPathAddRect(path, NULL, CGRectOffset(CGRectInset(rect, 4.0, 30.0), 0.0, 20.0));
      CTFrameRef frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, CFAttributedStringGetLength(string)), path, NULL);
      if (frame) {
        CFArrayRef lines = CTFrameGetLines(frame);
        CFIndex count = CFArrayGetCount(lines);
        if (count) {
          CGPoint origin;
          CTFrameGetLineOrigins(frame, CFRangeMake(count - 1, 1), &origin);
          CGFloat descent;
          CTLineGetTypographicBounds(CFArrayGetValueAtIndex(lines, count - 1), NULL, &descent, NULL);
          CGContextTranslateCTM(context, 0.0, -floorf((origin.y - descent - 1) / 2.0));
        }
#if TARGET_IPHONE_SIMULATOR
        CGContextSetShouldSmoothFonts(context, false);
#endif
        
        CGContextSetRGBFillColor(context, 0.25, 0.25, 0.25, 1.0);
        CGContextSetTextMatrix(context, CGAffineTransformIdentity);
        CTFrameDraw(frame, context);
        CGContextTranslateCTM(context, 0.0, -1.0);
        CGContextSetRGBFillColor(context, 1.0, 1.0, 1.0, 1.0);
        CGContextSetTextMatrix(context, CGAffineTransformIdentity);
        CTFrameDraw(frame, context);
      }
      CGPathRelease(path);
      CFRelease(framesetter);
    }
    CFRelease(string);
  }
  
  imageRef = CGBitmapContextCreateImage(context);
  UIImage* image = [[UIImage alloc] initWithCGImage:imageRef];
  NSData* data = UIImagePNGRepresentation(image);
  [image release];
  CGImageRelease(imageRef);
  CGContextRelease(context);
  CGColorSpaceRelease(colorspace);
  return data;
}

- (CGImageRef) _copyCoverImageFromComicAtPath:(NSString*)path withArchiveType:(ArchiveType)type forSize:(CGSize)size {
  size.width *= _screenScale;
  size.height *= _screenScale;
  CGImageRef imageRef = NULL;
  if (type == kArchiveType_PDF) {
    CGPDFDocumentRef document = CGPDFDocumentCreateWithURL((CFURLRef)[NSURL fileURLWithPath:path]);
    if (document) {
      if (CGPDFDocumentGetNumberOfPages(document) > 0) {
        CGPDFPageRef page = CGPDFDocumentGetPage(document, 1);
        if (page) {
          imageRef = CreateRenderedPDFPage(page, CGSizeMake(2.0 * size.width, 2 * size.height),  // Render at 2x resolution to ensure good antialiasing
                                           kImageScalingMode_AspectFill, [[UIColor whiteColor] CGColor]);
        }
      }
      CGPDFDocumentRelease(document);
    }
  } else {
    id archive = nil;
    if (type == kArchiveType_ZIP) {
      archive = [[MiniZip alloc] initWithArchiveAtPath:path];
    } else if (type == kArchiveType_RAR) {
      archive = [[UnRAR alloc] initWithArchiveAtPath:path];
    }
    [archive setSkipInvisibleFiles:YES];
    NSString* cover = nil;
    for (NSString* file in [archive retrieveFileList]) {
      NSString* extension = [file pathExtension];
      if (![extension caseInsensitiveCompare:@"jpg"] || ![extension caseInsensitiveCompare:@"jpeg"] ||
        ![extension caseInsensitiveCompare:@"png"] || ![extension caseInsensitiveCompare:@"gif"]) {
        if (!cover || ([file caseInsensitiveCompare:cover] == NSOrderedAscending)) {
          cover = file;
        }
      }
    }
    if (cover) {
      NSString* temp = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
      if ([archive extractFile:cover toPath:temp]) {
        NSData* data = [[NSData alloc] initWithContentsOfFile:temp];
        if (data) {
          UIImage* image = [[UIImage alloc] initWithData:data];
          if (image) {
            imageRef = CreateScaledImage([image CGImage], size, kImageScalingMode_AspectFill, [[UIColor blackColor] CGColor]);
            [image release];
          }
          [data release];
        }
        [[NSFileManager defaultManager] removeItemAtPath:temp error:NULL];
      }
    }
    [archive release];
  }
  return imageRef;
}

// Called from GCD thread
- (void) _updateComicForPath:(NSString*)path
                        type:(ArchiveType)type
                  collection:(Collection*)collection  // May be nil
                zombieComics:(CFMutableDictionaryRef)zombieComics
                  connection:(LibraryConnection*)connection
                       force:(BOOL)force {
  NSString* name = [path lastPathComponent];  // TODO: Improve this
  
  // Check if this comic has already been processed
  Comic* comic = nil;
  if (force == NO) {
    NSData* data = [[NSFileManager defaultManager] extendedAttributeDataWithName:kLibraryExtendedAttribute forFileAtPath:path];
    if (data.length == sizeof(DatabaseSQLRowID)) {
      DatabaseSQLRowID rowID = *((DatabaseSQLRowID*)data.bytes);
      if (rowID == kFakeRowID) {
        LOG_WARNING(@"Skipping comic \"%@\"", name);  // We started processing this comic but never finished - Assume it's corrupted
        return;
      } else {
        comic = (Comic*)CFDictionaryGetValue(zombieComics, (void*)rowID);
      }
    }
  }
  
  // If yes, update comic
  if (comic) {
    CFDictionaryRemoveValue(zombieComics, (void*)comic.sqlRowID);
    if ((comic.collection != collection.sqlRowID) || ![comic.name isEqualToString:name]) {
      comic.collection = collection.sqlRowID;
      comic.name = name;
      [connection updateObject:comic];
      LOG_VERBOSE(@"Updated comic \"%@\" (%i)", name, comic.sqlRowID);
    }
  }
  // Otherwise process and add comic to library
  else {
    [[NSFileManager defaultManager] setExtendedAttributeData:_fakeData withName:kLibraryExtendedAttribute forFileAtPath:path];
    
    // Process comic
    CGImageRef imageRef = [self _copyCoverImageFromComicAtPath:path withArchiveType:type forSize:CGSizeMake(kComicCoverWidth, kComicCoverHeight)];
    if (imageRef) {
      NSData* data = [self _thumbnailDataForComicWithCoverImage:imageRef];
      if (data) {
#if __STORE_THUMBNAILS_IN_DATABASE__
        Thumbnail* thumbnail = [[[Thumbnail alloc] init] autorelease];
        thumbnail.data = data;
        if (![connection insertObject:thumbnail]) {
          thumbnail = nil;
        }
#else
        NSString* thumbnail = [[[NSProcessInfo processInfo] globallyUniqueString] stringByAppendingPathExtension:@"png"];
        if (![data writeToFile:[[LibraryConnection libraryApplicationDataPath] stringByAppendingPathComponent:thumbnail] atomically:YES]) {
          thumbnail = nil;
        }
#endif
        if (thumbnail) {
          comic = [[[Comic alloc] init] autorelease];
          comic.collection = collection.sqlRowID;
          comic.name = name;
#if __STORE_THUMBNAILS_IN_DATABASE__
          comic.thumbnail = thumbnail.sqlRowID;
#else
          comic.thumbnail = thumbnail;
#endif
          comic.time = CFAbsoluteTimeGetCurrent();
          comic.status = -1;
          if ([connection insertObject:comic]) {
            DatabaseSQLRowID rowID = comic.sqlRowID;
            [[NSFileManager defaultManager] setExtendedAttributeData:[NSData dataWithBytes:&rowID length:sizeof(DatabaseSQLRowID)]
                                                            withName:kLibraryExtendedAttribute
                                                       forFileAtPath:path];
          } else {
            comic = nil;
          }
        }
      }
      CGImageRelease(imageRef);
    }
    if (comic) {
      LOG_VERBOSE(@"Imported comic \"%@\" (%i)", name, comic.sqlRowID);
    } else {
      LOG_ERROR(@"Failed importing comic \"%@\"", name);
    }
  }
}

static inline void _ZombieRemoveFunction(LibraryConnection* connection, DatabaseObject* object) {
#if __STORE_THUMBNAILS_IN_DATABASE__
  DatabaseSQLRowID rowID = [(id)object thumbnail];
  if (rowID > 0) {
    [connection deleteObjectOfClass:[Thumbnail class] withSQLRowID:rowID];
  }
#else
  NSString* name = [(id)object thumbnail];
  if (name) {
    NSString* path = [[LibraryConnection libraryApplicationDataPath] stringByAppendingPathComponent:name];
    [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
  }
#endif
  [connection deleteObject:object];
}

static void _ZombieCollectionsRemoveFunction(const void* key, const void* value, void* context) {
  LOG_VERBOSE(@"Removed collection \"%@\" (%i)", [(Collection*)value name], (DatabaseSQLRowID)key);
  _ZombieRemoveFunction((LibraryConnection*)context, (DatabaseObject*)value);
}

static void _ZombieComicsRemoveFunction(const void* key, const void* value, void* context) {
  if (!isnan([(Comic*)value time])) {
    LOG_VERBOSE(@"Removed comic \"%@\" (%i)", [(Comic*)value name], (DatabaseSQLRowID)key);
    _ZombieRemoveFunction((LibraryConnection*)context, (DatabaseObject*)value);
  }
}

static void _ZombieComicsMarkFunction(const void* key, const void* value, void* context) {
  if ([(Comic*)value collection] == (DatabaseSQLRowID)context) {
    [(Comic*)value setTime:NAN];
  }
}

// Called from GCD thread
- (id) _updateLibrary:(BOOL)force {
  LibraryConnection* connection = [[LibraryConnection alloc] initWithDatabaseAtPath:[LibraryConnection libraryDatabasePath]];
  if (connection == nil) {
    DNOT_REACHED();
    return nil;
  }
  NSString* rootPath = [LibraryConnection libraryRootPath];
  
  // Build list of all collections and comics currently in library as potential zombies
  CFMutableDictionaryRef zombieCollections = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, NULL, NULL);
  for (Collection* collection in [connection fetchAllObjectsOfClass:[Collection class]]) {
    CFDictionarySetValue(zombieCollections, (void*)collection.sqlRowID, collection);
  }
  CFMutableDictionaryRef zombieComics = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, NULL, NULL);
  for (Comic* comic in [connection fetchAllObjectsOfClass:[Comic class]]) {
    CFDictionarySetValue(zombieComics, (void*)comic.sqlRowID, comic);
  }
    
  // Build list of all directories and files in root directory
  float maximumProgress = 0.0;
  NSMutableDictionary* directories = [[NSMutableDictionary alloc] init];
  {
    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
    for (NSString* path in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:rootPath error:NULL]) {
      if ([path hasPrefix:@"."]) {
        continue;
      }
      NSString* fullPath = [rootPath stringByAppendingPathComponent:path];
      NSString* type = [[[NSFileManager defaultManager] attributesOfItemAtPath:fullPath error:NULL] fileType];
#if TARGET_IPHONE_SIMULATOR
      if ([type isEqualToString:NSFileTypeSymbolicLink]) {
        NSString* path = [[NSFileManager defaultManager] destinationOfSymbolicLinkAtPath:fullPath error:NULL];
        type = [[[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL] fileType];
      }
#endif
      if ([type isEqualToString:NSFileTypeRegular]) {
        NSMutableArray* array = [directories objectForKey:@""];
        if (array == nil) {
          array = [[NSMutableArray alloc] init];
          [directories setObject:array forKey:@""];
          [array release];
        }
        [array addObject:path];
        maximumProgress += 1.0;
      } else if ([type isEqualToString:NSFileTypeDirectory] && ![path isEqualToString:kInboxDirectoryName]) {
        NSMutableArray* array = [[NSMutableArray alloc] init];
        for (NSString* subpath in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:fullPath error:NULL]) {
          if ([subpath hasPrefix:@"."]) {
            continue;
          }
          NSString* fullSubpath = [fullPath stringByAppendingPathComponent:subpath];
          NSDictionary* attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:fullSubpath error:NULL];
          if ([[attributes fileType] isEqualToString:NSFileTypeRegular]) {
            [array addObject:subpath];
            maximumProgress += 1.0;
          }
        }
        [directories setObject:array forKey:path];
        [array release];
      }
    }
    [pool release];
  }
  
  // Process directories
  {
    float currentProgress = 0.0;
    float lastProgress = 0.0;
    for (NSString* directory in directories) {
      NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
      NSString* fullPath = [rootPath stringByAppendingPathComponent:directory];
      NSDictionary* attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:fullPath error:NULL];
      NSTimeInterval time = [[attributes fileModificationDate] timeIntervalSinceReferenceDate];
      BOOL needsUpdate = NO;
      
      // Check if this collection has already been processed
      Collection* collection = nil;
      if (directory.length && !force) {
        NSData* data = [[NSFileManager defaultManager] extendedAttributeDataWithName:kLibraryExtendedAttribute
                                                                       forFileAtPath:fullPath];
        if (data.length == sizeof(DatabaseSQLRowID)) {
          DatabaseSQLRowID rowID = *((DatabaseSQLRowID*)data.bytes);
          collection = (Collection*)CFDictionaryGetValue(zombieCollections, (void*)rowID);
        }
      }
      
      // If yes, update collection
      if (collection) {
        CFDictionaryRemoveValue(zombieCollections, (void*)collection.sqlRowID);
        if (time != collection.time) {
          needsUpdate = YES;
        } else {
          CFDictionaryApplyFunction(zombieComics, _ZombieComicsMarkFunction, (void*)collection.sqlRowID);
          if (![collection.name isEqualToString:directory]) {
            collection.name = directory;
            [connection updateObject:collection];
            LOG_VERBOSE(@"Updated collection \"%@\" (%i)", directory, collection.sqlRowID);
          }
        }
      }
      // Otherwise add collection
      else if (directory.length) {
        collection = [[[Collection alloc] init] autorelease];
        collection.name = directory;
        // collection.time = time;
        if ([connection insertObject:collection]) {
          DatabaseSQLRowID rowID = collection.sqlRowID;
          [[NSFileManager defaultManager] setExtendedAttributeData:[NSData dataWithBytes:&rowID
                                                                                  length:sizeof(DatabaseSQLRowID)]
                                                          withName:kLibraryExtendedAttribute
                                                     forFileAtPath:fullPath];
          LOG_VERBOSE(@"Imported collection \"%@\" (%i)", directory, collection.sqlRowID);
          needsUpdate = YES;
        } else {
          LOG_ERROR(@"Failed importing collection \"%@\"", directory);
        }
      }
      // Handle special root collection
      else {
        if (force || (time != [[NSUserDefaults standardUserDefaults] doubleForKey:kDefaultKey_RootTimestamp])) {
          needsUpdate = YES;
        } else {
          CFDictionaryApplyFunction(zombieComics, _ZombieComicsMarkFunction, (void*)0);
        }
      }
      
      // Process comics in collection
      NSArray* files = [directories objectForKey:directory];
      if (needsUpdate) {
        if (collection) {
          LOG_VERBOSE(@"Scanning collection \"%@\" (%i)", directory, collection.sqlRowID);
        } else {
          LOG_VERBOSE(@"Scanning root collection");
        }
        CGImageRef imageRef = NULL;
        for (NSString* file in files) {
          ArchiveType type = kArchiveType_Unknown;
          NSString* extension = [file pathExtension];
          if (![extension caseInsensitiveCompare:@"zip"] || ![extension caseInsensitiveCompare:@"cbz"]) {
            type = kArchiveType_ZIP;
          } else if (![extension caseInsensitiveCompare:@"rar"] || ![extension caseInsensitiveCompare:@"cbr"]) {
            type = kArchiveType_RAR;
          } else if (![extension caseInsensitiveCompare:@"pdf"]) {
            type = kArchiveType_PDF;
          }
          if (type != kArchiveType_Unknown) {
            NSString* path = [fullPath stringByAppendingPathComponent:file];
            [self _updateComicForPath:path
                                 type:type
                           collection:collection
                         zombieComics:zombieComics
                           connection:connection
                                force:force];
            if (collection && !imageRef) {
              LOG_VERBOSE(@"Using comic \"%@\" to generate thumbnail for collection \"%@\"", file, directory);
              imageRef = [self _copyCoverImageFromComicAtPath:path withArchiveType:type forSize:CGSizeMake(kCollectionCoverWidth, kCollectionCoverHeight)];
            }
          } else {
            LOG_INFO(@"Ignoring unknown type comic \"%@\"", file);
          }
          
          currentProgress += 1.0;
          float progress = currentProgress / maximumProgress;
          if (roundf(progress * 250.0) != roundf(lastProgress * 250.0)) {
            dispatch_async(dispatch_get_main_queue(), ^{
              [_delegate libraryUpdaterDidContinue:self progress:progress];
            });
            lastProgress = progress;
          }
        }
        if (collection) {
#if __STORE_THUMBNAILS_IN_DATABASE__
          Thumbnail* thumbnail = nil;
#else
          NSString* thumbnail = nil;
#endif
          if (imageRef) {
            NSData* data = [self _thumbnailDataForCollectionWithCoverImage:imageRef name:directory];
            if (data) {
#if __STORE_THUMBNAILS_IN_DATABASE__
              thumbnail = [[[Thumbnail alloc] init] autorelease];
              thumbnail.data = data;
              if (![connection insertObject:thumbnail]) {
                thumbnail = nil;
              }
#else
              thumbnail = [[[NSProcessInfo processInfo] globallyUniqueString] stringByAppendingPathExtension:@"png"];
              if (![data writeToFile:[[LibraryConnection libraryApplicationDataPath] stringByAppendingPathComponent:thumbnail] atomically:YES]) {
                thumbnail = nil;
              }
#endif
            }
          }
#if __STORE_THUMBNAILS_IN_DATABASE__
          collection.thumbnail = thumbnail.sqlRowID;
#else
          collection.thumbnail = thumbnail;
#endif
          collection.name = directory;
          collection.time = time;
          [connection updateObject:collection];
        } else {
          [[NSUserDefaults standardUserDefaults] setDouble:time forKey:kDefaultKey_RootTimestamp];
        }
        CGImageRelease(imageRef);
      } else {
        currentProgress += files.count;
        float progress = currentProgress / maximumProgress;
        if (roundf(progress * 250.0) != roundf(lastProgress * 250.0)) {
          dispatch_async(dispatch_get_main_queue(), ^{
            [_delegate libraryUpdaterDidContinue:self progress:progress];
          });
          lastProgress = progress;
        }
      }
      
      [pool release];
    }
    DCHECK(currentProgress <= maximumProgress);
  }
  
  // Remove zombies
  CFDictionaryApplyFunction(zombieCollections, _ZombieCollectionsRemoveFunction, connection);
  CFDictionaryApplyFunction(zombieComics, _ZombieComicsRemoveFunction, connection);
  
  [directories release];
  CFRelease(zombieComics);
  CFRelease(zombieCollections);
  [connection release];
  return [NSNull null];
}

@end
