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
#if TARGET_IPHONE_SIMULATOR
#import <unistd.h>
#endif

#import "ComicViewController.h"
#import "ZoomView.h"
#import "MiniZip.h"
#import "UnRAR.h"
#import "ImageUtilities.h"
#import "Logging.h"

#define kMaxPageSize 1500.0
#define kLeftZoneRatio 0.2
#define kRightZoneRatio 0.8

@interface ComicPageView : ZoomView {
@private
  NSString* _file;
}
@property(nonatomic, copy) NSString* file;
- (id) initWithTapTarget:(id)target action:(SEL)action;
- (void) displayImage:(UIImage*)anImage;
@end

@implementation ComicPageView

@synthesize file=_file;

- (id) initWithTapTarget:(id)target action:(SEL)action {
  if ((self = [super init])) {
    self.alwaysBounceHorizontal = NO;
    self.alwaysBounceVertical = NO;
    
    UITapGestureRecognizer* recognizer = [[UITapGestureRecognizer alloc] initWithTarget:target action:action];
    [recognizer requireGestureRecognizerToFail:[[self gestureRecognizers] lastObject]];
    [self addGestureRecognizer:recognizer];
    [recognizer release];
  }
  return self;
}

- (void) displayImage:(UIImage*)anImage {
  if (anImage) {
    UIImageView* imageView = [[UIImageView alloc] initWithImage:anImage];
    [self setDisplayView:imageView];
    [imageView release];
  } else {
    [self setDisplayView:nil];
  }
}

- (void) dealloc {
  [_file release];
  
  [super dealloc];
}

@end

@implementation ComicViewController

@synthesize navigationBar=_navigationBar, navigationControl=_navigationControl, contentView=_contentView;

- (id) initWithComic:(Comic*)comic {
  DCHECK(comic.sqlRowID);
  if ((self = [super init])) {
    _comic = [comic retain];
    
    NSString* path = [LibraryConnection libraryRootPath];
    if (comic.collection) {
      Collection* collection = [[LibraryConnection mainConnection] fetchObjectOfClass:[Collection class]
                                                                         withSQLRowID:_comic.collection];
      path = [path stringByAppendingPathComponent:collection.name];
    }
    _path = [[path stringByAppendingPathComponent:_comic.name] copy];
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:_path]) {
      NSString* extension = [_path pathExtension];
      if (![extension caseInsensitiveCompare:@"pdf"]) {
        _type = kComicType_PDF;
        CGPDFDocumentRef document = CGPDFDocumentCreateWithURL((CFURLRef)[NSURL fileURLWithPath:_path]);
        if (document) {
          _contents = [[NSNumber alloc] initWithInteger:CGPDFDocumentGetNumberOfPages(document)];
          CGPDFDocumentRelease(document);
        }
      } else if (![extension caseInsensitiveCompare:@"zip"] || ![extension caseInsensitiveCompare:@"cbz"]) {
        _type = kComicType_ZIP;
        _contents = [[MiniZip alloc] initWithArchiveAtPath:_path];
      } else if (![extension caseInsensitiveCompare:@"rar"] || ![extension caseInsensitiveCompare:@"cbr"]) {
        _type = kComicType_RAR;
        _contents = [[UnRAR alloc] initWithArchiveAtPath:_path];
      }
    }
    if (!_contents) {
      LOG_ERROR(@"Failed loading comic at \"%@\"", path);
      [self release];
      return nil;
    }
    
    self.wantsFullScreenLayout = YES;
  }
  return self;
}

- (void) dealloc {
  [_navigationBar release];
  [_navigationControl release];
  [_contentView release];
  
  [_pageLabel release];
  [_documentView release];
  [_contents release];
  [_path release];
  [_comic release];
  
  [super dealloc];
}

- (void) saveState {
  NSInteger status = (_documentView.selectedPageIndex < _documentView.pageViews.count - 1 ? _documentView.selectedPageIndex : 0);
  if (status != _comic.status) {
    _comic.status = status;
    [[LibraryConnection mainConnection] updateObject:_comic];
  }
}

- (BOOL) navigationBar:(UINavigationBar*)navigationBar shouldPopItem:(UINavigationItem*)item {
  [self.parentViewController dismissModalViewControllerAnimated:YES];
  return YES;
}

- (void) documentView:(DocumentView*)documentView willShowPageView:(UIView*)view {
  CGImageRef imageRef = NULL;
  if (_type == kComicType_PDF) {
    CGPDFDocumentRef document = CGPDFDocumentCreateWithURL((CFURLRef)[NSURL fileURLWithPath:_path]);  // Don't keep CGPDFDocument around as it caches pages content heavily
    if (document) {
      CGPDFPageRef page = CGPDFDocumentGetPage(document, view.tag);
      if (page) {
        imageRef = CreateRenderedPDFPage(page, CGSizeMake(kMaxPageSize, kMaxPageSize), kImageScalingMode_AspectFit,
                                         [[UIColor whiteColor] CGColor]);
        LOG_VERBOSE(@"Loading page %i of %ix%i pixels resized to %ix%i pixels", view.tag,
                    (int)CGPDFPageGetBoxRect(page, kCGPDFMediaBox).size.width, (int)CGPDFPageGetBoxRect(page, kCGPDFMediaBox).size.height,
                    CGImageGetWidth(imageRef), CGImageGetHeight(imageRef));
      }
      CGPDFDocumentRelease(document);
    }
  } else {
    NSString* temp = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
    if ([_contents extractFile:[(ComicPageView*)view file] toPath:temp]) {
      NSData* data = [[NSData alloc] initWithContentsOfFile:temp];
      if (data) {
        UIImage* image = [[UIImage alloc] initWithData:data];
        if (image) {
          imageRef = [image CGImage];
          if ((CGImageGetWidth(imageRef) > kMaxPageSize) || (CGImageGetHeight(imageRef) > kMaxPageSize)) {
            imageRef = CreateScaledImage(imageRef, CGSizeMake(kMaxPageSize, kMaxPageSize), kImageScalingMode_AspectFit,
                                         [[UIColor blackColor] CGColor]);
          } else {
            CGImageRetain(imageRef);
          }
          LOG_VERBOSE(@"Loading page %i of %ix%i pixels resized to %ix%i pixels", view.tag,
                      (int)image.size.width, (int)image.size.height, CGImageGetWidth(imageRef), CGImageGetHeight(imageRef));
          [image release];
        }
        [data release];
      }
      [[NSFileManager defaultManager] removeItemAtPath:temp error:NULL];
    }
  }
  if (imageRef) {
    UIImage* image = [[UIImage alloc] initWithCGImage:imageRef];
    [(ComicPageView*)view displayImage:image];
    [image release];
    view.backgroundColor = [UIColor blackColor];
    CGImageRelease(imageRef);
  } else {
    view.backgroundColor = [UIColor redColor];
  }
#if TARGET_IPHONE_SIMULATOR
  usleep(250 * 1000);
#endif
}

- (void) documentView:(DocumentView*)documentView didHidePageView:(UIView*)view {
  [(ComicPageView*)view displayImage:nil];
  view.backgroundColor = nil;
}

- (void) documentViewDidReachFirstPage:(DocumentView*)documentView {
  [[UIApplication sharedApplication] setStatusBarHidden:NO withAnimation:UIStatusBarAnimationFade];
  
  [self.parentViewController dismissModalViewControllerAnimated:YES];
}

- (void) documentViewDidReachLastPage:(DocumentView*)documentView {
  [[UIApplication sharedApplication] setStatusBarHidden:NO withAnimation:UIStatusBarAnimationFade];
  
  [self.parentViewController dismissModalViewControllerAnimated:YES];
}

- (void) viewDidLoad {
  [super viewDidLoad];
  
  UINavigationItem* item = [[UINavigationItem alloc] initWithTitle:[_path lastPathComponent]];
  [_navigationBar pushNavigationItem:item animated:NO];
  [item release];
  _navigationBar.hidden = YES;
  _navigationControl.delegate = self;
  _navigationControl.continuous = NO;
  _navigationControl.margins = UIEdgeInsetsMake(0, 80, 20, 80);
  _navigationControl.thumbTintColor = [UIColor colorWithRed:0.8 green:0.8 blue:0.8 alpha:1.0];
  _navigationControl.overlayTintColor = [UIColor colorWithRed:0.7 green:0.7 blue:0.7 alpha:1.0];
  _navigationControl.hidden = YES;
  _contentView.backgroundColor = nil;
  
  _documentView = [[DocumentView alloc] initWithFrame:_contentView.bounds];
  _documentView.delegate = self;
  _documentView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  [_contentView addSubview:_documentView];
  
  _pageLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 140, 20)];
  _pageLabel.font = [UIFont boldSystemFontOfSize:18];
  _pageLabel.textColor = [UIColor whiteColor];
  _pageLabel.textAlignment = UITextAlignmentCenter;
  _pageLabel.backgroundColor = nil;
  _pageLabel.opaque = NO;
}

- (void) viewDidUnload {
  [super viewDidUnload];
  
  [_pageLabel release];
  [_documentView release];
  
  self.navigationBar = nil;
  self.navigationControl = nil;
  self.contentView = nil;
}

- (void) _tapAction:(UITapGestureRecognizer*)recognizer {
  if (recognizer.state == UIGestureRecognizerStateEnded) {
    CGRect bounds = recognizer.view.bounds;
    CGPoint location = [recognizer locationInView:recognizer.view];
    // Left margin
    if (location.x <= bounds.size.width * kLeftZoneRatio) {
      [_documentView goToPreviousPage:NO];
    }
    // Right margin
    else if (location.x >= bounds.size.width * kRightZoneRatio) {
      [_documentView goToNextPage:NO];
    }
    // Center
    else {
      if ([[UIApplication sharedApplication] isStatusBarHidden]) {
        [[UIApplication sharedApplication] setStatusBarHidden:NO];
        _navigationBar.hidden = NO;
        _navigationControl.hidden = NO;
      } else {
        [[UIApplication sharedApplication] setStatusBarHidden:YES];
        _navigationBar.hidden = YES;
        _navigationControl.hidden = YES;
      }
    }
  }
}

- (void) viewWillAppear:(BOOL)animated {
  [super viewWillAppear:animated];
  
  NSMutableArray* array = [[NSMutableArray alloc] init];
  if (_type == kComicType_PDF) {
    NSUInteger count = [(NSNumber*)_contents integerValue];
    for (NSUInteger i = 0; i < count; ++i) {
      ComicPageView* view = [[ComicPageView alloc] initWithTapTarget:self action:@selector(_tapAction:)];
      view.tag = i + 1;
      [array addObject:view];
      [view release];
    }
  } else {
    [_contents setSkipInvisibleFiles:YES];
    NSUInteger index = 0;
    for (NSString* file in [[_contents retrieveFileList] sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)]) {
      NSString* extension = [file pathExtension];
      if (![extension caseInsensitiveCompare:@"jpg"] || ![extension caseInsensitiveCompare:@"jpeg"] ||
        ![extension caseInsensitiveCompare:@"png"] || ![extension caseInsensitiveCompare:@"gif"]) {
        ComicPageView* view = [[ComicPageView alloc] initWithTapTarget:self action:@selector(_tapAction:)];
        view.tag = ++index;
        view.file = file;
        [array addObject:view];
        [view release];
      }
    }
  }
  [_documentView setPageViews:array initialPageIndex:MAX(_comic.status, 0)];
  _navigationControl.numberOfPages = array.count;
  _navigationControl.numberOfMarkers = MIN(array.count, 50);
  _navigationControl.currentPage = _documentView.selectedPageIndex;
  [array release];
  
  [[UIApplication sharedApplication] setStatusBarHidden:YES
                                          withAnimation:(animated ? UIStatusBarAnimationFade : UIStatusBarAnimationNone)];
}

- (void) viewWillDisappear:(BOOL)animated {
  [super viewWillDisappear:animated];
  
  [self saveState];
}

- (void) viewDidDisappear:(BOOL)animated {
  [super viewDidDisappear:animated];
  
  _documentView.pageViews = nil;
}

- (BOOL) shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
  return YES;
}

- (void) documentViewDidChangePage:(DocumentView*)documentView {
  _navigationControl.currentPage = _documentView.selectedPageIndex;
}

- (UIView*) navigationControlOverlayViewForCurrentPage:(NavigationControl*)control {
  _pageLabel.text = [NSString stringWithFormat:NSLocalizedString(@"LABEL_FORMAT", nil), _navigationControl.currentPage + 1,
                                               _navigationControl.numberOfPages];
  return _pageLabel;
}

- (IBAction) selectPage:(id)sender {
  _documentView.selectedPageIndex = _navigationControl.currentPage;
}

@end
