@import UIKit;
#import "WMFAnalyticsLogging.h"
#import "MWKArticle.h"

@class MWKDataStore;
@class MWKTitle;
@class WMFShareFunnel;
@class WMFArticleViewController;

NS_ASSUME_NONNULL_BEGIN


@protocol WMFArticleViewControllerDelegate <NSObject>

- (void)articleController:(WMFArticleViewController*)controller didUpdateArticleLoadProgress:(CGFloat)progress animated:(BOOL)animated;

- (void)articleControllerDidLoadArticle:(WMFArticleViewController*)controller;

- (void)articleControllerDidFailToLoadArticle:(WMFArticleViewController*)controller;

@end

/**
 *  View controller responsible for displaying article content.
 */
@interface WMFArticleViewController : UIViewController<WMFAnalyticsContextProviding, WMFAnalyticsViewNameProviding>

- (instancetype)initWithArticleTitle:(MWKTitle*)title
                           dataStore:(MWKDataStore*)dataStore;

@property (nonatomic, strong, readonly) MWKTitle* articleTitle;
@property (nonatomic, strong, readonly) MWKDataStore* dataStore;

@property (nonatomic, strong, readonly, nullable) MWKArticle* article;

/**
 *  Show or hide the search button. Default is YES
 */
@property (nonatomic, assign) BOOL showsSearchButton;

/**
 *  Set to YES to restore the scroll position
 */
@property (nonatomic, assign) BOOL restoreScrollPositionOnArticleLoad;

@property (nonatomic, weak) id<WMFArticleViewControllerDelegate> delegate;

@end


@interface WMFArticleViewController (WMFBrowserViewControllerInterface)


@property (strong, nonatomic, nullable, readonly) WMFShareFunnel* shareFunnel;

- (BOOL)canRefresh;
- (BOOL)canShare;
- (BOOL)hasLanguages;
- (BOOL)hasTableOfContents;
- (BOOL)hasReadMore;
- (BOOL)hasAboutThisArticle;

- (void)fetchArticleIfNeeded;

- (void)shareArticleFromButton:(nullable UIBarButtonItem*)button;


@end

NS_ASSUME_NONNULL_END
