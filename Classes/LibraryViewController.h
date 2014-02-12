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

#import <pthread.h>

#import "GridView.h"
#import "Library.h"

@interface LibraryViewController : UIViewController <UINavigationBarDelegate, UIPopoverControllerDelegate> {
@private
  GridView* _gridView;
  UINavigationBar* _navigationBar;
  UISegmentedControl* _segmentedControl;
  UIView* _menuView;
  UIProgressView* _progressView;
  UIButton* _updateButton;
  UIButton* _forceUpdateButton;
  UIButton* _markReadButton;
  UIButton* _markNewButton;
  UISwitch* _serverSwitch;
  UILabel* _addressLabel;
  UILabel* _infoLabel;
  UILabel* _versionLabel;
  UISwitch* _dimmingSwitch;
  UIButton* _purchaseButton;
  UIButton* _restoreButton;
  
  UIWindow* _window;
  BOOL _launched;
  UIImage* _collectionImage;
  UIImage* _newImage;
  UIImage* _ribbonImage;
  UIImage* _comicImage;
  UIPopoverController* _menuController;
  Collection* _currentCollection;
  Comic* _currentComic;
  DatabaseObject* _selectedItem;
  UIImageView* _launchView;
#if __DISPLAY_THUMBNAILS_IN_BACKGROUND__
  pthread_mutex_t _displayMutex;
  CFMutableArrayRef _displayQueue;
  CFRunLoopSourceRef _displaySource;
  CFRunLoopRef _displayRunLoop;
  CFMutableDictionaryRef _showBatch;
  CFMutableSetRef _hideBatch;
#if __STORE_THUMBNAILS_IN_DATABASE__
  LibraryConnection* _displayConnection;
#endif
#endif
  NSTimer* _updateTimer;
}
@property(nonatomic, retain) IBOutlet GridView* gridView;
@property(nonatomic, retain) IBOutlet UINavigationBar* navigationBar;
@property(nonatomic, retain) IBOutlet UISegmentedControl* segmentedControl;
@property(nonatomic, retain) IBOutlet UIView* menuView;
@property(nonatomic, retain) IBOutlet UIProgressView* progressView;
@property(nonatomic, retain) IBOutlet UIButton* updateButton;
@property(nonatomic, retain) IBOutlet UIButton* forceUpdateButton;
@property(nonatomic, retain) IBOutlet UIButton* markReadButton;
@property(nonatomic, retain) IBOutlet UIButton* markNewButton;
@property(nonatomic, retain) IBOutlet UISwitch* serverSwitch;
@property(nonatomic, retain) IBOutlet UILabel* addressLabel;
@property(nonatomic, retain) IBOutlet UILabel* infoLabel;
@property(nonatomic, retain) IBOutlet UILabel* versionLabel;
@property(nonatomic, retain) IBOutlet UISwitch* dimmingSwitch;
@property(nonatomic, retain) IBOutlet UIButton* purchaseButton;
@property(nonatomic, retain) IBOutlet UIButton* restoreButton;
- (id) initWithWindow:(UIWindow*)window;
- (void) updatePurchase;
- (void) saveState;
@end

@interface LibraryViewController (IBActions)
- (IBAction) resort:(id)sender;
- (IBAction) update:(id)sender;
- (IBAction) forceUpdate:(id)sender;
- (IBAction) updateServer:(id)sender;
- (IBAction) markAllRead:(id)sender;
- (IBAction) markAllNew:(id)sender;
- (IBAction) showLog:(id)sender;
- (IBAction) toggleDimming:(id)sender;
- (IBAction) purchase:(id)sender;
- (IBAction) restore:(id)sender;
@end

@interface LibraryViewController (GridViewDelegate) <GridViewDelegate>
@end

@interface LibraryViewController (LibraryUpdaterDelegate) <LibraryUpdaterDelegate>
@end
