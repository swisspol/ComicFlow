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

#import "RatingViewController.h"
#import "Defaults.h"

@implementation RatingViewController

- (BOOL) shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
  return YES;
}

- (IBAction) remindLater:(id)sender {
  [[NSUserDefaults standardUserDefaults] setInteger:0 forKey:kDefaultUserKey_LaunchCount];
  
  if ([self respondsToSelector:@selector(presentingViewController)]) {
    [self.presentingViewController dismissModalViewControllerAnimated:YES];
  } else {
    [self.parentViewController dismissModalViewControllerAnimated:YES];
  }
}

- (IBAction) ignore:(id)sender {
  [[NSUserDefaults standardUserDefaults] setInteger:-1 forKey:kDefaultUserKey_LaunchCount];
  
  if ([self respondsToSelector:@selector(presentingViewController)]) {
    [self.presentingViewController dismissModalViewControllerAnimated:YES];
  } else {
    [self.parentViewController dismissModalViewControllerAnimated:YES];
  }
}

- (IBAction) rateNow:(id)sender {
  [[NSUserDefaults standardUserDefaults] setInteger:-1 forKey:kDefaultUserKey_LaunchCount];
  
  [[UIApplication sharedApplication] openURL:[NSURL URLWithString:[[NSBundle mainBundle] objectForInfoDictionaryKey:@"iTunesURL"]]];
  
  if ([self respondsToSelector:@selector(presentingViewController)]) {
    [self.presentingViewController dismissModalViewControllerAnimated:YES];
  } else {
    [self.parentViewController dismissModalViewControllerAnimated:YES];
  }
}

@end
