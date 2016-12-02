#import <UIKit/UIKit.h>
#import "WMFAnalyticsLogging.h"
#import "WMFArticleViewController.h"

@class MWKDataStore;
@class WMFArticleDataStore;
@class WMFTableOfContentsViewController;

NS_ASSUME_NONNULL_BEGIN

@interface UIViewController (WMFArticlePresentation)

- (WMFArticleViewController *)wmf_pushArticleWithURL:(NSURL *)url dataStore:(MWKDataStore *)dataStore previewStore:(WMFArticleDataStore *)previewStore restoreScrollPosition:(BOOL)restoreScrollPosition animated:(BOOL)animated;

- (void)wmf_pushArticleWithURL:(NSURL *)url dataStore:(MWKDataStore *)dataStore previewStore:(WMFArticleDataStore *)previewStore animated:(BOOL)animated;

- (void)wmf_pushArticleViewController:(WMFArticleViewController *)viewController animated:(BOOL)animated;

- (void)wmf_pushViewController:(UIViewController *)viewController animated:(BOOL)animated;

@end

NS_ASSUME_NONNULL_END
