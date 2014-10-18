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

@class XLDatabaseLogger;

@interface ApplicationDelegate : NSObject <UIApplicationDelegate> {
@private
  UIWindow* _window;
  UIViewController* _viewController;
  
  XLDatabaseLogger* _databaseLogger;
  UIWindow* _overlayWindow;
  
  UIAlertView* _alertView;
  id _alertDelegate;
  SEL _alertConfirmSelector;
  SEL _alertCancelSelector;
  id _alertArgument;
  UIView* _spinnerView;
}
@property(nonatomic, retain) IBOutlet UIWindow* window;
@property(nonatomic, retain) IBOutlet UIViewController* viewController;
+ (id) sharedInstance;
- (void) saveState;  // Called when app terminates or is suspended - Default implementation does nothing
@end

@interface ApplicationDelegate (Logging)
- (void) purgeLogHistory;
- (void) showLogViewController;
@end

// If alert is dismissed, cancel selector is called on delegate
// Any existing alert or authentication is automatically dismissed when new one is shown
// Alert is automatically dismissed when going to the background
@interface ApplicationDelegate (Alerts)
- (BOOL) isAlertVisible;
- (void) showAlertWithTitle:(NSString*)title message:(NSString*)message button:(NSString*)button;
- (void) showAlertWithTitle:(NSString*)title  // Cannot be nil
                    message:(NSString*)message
                     button:(NSString*)button  // Cannot be nil
                   delegate:(id)delegate
                   selector:(SEL)selector
                   argument:(id)argument;
- (void) showAlertWithTitle:(NSString*)title  // Cannot be nil
                    message:(NSString*)message
              confirmButton:(NSString*)confirmButton  // Cannot be nil
               cancelButton:(NSString*)cancelButton
                   delegate:(id)delegate
            confirmSelector:(SEL)confirmSelector  // -didConfirm:(id)argument
             cancelSelector:(SEL)cancelSelector  // -didCancel:(id)argument
                   argument:(id)argument;
- (void) dismissAlert:(BOOL)animated;  // Does nothing if alert is not visible
@end

// Spinner is shown in an overlay window
@interface ApplicationDelegate (Spinner)
- (BOOL) isSpinnerVisible;
- (void) showSpinnerWithMessage:(NSString*)message fullScreen:(BOOL)fullScreen animated:(BOOL)animated;  // Message may be nil
- (void) hideSpinner:(BOOL)animated;
@end
