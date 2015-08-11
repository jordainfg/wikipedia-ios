@import UIKit;
#import "WMFArticleContentController.h"
#import "WMFArticleListItemController.h"

@class WMFArticleViewController;
@class MWKDataStore;
@class MWKSavedPageList;
@class MWKArticle;

NS_ASSUME_NONNULL_BEGIN

@interface WMFArticleContainerViewController : UIViewController
    <WMFArticleContentController, WMFArticleListItemController>

+ (instancetype)articleContainerViewControllerWithDataStore:(MWKDataStore*)dataStore
                                                 savedPages:(MWKSavedPageList*)savedPages;

@property (nonatomic, strong, readonly) WMFArticleViewController* articleViewController;

@end

NS_ASSUME_NONNULL_END
