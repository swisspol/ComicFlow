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

#import <QuartzCore/QuartzCore.h>
#if TARGET_IPHONE_SIMULATOR
#import <unistd.h>
#endif

#import "AppDelegate.h"
#import "ComicViewController.h"
#import "ZoomView.h"
#import "MiniZip.h"
#import "UnRAR.h"
#import "ImageDecompression.h"

#define kMaxPageSize 1500.0
#define kLeftZoneRatio 0.2
#define kRightZoneRatio 0.8
#define kDoubleTapZoomRatio 1.5

typedef enum { kPositionCenter, kPositionLeftEdge, kPositionRightEdge } ContentPos;

@interface ComicDocumentView : DocumentView
@end

@interface ComicPageView : ZoomView {
@private
  NSString* _file;
  BOOL _contentIsLandscape;
}
@property(nonatomic, copy) NSString* file;
@property(nonatomic) BOOL contentIsLandscape;
- (id) initWithTarget:(id)target tapAction:(SEL)tapAction swipeLeftAction:(SEL)swipeLeftAction swipeRightAction:(SEL)swipeRightAction;
- (void) displayImage:(UIImage*)anImage;
- (void) positionContentAt:(ContentPos)position;
@end

@implementation ComicDocumentView

// If we are zoomed out on a page, make sure the DocumentView built-in pan gesture recognizer is allowed to work simultaneously with the UIScrollView native one
// This is required since iOS 8
- (BOOL) gestureRecognizer:(UIGestureRecognizer*)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer*)otherGestureRecognizer {
  if ([otherGestureRecognizer isKindOfClass:NSClassFromString(@"UIScrollViewPanGestureRecognizer")]) {
    ComicPageView* pageView = (ComicPageView*)self.selectedPageView;
    if (pageView) {
      if (pageView.zoomScale < pageView.minimumZoomScale) {
        return YES;
      }
    } else {
      XLOG_DEBUG_UNREACHABLE();
    }
  }
  return NO;
}

@end

@implementation ComicPageView

@synthesize file=_file;
@synthesize contentIsLandscape=_contentIsLandscape;

- (id) initWithTarget:(id)target tapAction:(SEL)tapAction swipeLeftAction:(SEL)swipeLeftAction swipeRightAction:(SEL)swipeRightAction {
  if ((self = [super init])) {
    self.displayMode = kZoomViewDisplayMode_FitVertically;
    self.doubleTapZoom = kDoubleTapZoomRatio;
    
    self.alwaysBounceHorizontal = NO;
    self.alwaysBounceVertical = NO;
    self.bounces = NO;

    UITapGestureRecognizer* recognizer = [[UITapGestureRecognizer alloc] initWithTarget:target action:tapAction];
    [recognizer requireGestureRecognizerToFail:[[self gestureRecognizers] lastObject]];
    [self addGestureRecognizer:recognizer];
    [recognizer release];

    UISwipeGestureRecognizer* swipeLeftRecognizer = [[UISwipeGestureRecognizer alloc] initWithTarget:target action:swipeLeftAction];
    swipeLeftRecognizer.direction = UISwipeGestureRecognizerDirectionLeft;
    [swipeLeftRecognizer requireGestureRecognizerToFail:[[self gestureRecognizers] lastObject]];
    [self addGestureRecognizer:swipeLeftRecognizer];
    [swipeLeftRecognizer release];

    UISwipeGestureRecognizer* swipeRightRecognizer = [[UISwipeGestureRecognizer alloc] initWithTarget:target action:swipeRightAction];
    swipeRightRecognizer.direction = UISwipeGestureRecognizerDirectionRight;
    [swipeRightRecognizer requireGestureRecognizerToFail:[[self gestureRecognizers] lastObject]];
    [self addGestureRecognizer:swipeRightRecognizer];
    [swipeRightRecognizer release];
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

- (void) positionContentAt:(ContentPos)position {
  CGFloat delta = (self.contentSize.width - self.bounds.size.width);

  // Always center portrait content
  if ((position == kPositionCenter) || (self.contentIsLandscape == NO)) {
    [self setContentOffset:CGPointMake(delta / 2, 0) animated:NO];
  } else if (position == kPositionRightEdge) {
    [self setContentOffset:CGPointMake(delta, 0) animated:NO];
  } else {
    [self setContentOffset:CGPointMake(0, 0) animated:NO];
  }
}

@end

@implementation ComicViewController

@synthesize navigationBar=_navigationBar, navigationControl=_navigationControl, contentView=_contentView;

- (id) initWithComic:(Comic*)comic {
  [CATransaction begin];
  [[AppDelegate sharedInstance] showSpinnerWithMessage:NSLocalizedString(@"SPINNER_MESSAGE", nil) fullScreen:NO animated:YES];
  [CATransaction flush];
  [CATransaction commit];
  
  XLOG_DEBUG_CHECK(comic.sqlRowID);
  if ((self = [super init])) {
    _comic = [comic retain];
    _path = [[[LibraryConnection mainConnection] pathForComic:_comic] copy];
    
    _previousPageIndex = -1;
    _previousPageView = nil;

    if ([[NSFileManager defaultManager] fileExistsAtPath:_path]) {
      NSString* extension = [_path pathExtension];
      if (![extension caseInsensitiveCompare:@"pdf"]) {
        _type = kComicType_PDF;
        CGPDFDocumentRef document = CGPDFDocumentCreateWithURL((CFURLRef)[NSURL fileURLWithPath:_path]);
        if (document) {
          _contents = [[NSNumber alloc] initWithInteger:CGPDFDocumentGetNumberOfPages(document)];
          CGPDFDocumentRelease(document);
        }
      } else if (![extension caseInsensitiveCompare:@"zip"] || ![extension caseInsensitiveCompare:@"cbz"] || ![extension caseInsensitiveCompare:@"rar"] || ![extension caseInsensitiveCompare:@"cbr"]) {
        _type = kComicType_ZIP;
        _contents = [[MiniZip alloc] initWithArchiveAtPath:_path];
        if (_contents == nil) {
          _type = kComicType_RAR;
          _contents = [[UnRAR alloc] initWithArchiveAtPath:_path];
        }
      }
    }
    if (!_contents) {
      XLOG_ERROR(@"Failed loading comic at \"%@\"", _path);
      [self release];
      return nil;
    }
    
    self.edgesForExtendedLayout = UIRectEdgeAll;
    self.extendedLayoutIncludesOpaqueBars = YES;

    NSString* type = @"";
    switch (_type) {
      case kComicType_PDF: type = @"PDF"; break;
      case kComicType_ZIP: type = @"ZIP"; break;
      case kComicType_RAR: type = @"RAR"; break;
    }
    [[AppDelegate sharedDelegate] logEvent:@"comic.read" withParameterName:@"type" value:type];
  }
  return self;
}

- (void) dealloc {
  _documentView.delegate = nil;
  _navigationControl.delegate = nil;
  
  [_navigationBar release];
  [_navigationControl release];
  [_contentView release];
  
  [_pageLabel release];
  [_documentView release];
  [_contents release];
  [_path release];
  [_comic release];
  
  [[AppDelegate sharedInstance] hideSpinner:NO];  // Just in case
  
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
  if ([self respondsToSelector:@selector(presentingViewController)]) {
    [self.presentingViewController dismissModalViewControllerAnimated:YES];
  } else {
    [self.parentViewController dismissModalViewControllerAnimated:YES];
  }
  return YES;
}

- (void) documentView:(DocumentView*)documentView willShowPageView:(UIView*)view {
  CGFloat maxPageSize = kMaxPageSize * [[UIScreen mainScreen] scale];
  CGImageRef imageRef = NULL;
  if (_type == kComicType_PDF) {
    CGPDFDocumentRef document = CGPDFDocumentCreateWithURL((CFURLRef)[NSURL fileURLWithPath:_path]);  // Don't keep CGPDFDocument around as it caches pages content heavily
    if (document) {
      CGPDFPageRef page = CGPDFDocumentGetPage(document, view.tag);
      if (page) {
        imageRef = CreateCGImageFromPDFPage(page, CGSizeMake(maxPageSize, maxPageSize), NO);
      }
      CGPDFDocumentRelease(document);
    }
  } else {
    NSString* temp = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
    if ([_contents extractFile:[(ComicPageView*)view file] toPath:temp]) {
      NSData* data = [[NSData alloc] initWithContentsOfFile:temp];
      if (data) {
        NSString* extension = [[(ComicPageView*)view file] pathExtension];
        imageRef = CreateCGImageFromFileData(data, extension, CGSizeMake(maxPageSize, maxPageSize), NO);
        [data release];
      }
      [[NSFileManager defaultManager] removeItemAtPath:temp error:NULL];
    }
  }
  if (imageRef) {
    UIImage* image = [[UIImage alloc] initWithCGImage:imageRef];
    [(ComicPageView*)view displayImage:image];
    ((ComicPageView*)view).contentIsLandscape = (image.size.width > image.size.height);
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
  if ([self respondsToSelector:@selector(presentingViewController)]) {
    [self.presentingViewController dismissModalViewControllerAnimated:YES];
  } else {
    [self.parentViewController dismissModalViewControllerAnimated:YES];
  }
}

- (void) documentViewDidReachLastPage:(DocumentView*)documentView {
  if ([self respondsToSelector:@selector(presentingViewController)]) {
    [self.presentingViewController dismissModalViewControllerAnimated:YES];
  } else {
    [self.parentViewController dismissModalViewControllerAnimated:YES];
  }
}

- (void) viewDidLoad {
  [super viewDidLoad];
  
  self.view.clipsToBounds = YES;  // Required on iOS 7
  
  UINavigationItem* item = [[UINavigationItem alloc] initWithTitle:[_path lastPathComponent]];
  [_navigationBar pushNavigationItem:item animated:NO];
  [item release];
  _navigationBar.hidden = YES;
  _navigationControl.delegate = self;
  _navigationControl.continuous = NO;
  _navigationControl.margins = UIEdgeInsetsMake(0, 80, 20, 80);
  _navigationControl.hidden = YES;
  _contentView.backgroundColor = nil;
  
  _documentView = [[ComicDocumentView alloc] initWithFrame:_contentView.bounds];
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
  
  _documentView.delegate = nil;
  _navigationControl.delegate = nil;
  
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
    CGFloat xLoc = location.x - bounds.origin.x;

    if (xLoc <= bounds.size.width * kLeftZoneRatio) { // Left margin
      [_documentView goToPreviousPage:YES];
	}
    else if (xLoc >= bounds.size.width * kRightZoneRatio) { // Right margin
      [_documentView goToNextPage:YES];
    }
    else { // Center
      [self toggleNavigation];
    }
  }
}

- (void) _swipeLeftAction:(UITapGestureRecognizer*)recognizer {
  if (recognizer.state == UIGestureRecognizerStateEnded) {
    [_documentView goToNextPage:YES];
  }
}

- (void) _swipeRightAction:(UITapGestureRecognizer*)recognizer {
  if (recognizer.state == UIGestureRecognizerStateEnded) {
    [_documentView goToPreviousPage:YES];
  }
}

- (void) documentViewDidEndSwiping:(DocumentView*)documentView
{
}

- (void) documentViewWillChangePage:(DocumentView*)documentView {
  // Make a note of where we were...
  _previousPageIndex = _documentView.selectedPageIndex;
  _previousPageView = _documentView.selectedPageView;
}

- (void) documentViewDidChangePage:(DocumentView*)documentView {
  _navigationControl.currentPage = _documentView.selectedPageIndex;

  if (_documentView.pageViews) {
    [[AppDelegate sharedDelegate] logPageView];

    // Adjust the positioning of the page we are about to display
    ComicPageView* pageView = (ComicPageView*)_documentView.selectedPageView;
    if (pageView.contentIsLandscape == NO) {
      [pageView positionContentAt:kPositionCenter];
    }
	else if (_previousPageView != nil)
	{
      if (_previousPageIndex < documentView.selectedPageIndex) {
        // Just moved to a later page
        [pageView positionContentAt:kPositionLeftEdge];
      } else {
        // Just moved to an earlier page
        [pageView positionContentAt:kPositionRightEdge];
	  }
    }
  }
}

- (void) documentViewDidDisplayCurrentPage:(DocumentView*)documentView animated:(BOOL)animated {
  if (_previousPageView != nil)
  {
    // Adjust the positioning of the page we just left
    if (_previousPageIndex < documentView.selectedPageIndex) {
      // Just moved to a later page
      [(ComicPageView*)_previousPageView positionContentAt:kPositionRightEdge];
    } else {
      // Just moved to an earlier page
      [(ComicPageView*)_previousPageView positionContentAt:kPositionLeftEdge];
    }

    // Reset things so we won't mess up if this gets called without a preceding WillChange
    _previousPageIndex = -1;
    _previousPageView = nil;
  }
}

- (BOOL) shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
  return YES;
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation {
  // Try to fix the position of the pages before and after the current one
  NSArray* allViews = _documentView.pageViews;
  for (ComicPageView* pageView in allViews) {
    if (pageView.tag < _documentView.selectedPageIndex) {
      [pageView positionContentAt:kPositionRightEdge];
    }
    else if (pageView.tag > _documentView.selectedPageIndex) {
      [pageView positionContentAt:kPositionLeftEdge];
    }
  }
}

- (void) toggleNavigation {
  // Make sure we're still active!
  if (_documentView.pageViews != nil) {
    if (_navigationBar.hidden == YES) {
      _navigationBar.hidden = NO;
      _navigationControl.hidden = NO;
    } else {
      _navigationBar.hidden = YES;
      _navigationControl.hidden = YES;
    }
  }
}

- (void) viewWillAppear:(BOOL)animated {
  [super viewWillAppear:animated];
  
  NSMutableArray* array = [[NSMutableArray alloc] init];
  if (_type == kComicType_PDF) {
    NSUInteger count = [(NSNumber*)_contents integerValue];
    for (NSUInteger i = 0; i < count; ++i) {
      ComicPageView* view = [[ComicPageView alloc] initWithTarget:self
														tapAction:@selector(_tapAction:)
												  swipeLeftAction:@selector(_swipeLeftAction:)
												 swipeRightAction:@selector(_swipeRightAction:)];
      view.tag = i + 1;
      [array addObject:view];
      [view release];
    }
  } else {
    [_contents setSkipInvisibleFiles:YES];
    NSUInteger index = 0;
    for (NSString* file in [[_contents retrieveFileList] sortedArrayUsingSelector:@selector(localizedStandardCompare:)]) {
      if (IsImageFileExtensionSupported([file pathExtension])) {
        ComicPageView* view = [[ComicPageView alloc] initWithTarget:self
														  tapAction:@selector(_tapAction:)
													swipeLeftAction:@selector(_swipeLeftAction:)
												   swipeRightAction:@selector(_swipeRightAction:)];
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
  if (array.count == 0) {
    _navigationBar.hidden = NO;
    _navigationControl.hidden = NO;
  }
  [array release];
}

- (void) viewDidAppear:(BOOL)animated {
  [super viewDidAppear:animated];
  
  [[AppDelegate sharedInstance] hideSpinner:YES];
}

- (void) viewDidDisappear:(BOOL)animated {
  [super viewDidDisappear:animated];
  
  _documentView.pageViews = nil;
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
