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

#import <unistd.h>
#import <QuartzCore/QuartzCore.h>

#import "Flurry.h"

#import "LibraryViewController.h"
#import "ComicViewController.h"
#import "AppDelegate.h"
#import "Defaults.h"
#import "Extensions_Foundation.h"
#import "Extensions_UIKit.h"
#import "NetReachability.h"
#import "Logging.h"

#define kGridMargin 10.0
#define kGridMarginExtra_Portrait 2.0
#define kGridMarginExtra_Landscape 2.0
#define kItemVerticalSpacing 8.0
#define kItemHorizontalSpacing_Portrait 17.0
#define kItemHorizontalSpacing_Landscape 9.0

#define kNewImageX 0.0
#define kNewImageY 0.0
#define kNewImageWidth 65.0
#define kNewImageHeight 65.0

#define kRibbonImageX 58.0
#define kRibbonImageY 0.0
#define kRibbonImageWidth 60.0
#define kRibbonImageHeight 70.0

#define kLaunchCountBeforeRating 10
#define kShowRatingDelay 1.0

#if __DISPLAY_THUMBNAILS_IN_BACKGROUND__
@interface ThumbnailView : UIView
#else
@interface ThumbnailView : UIImageView
#endif
{
@private
  UIView* _noteView;
  UIView* _ribbonView;
}
@property(nonatomic, assign) UIView* noteView;
@property(nonatomic, assign) UIView* ribbonView;
@end

@interface LibraryViewController ()
- (void) _reloadCurrentCollection;
- (void) _presentComic:(Comic*)comic;
- (void) _setCurrentCollection:(Collection*)collection;
@end

@implementation ThumbnailView

@synthesize noteView=_noteView, ribbonView=_ribbonView;

@end

@implementation LibraryViewController

@synthesize gridView=_gridView, navigationBar=_navigationBar, segmentedControl=_segmentedControl, menuView=_menuView,
            progressView=_progressView, markReadButton=_markReadButton, markNewButton=_markNewButton, updateButton=_updateButton,
            forceUpdateButton=_forceUpdateButton, serverSwitch=_serverSwitch, addressLabel=_addressLabel,
            infoLabel=_infoLabel, versionLabel=_versionLabel, dimmingSwitch=_dimmingSwitch;

- (void) _updateStatistics {
  NSDictionary* attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:[LibraryConnection libraryDatabasePath]
                                                                              error:nil];
  _infoLabel.text = [NSString stringWithFormat:NSLocalizedString(@"INFO_FORMAT", nil),
                                               [[LibraryConnection mainConnection] countObjectsOfClass:[Comic class]],
                                               [[LibraryConnection mainConnection] countObjectsOfClass:[Collection class]],
                                               ceil((double)[attributes fileSize] / (1024.0 * 1024.0))];
}

- (void) _updateServer {
  WebServer* server = [(AppDelegate*)[AppDelegate sharedInstance] webServer];
  _serverSwitch.on = server ? YES : NO;
  if (server) {
    NSString* ipAddress = [[UIDevice currentDevice] currentWiFiAddress];
    _addressLabel.text = ipAddress ? [NSString stringWithFormat:NSLocalizedString(@"ADDRESS_FORMAT", nil), ipAddress, server.port]
                                   : NSLocalizedString(@"ADDRESS_UNAVAILABLE", nil);
    _addressLabel.textColor = [UIColor darkGrayColor];
  } else {
    _addressLabel.text = NSLocalizedString(@"ADDRESS_UNAVAILABLE", nil);
    _addressLabel.textColor = [UIColor grayColor];
  }
}

#if __DISPLAY_THUMBNAILS_IN_BACKGROUND__

// Called from main thread or display thread
static void __DisplayQueueApplierFunction(const void* key, const void* value, void* context) {
  ThumbnailView* view = (ThumbnailView*)key;
  DatabaseObject* item = (DatabaseObject*)value;
  void** params = (void**)context;
  UIImage* image = nil;
#if __STORE_THUMBNAILS_IN_DATABASE__
  DatabaseSQLRowID rowID = [(id)item thumbnail];
  if (rowID > 0) {
    Thumbnail* thumnail = [(LibraryConnection*)params[1] fetchObjectOfClass:[Thumbnail class] withSQLRowID:rowID];
    image = [[UIImage alloc] initWithData:thumnail.data];
  }
#else
  NSString* name = [(id)item thumbnail];
  if (name) {
    NSString* path = [(NSString*)params[1] stringByAppendingPathComponent:name];
    image = [[UIImage alloc] initWithContentsOfFile:path];
  }
#endif
  if (image) {
    if (params[0]) {
      [CATransaction begin];
    }
    view.layer.contents = (id)[image CGImage];
    if (params[0]) {
      [CATransaction commit];
    }
    [image release];
  }
}

// Called from main thread or display thread
- (void) _processDisplayQueue:(BOOL)inBackground {
#if __STORE_THUMBNAILS_IN_DATABASE__
  void** params[] = {inBackground ? (void*)self : NULL,
                     inBackground ? (void*)_displayConnection : (void*)[LibraryConnection mainConnection]};
#else
  void** params[] = {inBackground ? (void*)self : NULL, [LibraryConnection libraryApplicationDataPath]};
#endif
  while (1) {
    CFDictionaryRef dictionary = NULL;
    
    pthread_mutex_lock(&_displayMutex);
    if (CFArrayGetCount(_displayQueue)) {
      dictionary = CFRetain(CFArrayGetValueAtIndex(_displayQueue, 0));
      CFArrayRemoveValueAtIndex(_displayQueue, 0);
    }
    pthread_mutex_unlock(&_displayMutex);
    
    if (dictionary) {
      NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
      CFDictionaryApplyFunction(dictionary, __DisplayQueueApplierFunction, params);
      [pool release];
      CFRelease(dictionary);
    } else {
      break;
    }
  }
}

// Called from display thread
static void __DisplayQueueCallBack(void* info) {
  [(LibraryViewController*)info _processDisplayQueue:YES];
}

- (void) _displayQueueThread:(id)argument {
  _displayRunLoop = CFRunLoopGetCurrent();
  CFRunLoopAddSource(_displayRunLoop, _displaySource, kCFRunLoopCommonModes);
  CFRunLoopRun();
}

#endif

- (id) initWithWindow:(UIWindow*)window {
  if ((self = [super init])) {
    _window = window;
    
    _collectionImage = [[UIImage alloc] initWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"Collection" ofType:@"png"]];
    CHECK(_collectionImage);
    _newImage = [[UIImage alloc] initWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"New" ofType:@"png"]];
    CHECK(_newImage);
    _ribbonImage = [[UIImage alloc] initWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"Ribbon" ofType:@"png"]];
    CHECK(_ribbonImage);
    _comicImage = [[UIImage alloc] initWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"Comic" ofType:@"png"]];
    CHECK(_comicImage);
    
    DatabaseSQLRowID collectionID = [[NSUserDefaults standardUserDefaults] integerForKey:kDefaultKey_CurrentCollection];
    if (collectionID) {
      _currentCollection = [[[LibraryConnection mainConnection] fetchObjectOfClass:[Collection class] withSQLRowID:collectionID] retain];
    }
    DatabaseSQLRowID comicID = [[NSUserDefaults standardUserDefaults] integerForKey:kDefaultKey_CurrentComic];
    if (comicID) {
      _currentComic = [[[LibraryConnection mainConnection] fetchObjectOfClass:[Comic class] withSQLRowID:comicID] retain];
    }
    
#if __DISPLAY_THUMBNAILS_IN_BACKGROUND__
#if __STORE_THUMBNAILS_IN_DATABASE__
    _displayConnection = [[LibraryConnection alloc] initWithDatabaseAtPath:[LibraryConnection libraryDatabasePath]];
    CHECK(_displayConnection);
#endif
    pthread_mutexattr_t attributes;
    pthread_mutexattr_init(&attributes);
    pthread_mutexattr_settype(&attributes, PTHREAD_MUTEX_RECURSIVE);
    pthread_mutex_init(&_displayMutex, &attributes);
    pthread_mutexattr_destroy(&attributes);
    _displayQueue = CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);
    CFRunLoopSourceContext context = {0, self, NULL, NULL, NULL, NULL, NULL, NULL, NULL, __DisplayQueueCallBack};
    _displaySource = CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &context);
    [NSThread detachNewThreadSelector:@selector(_displayQueueThread:) toTarget:self withObject:nil];
    do {
      usleep(100000);  // Make sure background thread has started
    } while (_displayRunLoop == NULL);
#endif
  }
  return self;
}

- (BOOL) canBecomeFirstResponder {
  return YES;
}

- (BOOL) shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
  return YES;
}

- (void) _toggleMenu:(id)sender {
  if (_menuController.popoverVisible) {
    [_menuController dismissPopoverAnimated:YES];
  } else {
    [self _updateServer];
    [self _updateStatistics];
    [_menuController presentPopoverFromBarButtonItem:sender permittedArrowDirections:UIPopoverArrowDirectionUp animated:YES];
  }
}

- (void) _tap:(UITapGestureRecognizer*)recognizer {
  if (recognizer.state == UIGestureRecognizerStateEnded) {
    DatabaseObject* item = [_gridView itemAtLocation:[recognizer locationInView:_gridView] view:NULL];
    if ([item isKindOfClass:[Comic class]]) {
      [self _presentComic:(Comic*)item];
    } else if ([item isKindOfClass:[Collection class]]) {
      [self gridViewDidUpdateScrollingAmount:nil];
      [self _setCurrentCollection:(Collection*)item];
    }
  }
}

- (void) _updateThumbnailViewForItem:(DatabaseObject*)item {
  ThumbnailView* view = (ThumbnailView*)[_gridView viewForItem:item];
  if (view && !view.hidden) {
    NSInteger status = [(id)item status];
    [view.noteView removeFromSuperview];
    [view.ribbonView removeFromSuperview];
    if (status > 0) {
      UIImageView* subview = [[UIImageView alloc] initWithImage:_ribbonImage];
      subview.frame = CGRectMake(kRibbonImageX, kRibbonImageY, kRibbonImageWidth, kRibbonImageHeight);
      [view addSubview:subview];
      [subview release];
      view.noteView = nil;
      view.ribbonView = subview;
    } else if (status < 0) {
      UIImageView* subview = [[UIImageView alloc] initWithImage:_newImage];
      subview.frame = CGRectMake(kNewImageX, kNewImageY, kNewImageWidth, kNewImageHeight);
      [view addSubview:subview];
      [subview release];
      view.noteView = subview;
      view.ribbonView = nil;
    } else {
      view.noteView = nil;
      view.ribbonView = nil;
    }
  }
}

- (void) _setStatus:(int)status {
  if (_selectedItem) {
    if ([_selectedItem isKindOfClass:[Comic class]]) {
      [(Comic*)_selectedItem setStatus:status];
      [[LibraryConnection mainConnection] updateObject:_selectedItem];
      [self _updateThumbnailViewForItem:_selectedItem];
      if ([[NSUserDefaults standardUserDefaults] integerForKey:kDefaultKey_SortingMode] == kSortingMode_ByStatus) {
        [self _reloadCurrentCollection];
      }
    } else {
      [[LibraryConnection mainConnection] updateStatus:status forComicsInCollection:(Collection*)_selectedItem];
      [[LibraryConnection mainConnection] refetchObject:_selectedItem];
      [self _updateThumbnailViewForItem:_selectedItem];
    }
    [_selectedItem release];
    _selectedItem = nil;
  } else {
    DNOT_REACHED();
  }
}

- (void) _setRead:(id)sender {
  [self _setStatus:0];
}

- (void) _setNew:(id)sender {
  [self _setStatus:-1];
}

- (void) _delete:(id)sender {
  if (_selectedItem) {
    if ([_selectedItem isKindOfClass:[Comic class]]) {
      NSError* error = nil;
      if ([[NSFileManager defaultManager] removeItemAtPath:[[LibraryConnection mainConnection] pathForComic:(Comic*)_selectedItem] error:&error]) {
        [(AppDelegate*)[AppDelegate sharedInstance] updateLibrary];
      } else {
        LOG_ERROR(@"Failed deleting comic \"%@\": %@", [(Comic*)_selectedItem name], error);
      }
    } else {
      NSError* error = nil;
      if ([[NSFileManager defaultManager] removeItemAtPath:[[LibraryConnection mainConnection] pathForCollection:(Collection*)_selectedItem] error:&error]) {
        [(AppDelegate*)[AppDelegate sharedInstance] updateLibrary];
      } else {
        LOG_ERROR(@"Failed deleting comic \"%@\": %@", [(Collection*)_selectedItem name], error);
      }
    }
    [_selectedItem release];
    _selectedItem = nil;
  } else {
    DNOT_REACHED();
  }
}

- (void) _press:(UILongPressGestureRecognizer*)recognizer {
  if (recognizer.state == UIGestureRecognizerStateBegan) {
    [_selectedItem release];
    _selectedItem = [[_gridView itemAtLocation:[recognizer locationInView:_gridView] view:NULL] retain];
    if (_selectedItem) {
      NSInteger status = [(id)_selectedItem status];
      NSMutableArray* items = [[NSMutableArray alloc] init];
      if ([_selectedItem isKindOfClass:[Comic class]]) {
        if (status != 0) {
          UIMenuItem* item = [[UIMenuItem alloc] initWithTitle:NSLocalizedString(@"MARK_READ", nil) action:@selector(_setRead:)];
          [items addObject:item];
          [item release];
        }
        if (status >= 0) {
          UIMenuItem* item = [[UIMenuItem alloc] initWithTitle:NSLocalizedString(@"MARK_NEW", nil) action:@selector(_setNew:)];
          [items addObject:item];
          [item release];
        }
        if (1) {
          UIMenuItem* item = [[UIMenuItem alloc] initWithTitle:NSLocalizedString(@"DELETE", nil) action:@selector(_delete:)];
          [items addObject:item];
          [item release];
        }
      } else {
        if (status != 0) {
          UIMenuItem* item = [[UIMenuItem alloc] initWithTitle:NSLocalizedString(@"MARK_ALL_READ", nil) action:@selector(_setRead:)];
          [items addObject:item];
          [item release];
        }
        if (status >= 0) {
          UIMenuItem* item = [[UIMenuItem alloc] initWithTitle:NSLocalizedString(@"MARK_ALL_NEW", nil) action:@selector(_setNew:)];
          [items addObject:item];
          [item release];
        }
        if (1) {
          UIMenuItem* item = [[UIMenuItem alloc] initWithTitle:NSLocalizedString(@"DELETE_ALL", nil) action:@selector(_delete:)];
          [items addObject:item];
          [item release];
        }
      }
      CGPoint location = [recognizer locationInView:_gridView];
      [[UIMenuController sharedMenuController] setMenuItems:items];
      [[UIMenuController sharedMenuController] setTargetRect:CGRectMake(location.x, location.y, 1.0, 1.0) inView:_gridView];
      [[UIMenuController sharedMenuController] setMenuVisible:YES animated:YES];
      [items release];
    }
  }
}

- (void) viewDidLoad {
  [super viewDidLoad];
  
  self.view.backgroundColor = nil;  // Can't do this in Interface Builder
  
  _gridView.delegate = self;
  UITapGestureRecognizer* tapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_tap:)];
  [_gridView addGestureRecognizer:tapRecognizer];
  [tapRecognizer release];
  UILongPressGestureRecognizer* pressRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(_press:)];
  pressRecognizer.minimumPressDuration = 0.3;  // Default is 0.5
  [_gridView addGestureRecognizer:pressRecognizer];
  [pressRecognizer release];
  
  UINavigationItem* item = [_navigationBar.items objectAtIndex:0];
  UIBarButtonItem* rightButton = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"Action.png"]
                                                                  style:UIBarButtonItemStyleBordered
                                                                 target:self
                                                                 action:@selector(_toggleMenu:)];
  item.rightBarButtonItem = rightButton;
  [rightButton release];
  
  UIViewController* viewController = [[UIViewController alloc] init];
  viewController.view = _menuView;
  _menuController = [[UIPopoverController alloc] initWithContentViewController:viewController];
  _menuController.popoverContentSize = _menuView.frame.size;
  [viewController release];
  
  _infoLabel.text = nil;
  _versionLabel.text = [NSString stringWithFormat:NSLocalizedString(@"VERSION_FORMAT", nil),
                                                  [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"],
                                                  [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"]];
  _progressView.progress = 1.0;
  BOOL updating = [[LibraryUpdater sharedUpdater] isUpdating];
  _markReadButton.enabled = !updating;
  _markNewButton.enabled = !updating;
  _updateButton.enabled = !updating;
  _forceUpdateButton.enabled = !updating;
  _dimmingSwitch.on = [(AppDelegate*)[AppDelegate sharedInstance] isScreenDimmed];
}

- (void) viewDidUnload {
  [super viewDidUnload];
  
  [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidBecomeActiveNotification object:nil];
  
  _window.layer.contents = nil;
  
  self.gridView = nil;
  self.navigationBar = nil;
  self.segmentedControl = nil;
  self.menuView = nil;
  self.progressView = nil;
  self.markReadButton = nil;
  self.markNewButton = nil;
  self.updateButton = nil;
  self.forceUpdateButton = nil;
  self.serverSwitch = nil;
  self.addressLabel = nil;
  self.infoLabel = nil;
  self.versionLabel = nil;
  self.dimmingSwitch = nil;
  
  [_menuController release];
  _menuController = nil;
}

- (void) _reloadCurrentCollection {
  LOG_VERBOSE(@"Reloading current collection");
  NSInteger scrolling = _currentCollection ? _currentCollection.scrolling
                                           : [[NSUserDefaults standardUserDefaults] integerForKey:kDefaultKey_RootScrolling];
  if ((scrolling < 0) || (scrolling == NSNotFound)) {
    scrolling = 0;
  }
  
  NSArray* items = nil;
  switch ([[NSUserDefaults standardUserDefaults] integerForKey:kDefaultKey_SortingMode]) {  // Setting "selectedSegmentIndex" will call the action
    
    case kSortingMode_ByName: {
      _segmentedControl.selectedSegmentIndex = 1;
      items = [[LibraryConnection mainConnection] fetchAllComicsByName];
      break;
    }
    
    case kSortingMode_ByDate: {
      _segmentedControl.selectedSegmentIndex = 2;
      items = [[LibraryConnection mainConnection] fetchAllComicsByDate];
      break;
    }
    
    case kSortingMode_ByStatus: {
      _segmentedControl.selectedSegmentIndex = 3;
      items = [[LibraryConnection mainConnection] fetchAllComicsByStatus];
      break;
    }
    
    default: {  // kSortingMode_ByCollection
      _segmentedControl.selectedSegmentIndex = 0;
      if (_currentCollection) {
        items = [[LibraryConnection mainConnection] fetchComicsInCollection:_currentCollection];
      } else {
        items = [[LibraryConnection mainConnection] fetchAllCollectionsByName];
      }
      break;
    }
    
  }
#if __DISPLAY_THUMBNAILS_IN_BACKGROUND__
  pthread_mutex_lock(&_displayMutex);
  CFArrayRemoveAllValues(_displayQueue);
  _gridView.items = nil;
  _gridView.extraVisibleRows = 0;
#endif
  _gridView.scrollingAmount = scrolling;
  _gridView.items = items;
#if __DISPLAY_THUMBNAILS_IN_BACKGROUND__
  [self _processDisplayQueue:NO];  // Display immediately
  pthread_mutex_unlock(&_displayMutex);
  _gridView.extraVisibleRows = 6;
#endif
}

- (void) _setCurrentCollection:(Collection*)collection {
  UIImage* backgroundImage = [UIImage imageNamed:(collection ? @"Background-Collection.png" : @"Background-Library.png")];
  _window.layer.contents = (id)[backgroundImage CGImage];
  _window.layer.contentsScale = backgroundImage.scale;
  
  NSMutableArray* barItems = [[NSMutableArray alloc] initWithArray:_navigationBar.items];
  if (barItems.count == 2) {
    [barItems removeObjectAtIndex:1];
  }
  if (collection) {
    UINavigationItem* item = [[UINavigationItem alloc] initWithTitle:collection.name];
    UIBarButtonItem* button = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"Action.png"]
                                                               style:UIBarButtonItemStyleBordered
                                                              target:self
                                                              action:@selector(_toggleMenu:)];
    item.rightBarButtonItem = button;
    [button release];
    [barItems addObject:item];
    [item release];
  }
  _navigationBar.items = barItems;
  [barItems release];
  
  if (collection != _currentCollection) {
    [_currentCollection release];
    _currentCollection = [collection retain];
  }
  [self _reloadCurrentCollection];
}

- (void) _presentComic:(Comic*)comic {
  ComicViewController* viewController = [[ComicViewController alloc] initWithComic:comic];
  if (viewController) {
    [CATransaction begin];
    [[AppDelegate sharedInstance] showSpinnerWithMessage:NSLocalizedString(@"SPINNER_MESSAGE", nil) fullScreen:NO animated:YES];
    [CATransaction commit];
    
    viewController.modalPresentationStyle = UIModalPresentationFullScreen;
    viewController.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    [self presentModalViewController:viewController animated:YES];
    [viewController release];
    
    [[AppDelegate sharedInstance] hideSpinner:YES];
    
    if (comic != _currentComic) {
      [_currentComic release];
      _currentComic = [comic retain];
    }
  }
}

- (void) dismissModalViewControllerAnimated:(BOOL)animated {
  [super dismissModalViewControllerAnimated:animated];
  
  if (([[NSUserDefaults standardUserDefaults] integerForKey:kDefaultKey_SortingMode] == kSortingMode_ByStatus) && !_gridView.empty) {
    [self _reloadCurrentCollection];
  } else if (_currentComic) {
    Comic* comic = [_gridView itemForItem:_currentComic];  // We cannot update "_currentComic" directly as it will not be in the grid items anymore if the view has been reloaded
    if (comic) {
      [[LibraryConnection mainConnection] refetchObject:comic];
      [self _updateThumbnailViewForItem:comic];
    } else {
      DNOT_REACHED();
    }
  }
  
  [_currentComic release];
  _currentComic = nil;
}

- (void) willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration {
  [super willRotateToInterfaceOrientation:toInterfaceOrientation duration:duration];
  
  if (UIInterfaceOrientationIsLandscape(toInterfaceOrientation)) {
    _gridView.contentMargins = UIEdgeInsetsMake(kGridMargin, kGridMargin + kGridMarginExtra_Landscape, kGridMargin, kGridMargin);
    _gridView.itemSpacing = UIEdgeInsetsMake(0.0, 0.0, kItemVerticalSpacing, kItemHorizontalSpacing_Landscape);
  } else {
    _gridView.contentMargins = UIEdgeInsetsMake(kGridMargin, kGridMargin + kGridMarginExtra_Portrait, kGridMargin, kGridMargin);
    _gridView.itemSpacing = UIEdgeInsetsMake(0.0, 0.0, kItemVerticalSpacing, kItemHorizontalSpacing_Portrait);
  }
}

- (void) didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation {
  [super didRotateFromInterfaceOrientation:fromInterfaceOrientation];
  
  // This code path is only used before iOS 6.0
  if (_launchView && UIInterfaceOrientationIsLandscape(self.interfaceOrientation)) {
    UIImage* image = [[UIImage alloc] initWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"Default-Landscape" ofType:@"png"]];
    _launchView.image = image;
    [image release];
  }
}

- (void) viewWillAppear:(BOOL)animated {
  [super viewWillAppear:animated];
  
  if (UIInterfaceOrientationIsLandscape(self.interfaceOrientation)) {
    _gridView.contentMargins = UIEdgeInsetsMake(kGridMargin, kGridMargin + kGridMarginExtra_Landscape, kGridMargin, kGridMargin);
    _gridView.itemSpacing = UIEdgeInsetsMake(0.0, 0.0, kItemVerticalSpacing, kItemHorizontalSpacing_Landscape);
  } else {
    _gridView.contentMargins = UIEdgeInsetsMake(kGridMargin, kGridMargin + kGridMarginExtra_Portrait, kGridMargin, kGridMargin);
    _gridView.itemSpacing = UIEdgeInsetsMake(0.0, 0.0, kItemVerticalSpacing, kItemHorizontalSpacing_Portrait);
  }
  
  if (_gridView.empty) {
    [_gridView layoutSubviews];
    [self _setCurrentCollection:_currentCollection];
  }
  
  if (_launched == NO) {
    _launchView = [[UIImageView alloc] initWithFrame:self.view.bounds];
    _launchView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    NSString* path = [[NSBundle mainBundle] pathForResource:(UIInterfaceOrientationIsLandscape(self.interfaceOrientation) ? @"Default-Landscape" : @"Default-Portrait") ofType:@"png"];
    UIImage* image = [[UIImage alloc] initWithContentsOfFile:path];
    _launchView.image = image;
    [image release];
    [self.view addSubview:_launchView];
    _launched = YES;
  }
}

- (void) _rateNow:(id)argument {
  [Flurry logEvent:@"rating.now" withParameters:nil];
  [[NSUserDefaults standardUserDefaults] setInteger:-1 forKey:kDefaultUserKey_LaunchCount];
  
  [[UIApplication sharedApplication] openURL:[NSURL URLWithString:[[NSBundle mainBundle] objectForInfoDictionaryKey:@"iTunesURL"]]];
}

- (void) _rateLater:(id)argument {
  [Flurry logEvent:@"rating.later" withParameters:nil];
  [[NSUserDefaults standardUserDefaults] setInteger:0 forKey:kDefaultUserKey_LaunchCount];
}

- (void) _showRatingScreen {
  [Flurry logEvent:@"rating.prompt" withParameters:nil];
  [(ApplicationDelegate*)[[UIApplication sharedApplication] delegate] showAlertWithTitle:NSLocalizedString(@"RATE_ALERT_TITLE", nil)
                                                                                 message:NSLocalizedString(@"RATE_ALERT_MESSAGE", nil)
                                                                           confirmButton:NSLocalizedString(@"RATE_ALERT_CONFIRM", nil)
                                                                            cancelButton:NSLocalizedString(@"RATE_ALERT_CANCEL", nil)
                                                                                delegate:self
                                                                         confirmSelector:@selector(_rateNow:)
                                                                          cancelSelector:@selector(_rateLater:)
                                                                                argument:nil];
  [[UIApplication sharedApplication] endIgnoringInteractionEvents];
}

- (void) _viewDidReallyAppear {
  if (_currentComic) {
    Comic* comic = [[_currentComic retain] autorelease];
    [_currentComic release];
    _currentComic = nil;
    
    [self _presentComic:comic];
  } else {
    [[UIApplication sharedApplication] setStatusBarHidden:NO withAnimation:UIStatusBarAnimationSlide];
  }
  
  [CATransaction flush];
  
  UIView* launchView = _launchView;
  [UIView animateWithDuration:0.5 animations:^{
    launchView.alpha = 0.0;
    self.view.frame = [[UIScreen mainScreen] applicationFrame];
  } completion:^(BOOL finished) {
    [launchView removeFromSuperview];
    [launchView release];
  }];
  _launchView = nil;
  
  NSInteger count = [[NSUserDefaults standardUserDefaults] integerForKey:kDefaultUserKey_LaunchCount];
  if (count >= 0) {
    [[NSUserDefaults standardUserDefaults] setInteger:(count + 1) forKey:kDefaultUserKey_LaunchCount];
    if ((count + 1 >= kLaunchCountBeforeRating) && !self.modalViewController && [[NetReachability sharedNetReachability] state]) {
      [[UIApplication sharedApplication] beginIgnoringInteractionEvents];
      [self performSelector:@selector(_showRatingScreen) withObject:nil afterDelay:kShowRatingDelay];
    } else {
      LOG_VERBOSE(@"Launch count is now %i", [[NSUserDefaults standardUserDefaults] integerForKey:kDefaultUserKey_LaunchCount]);
    }
  }
}

- (void) viewDidAppear:(BOOL)animated {
  [super viewDidAppear:animated];
  
  if (_launchView) {
    [self performSelector:@selector(_viewDidReallyAppear) withObject:nil afterDelay:0.0];  // Work around interface orientation not already set in -viewDidAppear before iOS 6.0 but instead set after -didRotateFromInterfaceOrientation gets called
  }
  
  [self becomeFirstResponder];
}

- (void) _popCollection {
  [self gridViewDidUpdateScrollingAmount:nil];
  [self _setCurrentCollection:nil];
}

- (BOOL) navigationBar:(UINavigationBar*)navigationBar shouldPopItem:(UINavigationItem*)item {
  [self performSelector:@selector(_popCollection) withObject:nil afterDelay:0.0];
  return NO;
}

- (void) libraryUpdaterWillStart:(LibraryUpdater*)library {
  _progressView.progress = 0.0;
  _markReadButton.enabled = NO;
  _markNewButton.enabled = NO;
  _updateButton.enabled = NO;
  _forceUpdateButton.enabled = NO;
}

- (void) libraryUpdaterDidContinue:(LibraryUpdater*)library progress:(float)progress {
  _progressView.progress = progress;
  if (_menuController.popoverVisible) {
    [self _updateStatistics];
  }
}

- (void) libraryUpdaterDidFinish:(LibraryUpdater*)library {
  if (_currentCollection && ![[LibraryConnection mainConnection] refetchObject:_currentCollection]) {
    [self _setCurrentCollection:nil];
  } else {
    [self _reloadCurrentCollection];
  }
  
  _progressView.progress = 1.0;
  _markReadButton.enabled = YES;
  _markNewButton.enabled = YES;
  _updateButton.enabled = YES;
  _forceUpdateButton.enabled = YES;
}

- (UIView*) gridView:(GridView*)gridView viewForItem:(id)item {
  ThumbnailView* view = [[ThumbnailView alloc] initWithFrame:CGRectMake(0, 0, kLibraryThumbnailWidth, kLibraryThumbnailHeight)];
  return [view autorelease];
}

- (void) gridViewDidUpdateScrollingAmount:(GridView*)gridView {
  if (!_gridView.empty) {
    NSInteger scrolling = lroundf(_gridView.scrollingAmount);
    if (_currentCollection) {
      if (scrolling != _currentCollection.scrolling) {
        _currentCollection.scrolling = scrolling;
        [[LibraryConnection mainConnection] updateObject:_currentCollection];
      }
    } else {
      [[NSUserDefaults standardUserDefaults] setInteger:scrolling forKey:kDefaultKey_RootScrolling];
    }
  }
}

#if __DISPLAY_THUMBNAILS_IN_BACKGROUND__

- (void) gridViewWillStartUpdatingViewsVisibility:(GridView*)gridView {
  pthread_mutex_lock(&_displayMutex);
  _showBatch = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
  _hideBatch = CFSetCreateMutable(kCFAllocatorDefault, 0, &kCFTypeSetCallBacks);
}

#endif

- (void) gridView:(GridView*)gridView willShowView:(UIView*)view forItem:(id)item {
  UIImage* placeholderImage = [item isKindOfClass:[Comic class]] ? _comicImage : _collectionImage;
#if __DISPLAY_THUMBNAILS_IN_BACKGROUND__
  view.layer.contents = (id)[placeholderImage CGImage];
  CFDictionarySetValue(_showBatch, view, item);
#else
  UIImage* image = nil;
#if __STORE_THUMBNAILS_IN_DATABASE__
  DatabaseSQLRowID rowID = [item thumbnail];
  if (rowID > 0) {
    Thumbnail* thumnail = [[LibraryConnection mainConnection] fetchObjectOfClass:[Thumbnail class] withSQLRowID:rowID];
    image = [[UIImage alloc] initWithData:thumnail.data];
  }
#else
  NSString* name = [item thumbnail];
  if (name) {
    NSString* path = [[LibraryConnection libraryApplicationDataPath] stringByAppendingPathComponent:name];
    image = [[UIImage alloc] initWithContentsOfFile:path];
  }
#endif
  if (image) {
    [(ThumbnailView*)view setImage:image];
    [image release];
  } else {
    [(ThumbnailView*)view setImage:placeholderImage];
  }
#endif
  
  int status = [item status];
  if (status > 0) {
    UIImageView* subview = [[UIImageView alloc] initWithImage:_ribbonImage];
    subview.frame = CGRectMake(kRibbonImageX, kRibbonImageY, kRibbonImageWidth, kRibbonImageHeight);
    [view addSubview:subview];
    [subview release];
    [(ThumbnailView*)view setRibbonView:subview];
  } else if (status < 0) {
    UIImageView* subview = [[UIImageView alloc] initWithImage:_newImage];
    subview.frame = CGRectMake(kNewImageX, kNewImageY, kNewImageWidth, kNewImageHeight);
    [view addSubview:subview];
    [subview release];
    [(ThumbnailView*)view setNoteView:subview];
  }
}

- (void) gridView:(GridView*)gridView didHideView:(UIView*)view forItem:(id)item {
#if __DISPLAY_THUMBNAILS_IN_BACKGROUND__
  CFSetAddValue(_hideBatch, view);
  view.layer.contents = NULL;
#else
  [(ThumbnailView*)view setImage:nil];
#endif
  
  [[(ThumbnailView*)view noteView] removeFromSuperview];
  [(ThumbnailView*)view setNoteView:nil];
  [[(ThumbnailView*)view ribbonView] removeFromSuperview];
  [(ThumbnailView*)view setRibbonView:nil];
}

#if __DISPLAY_THUMBNAILS_IN_BACKGROUND__

static void __SetApplierFunction(const void* value, void* context) {
  CFDictionaryRemoveValue((CFMutableDictionaryRef)context, value);
}

static void __ArrayApplierFunction(const void* value, void* context) {
  CFSetApplyFunction((CFSetRef)context, __SetApplierFunction, (void*)value);
}

- (void) gridViewDidEndUpdatingViewsVisibility:(GridView*)gridView {
  BOOL signal = NO;
  
  if (CFSetGetCount(_hideBatch)) {
    CFArrayApplyFunction(_displayQueue, CFRangeMake(0, CFArrayGetCount(_displayQueue)), __ArrayApplierFunction, _hideBatch);
  }
  CFRelease(_hideBatch);
  if (CFDictionaryGetCount(_showBatch)) {
    CFArrayAppendValue(_displayQueue, _showBatch);
    signal = YES;
  }
  CFRelease(_showBatch);
  pthread_mutex_unlock(&_displayMutex);
  
  if (signal) {
    CFRunLoopSourceSignal(_displaySource);
    CFRunLoopWakeUp(_displayRunLoop);
  }
}

#endif

- (void) saveState {
  if ([self.modalViewController isKindOfClass:[ComicViewController class]]) {
    [(ComicViewController*)self.modalViewController saveState];
  }
  
  [self gridViewDidUpdateScrollingAmount:nil];
  [[NSUserDefaults standardUserDefaults] setInteger:_currentCollection.sqlRowID forKey:kDefaultKey_CurrentCollection];
  [[NSUserDefaults standardUserDefaults] setInteger:_currentComic.sqlRowID forKey:kDefaultKey_CurrentComic];
}

@end

@implementation LibraryViewController (IBActions)

- (IBAction) resort:(id)sender {
  if (_segmentedControl.selectedSegmentIndex != [[NSUserDefaults standardUserDefaults] integerForKey:kDefaultKey_SortingMode]) {
    [[NSUserDefaults standardUserDefaults] setInteger:_segmentedControl.selectedSegmentIndex forKey:kDefaultKey_SortingMode];
    [self gridViewDidUpdateScrollingAmount:nil];
    [self _reloadCurrentCollection];
  }
}

- (IBAction) update:(id)sender {
  [[LibraryUpdater sharedUpdater] update:NO];
}

- (void) _forceUpdate {
  LoggingPurgeHistory(0.0);
  [[LibraryUpdater sharedUpdater] update:YES];
  [self _updateStatistics];
  [self _setCurrentCollection:nil];
}

- (IBAction) forceUpdate:(id)sender {
  [[AppDelegate sharedInstance] showAlertWithTitle:NSLocalizedString(@"FORCE_UPDATE_TITLE", nil)
                                           message:NSLocalizedString(@"FORCE_UPDATE_MESSAGE", nil)
                                     confirmButton:NSLocalizedString(@"FORCE_UPDATE_CONTINUE", nil)
                                      cancelButton:NSLocalizedString(@"FORCE_UPDATE_CANCEL", nil)
                                          delegate:self
                                   confirmSelector:@selector(_forceUpdate)
                                    cancelSelector:NULL
                                          argument:nil];
}

- (IBAction) updateServer:(id)sender {
  if (_serverSwitch.on) {
    [(AppDelegate*)[AppDelegate sharedInstance] enableWebServer];
  } else {
    [(AppDelegate*)[AppDelegate sharedInstance] disableWebServer];
  }
  [self _updateServer];
}

- (void) _markAllRead {
  [[LibraryConnection mainConnection] updateStatusForAllComics:0];
  [self _reloadCurrentCollection];
}

- (IBAction) markAllRead:(id)sender {
  [[AppDelegate sharedInstance] showAlertWithTitle:NSLocalizedString(@"MARK_ALL_READ_TITLE", nil)
                                           message:nil
                                     confirmButton:NSLocalizedString(@"MARK_ALL_READ_CONTINUE", nil)
                                      cancelButton:NSLocalizedString(@"MARK_ALL_READ_CANCEL", nil)
                                          delegate:self
                                   confirmSelector:@selector(_markAllRead)
                                    cancelSelector:NULL
                                          argument:nil];
}

- (void) _markAllNew {
  [[LibraryConnection mainConnection] updateStatusForAllComics:-1];
  [self _reloadCurrentCollection];
}

- (IBAction) markAllNew:(id)sender {
  [[AppDelegate sharedInstance] showAlertWithTitle:NSLocalizedString(@"MARK_ALL_NEW_TITLE", nil)
                                           message:nil
                                     confirmButton:NSLocalizedString(@"MARK_ALL_NEW_CONTINUE", nil)
                                      cancelButton:NSLocalizedString(@"MARK_ALL_NEW_CANCEL", nil)
                                          delegate:self
                                   confirmSelector:@selector(_markAllNew)
                                    cancelSelector:NULL
                                          argument:nil];
}

- (IBAction) showLog:(id)sender {
  [_menuController dismissPopoverAnimated:YES];
  [[AppDelegate sharedInstance] showLogViewControllerWithTitle:NSLocalizedString(@"LOG_TITLE", nil)];
}

- (IBAction) toggleDimming:(id)sender {
  [(AppDelegate*)[AppDelegate sharedInstance] setScreenDimmed:_dimmingSwitch.on];
}

@end
