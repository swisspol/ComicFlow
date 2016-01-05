//  Copyright (C) 2010-2016 Pierre-Olivier Latour <info@pol-online.net>
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

#define kDefaultKey_LibraryVersion @"libraryVersion"
#define kLibraryVersion 1

#define kDefaultKey_ServerType @"serverType"
#define kDefaultKey_ServerMode @"serverMode"
typedef enum {
  kServerMode_Limited = -1,
  kServerMode_Trial = 0,
  kServerMode_Full = 1
} ServerMode;
#define kDefaultKey_UploadsRemaining @"uploadsRemaining"

#define kDefaultKey_ScreenDimmed @"screenDimmed"

#define kDefaultKey_RootTimestamp @"rootTimestamp"
#define kDefaultKey_RootScrolling @"rootScrolling"
#define kDefaultKey_CurrentCollection @"currentCollection"
#define kDefaultKey_CurrentComic @"currentComic"

#define kDefaultKey_SortingMode @"sortingMode"
typedef enum {
  kSortingMode_ByCollection = 0,
  kSortingMode_ByName,
  kSortingMode_ByDate,
  kSortingMode_ByStatus
} SortingMode;

#define kDefaultKey_LaunchCount @"launchCount"
