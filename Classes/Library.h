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

#import "Database.h"
#import "GridView.h"

#define kLibraryExtendedAttribute @"comicflow.identifier"
#define kLibraryThumbnailWidth 135
#define kLibraryThumbnailHeight 180

@class LibraryUpdater;

@protocol LibraryUpdaterDelegate <NSObject>
- (void)libraryUpdaterWillStart:(LibraryUpdater*)library;
- (void)libraryUpdaterDidContinue:(LibraryUpdater*)library progress:(float)progress;
- (void)libraryUpdaterDidFinish:(LibraryUpdater*)library;
@end

#if __STORE_THUMBNAILS_IN_DATABASE__

@interface Thumbnail : DatabaseObject
@property (nonatomic, copy) NSData* data;
@end

#endif

@interface Comic : DatabaseObject {
    NSMutableData* fileData;
    NSUInteger totalBytes;
    NSUInteger receivedBytes;
    NSString* urlToDownload;
    NSString* dstPath;
    NSURLConnection* connection;
    GridView* gridToUpdate;
}
@property (nonatomic) DatabaseSQLRowID collection; // May be 0
@property (nonatomic, copy) NSString* name;
#if __STORE_THUMBNAILS_IN_DATABASE__
@property (nonatomic) DatabaseSQLRowID thumbnail;
#else
@property (nonatomic, copy) NSString* thumbnail;
#endif
@property (nonatomic) NSTimeInterval time;
@property (nonatomic) int status; // -1: new, 0: normal, 1+: reading

//Dropbox code
@property (nonatomic) BOOL isDownloading;
@property (nonatomic) CGFloat progress;

- (void)startDownloading:(NSURL*)url fileName:(NSString*)filename;
@end

@interface Collection : DatabaseObject
@property (nonatomic, copy) NSString* name;
#if __STORE_THUMBNAILS_IN_DATABASE__
@property (nonatomic) DatabaseSQLRowID thumbnail;
#else
@property (nonatomic, copy) NSString* thumbnail;
#endif
@property (nonatomic) NSTimeInterval time;
@property (nonatomic, readonly) int status; // -1: new, 0: normal, 1+: reading
@property (nonatomic) int scrolling;
@end

@interface Collection ()
@property (nonatomic, retain) NSArray* comics;
@end

@interface LibraryConnection : DatabaseConnection

@property (retain, nonatomic) NSMutableArray* comicsBeingDownloaded;

+ (NSString*)libraryRootPath;
+ (NSString*)libraryApplicationDataPath;
+ (NSString*)libraryDatabasePath;
+ (LibraryConnection*)mainConnection; // For main thread only
- (NSArray*)fetchAllComicsByName;
- (NSArray*)fetchAllComicsByDate;
- (NSArray*)fetchAllComicsByStatus;
- (NSArray*)fetchComicsInCollection:(Collection*)collection;
- (NSArray*)fetchAllCollectionsByName;
- (BOOL)updateStatus:(int)status forComicsInCollection:(Collection*)collection;
- (BOOL)updateStatusForAllComics:(int)status;
- (NSString*)pathForComic:(Comic*)comic;
- (NSString*)pathForCollection:(Collection*)collection;

- (void)downloadFileAtUrl:(NSURL*)url withFileName:(NSString*)filename;
//updateGrid:(GridView*)gridView
- (void)finishedDownloading:(Comic*)comic;

@end

@interface LibraryUpdater : NSObject {
@private
    id<LibraryUpdaterDelegate> _delegate;
    CGFloat _screenScale;
    CGImageRef _comicPlaceholderImageRef;
    CGImageRef _comicBackgroundImageRef;
    CGImageRef _comicScreenImageRef;
    CGImageRef _collectionBackgroundImageRef;
    CGImageRef _collectionScreenImageRef;
    NSData* _fakeData;
    BOOL _updating;
}
@property (nonatomic, readonly, getter=isUpdating) BOOL updating;
@property (nonatomic, assign) id<LibraryUpdaterDelegate> delegate;
+ (LibraryUpdater*)sharedUpdater;
- (void)update:(BOOL)force; // Does nothing if already updating
@end
