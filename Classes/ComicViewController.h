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

#import "DocumentView.h"
#import "NavigationControl.h"
#import "Library.h"

typedef enum {
  kComicType_PDF,
  kComicType_ZIP,
  kComicType_RAR
} ComicType;

@interface ComicViewController : UIViewController <UINavigationBarDelegate, DocumentViewDelegate, NavigationControlDelegate> {
@private
  UINavigationBar* _navigationBar;
  UIView* _contentView;
  NavigationControl* _navigationControl;
  
  Comic* _comic;
  NSString* _path;
  ComicType _type;
  id _contents;
  DocumentView* _documentView;
  UILabel* _pageLabel;
}
@property(nonatomic, retain) IBOutlet UINavigationBar* navigationBar;
@property(nonatomic, retain) IBOutlet NavigationControl* navigationControl;
@property(nonatomic, retain) IBOutlet UIView* contentView;
- (id) initWithComic:(Comic*)comic;
- (IBAction) selectPage:(id)sender;
- (void) saveState;
@end
