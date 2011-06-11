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

#import "ApplicationDelegate.h"
#import "DAVServer.h"

@interface AppDelegate : ApplicationDelegate <DAVServerDelegate> {
  DAVServer* _davServer;
  NSTimer* _updateTimer;
  BOOL _hasConnections;
  BOOL _needsUpdate;
#ifdef NSFoundationVersionNumber_iOS_4_0
  UIBackgroundTaskIdentifier _backgroundTask;
#endif
}
@property(nonatomic, readonly) DAVServer* davServer;
- (void) enableDAVServer;
- (void) disableDAVServer;
@end
