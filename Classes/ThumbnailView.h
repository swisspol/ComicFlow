//
//  ThumbnailView.h
//  ComicFlow
//
//  Created by Leonardo Carnevale on 3/5/15.
//
//

#import <Foundation/Foundation.h>

#if __DISPLAY_THUMBNAILS_IN_BACKGROUND__
@interface ThumbnailView : UIView
#else
@interface ThumbnailView : UIImageView
#endif
                           {
@private
    //    UIView* _noteView;
    //    UIView* _ribbonView;
    //    UIProgressView* _progressBar;
    //    NSURLConnection* _connection;
}

@property (nonatomic, assign) UIView* noteView;
@property (nonatomic, assign) UIView* ribbonView;
@property (nonatomic, assign) UIProgressView* progressBar;

@end
