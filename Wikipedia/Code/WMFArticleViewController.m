#import "WMFArticleViewController_Private.h"
#import "Wikipedia-Swift.h"

#import "NSUserActivity+WMFExtensions.h"

// Frameworks
#import <Masonry/Masonry.h>
#import <BlocksKit/BlocksKit+UIKit.h>

// Controller
#import "WebViewController.h"
#import "UIViewController+WMFStoryboardUtilities.h"
#import "WMFReadMoreViewController.h"
#import "WMFImageGalleryViewContoller.h"
#import "SectionEditorViewController.h"
#import "WMFArticleFooterMenuViewController.h"
#import "WMFArticleBrowserViewController.h"
#import "WMFLanguagesViewController.h"
#import "MWKLanguageLinkController.h"
#import "WMFShareOptionsController.h"
#import "WMFSaveButtonController.h"
#import "UIViewController+WMFSearch.h"

//Funnel
#import "WMFShareFunnel.h"
#import "ProtectedEditAttemptFunnel.h"
#import "PiwikTracker+WMFExtensions.h"

// Model
#import "MWKDataStore.h"
#import "MWKCitation.h"
#import "MWKTitle.h"
#import "MWKSavedPageList.h"
#import "MWKUserDataStore.h"
#import "MWKArticle+WMFSharing.h"
#import "MWKHistoryEntry.h"
#import "MWKHistoryList.h"
#import "MWKProtectionStatus.h"
#import "MWKSectionList.h"
#import "MWKHistoryList.h"
#import "MWKLanguageLink.h"


// Networking
#import "WMFArticleFetcher.h"

// View
#import "UIViewController+WMFEmptyView.h"
#import "UIBarButtonItem+WMFButtonConvenience.h"
#import "UIScrollView+WMFContentOffsetUtils.h"
#import "UIWebView+WMFTrackingView.h"
#import "NSArray+WMFLayoutDirectionUtilities.h"
#import "UIViewController+WMFOpenExternalUrl.h"
#import <TUSafariActivity/TUSafariActivity.h>
#import "WMFArticleTextActivitySource.h"
#import "UIImageView+WMFImageFetching.h"
#import "UIImageView+WMFPlaceholder.h"

#import "NSString+WMFPageUtilities.h"
#import "NSURL+WMFLinkParsing.h"
#import "NSURL+WMFExtras.h"
#import "UIToolbar+WMFStyling.h"

@import SafariServices;

@import JavaScriptCore;

@import Tweaks;

NS_ASSUME_NONNULL_BEGIN

@interface WMFArticleViewController ()
<WMFWebViewControllerDelegate,
 UINavigationControllerDelegate,
 WMFImageGalleryViewContollerReferenceViewDelegate,
 SectionEditorViewControllerDelegate,
 UIViewControllerPreviewingDelegate,
 WMFLanguagesViewControllerDelegate,
 WMFArticleListTableViewControllerDelegate,
 WMFFontSliderViewControllerDelegate,
 UIPopoverPresentationControllerDelegate>

@property (nonatomic, strong, readwrite) MWKTitle* articleTitle;
@property (nonatomic, strong, readwrite) MWKDataStore* dataStore;

@property (strong, nonatomic, nullable, readwrite) WMFShareFunnel* shareFunnel;
@property (strong, nonatomic, nullable) WMFShareOptionsController* shareOptionsController;
@property (nonatomic, strong) WMFSaveButtonController* saveButtonController;

// Data
@property (nonatomic, strong, readonly) MWKHistoryEntry* historyEntry;
@property (nonatomic, strong, readonly) MWKSavedPageList* savedPages;
@property (nonatomic, strong, readonly) MWKHistoryList* recentPages;

// Fetchers
@property (nonatomic, strong) WMFArticleFetcher* articleFetcher;
@property (nonatomic, strong, nullable) AnyPromise* articleFetcherPromise;

// Children
@property (nonatomic, strong) WMFReadMoreViewController* readMoreListViewController;
@property (nonatomic, strong) WMFArticleFooterMenuViewController* footerMenuViewController;

// Views
@property (nonatomic, strong) UIImageView* headerImageView;
@property (nonatomic, strong) UIBarButtonItem* saveToolbarItem;
@property (nonatomic, strong) UIBarButtonItem* languagesToolbarItem;
@property (nonatomic, strong) UIBarButtonItem* shareToolbarItem;
@property (nonatomic, strong) UIBarButtonItem* fontSizeToolbarItem;
@property (nonatomic, strong) UIBarButtonItem* tableOfContentsToolbarItem;
@property (strong, nonatomic) UIProgressView* progressView;
@property (nonatomic, strong) UIRefreshControl* pullToRefresh;

// Previewing
@property (nonatomic, weak) id<UIViewControllerPreviewing> linkPreviewingContext;
@property (nonatomic, assign) BOOL isPreviewing;

@property (strong, nonatomic, nullable) NSTimer* significantlyViewedTimer;

/**
 *  We need to do this to prevent auto loading from occuring,
 *  if we do something to the article like edit it and force a reload
 */
@property (nonatomic, assign) BOOL skipFetchOnViewDidAppear;

@end

@implementation WMFArticleViewController

+ (void)load {
    [self registerTweak];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (instancetype)initWithArticleTitle:(MWKTitle*)title
                           dataStore:(MWKDataStore*)dataStore {
    NSParameterAssert(title);
    NSParameterAssert(dataStore);

    self = [super init];
    if (self) {
        self.articleTitle             = title;
        self.dataStore                = dataStore;
        self.hidesBottomBarWhenPushed = YES;
    }
    return self;
}

#pragma mark - Accessors

- (WMFArticleFooterMenuViewController*)footerMenuViewController {
    if (!_footerMenuViewController && [self hasAboutThisArticle]) {
        self.footerMenuViewController = [[WMFArticleFooterMenuViewController alloc] initWithArticle:self.article similarPagesListDelegate:self];
    }
    return _footerMenuViewController;
}

- (NSString*)description {
    return [NSString stringWithFormat:@"%@ %@", [super description], self.articleTitle];
}

- (void)setArticle:(nullable MWKArticle*)article {
    NSAssert(self.isViewLoaded, @"Expecting article to only be set after the view loads.");
    NSAssert([article.title isEqualToTitle:self.articleTitle],
             @"Invalid article set for VC expecting article data for title: %@", self.articleTitle);

    _shareFunnel            = nil;
    _shareOptionsController = nil;
    [self.articleFetcher cancelFetchForPageTitle:_articleTitle];

    _article = article;

    // always update webVC & headerGallery, even if nil so they are reset if needed
    self.footerMenuViewController.article = _article;
    self.webViewController.article        = _article;

    if (self.article) {
        [self.headerImageView wmf_setImageWithMetadata:_article.leadImage detectFaces:YES];
        [self startSignificantlyViewedTimer];
        [self wmf_hideEmptyView];
        [NSUserActivity wmf_makeActivityActive:[NSUserActivity wmf_articleViewActivityWithArticle:self.article]];
    }

    [self updateToolbar];
    [self createTableOfContentsViewControllerIfNeeded];
    [self updateWebviewFootersIfNeeded];
    [self observeArticleUpdates];
}

- (MWKHistoryList*)recentPages {
    return self.dataStore.userDataStore.historyList;
}

- (MWKSavedPageList*)savedPages {
    return self.dataStore.userDataStore.savedPageList;
}

- (MWKHistoryEntry*)historyEntry {
    return [self.recentPages entryForTitle:self.articleTitle];
}

- (nullable WMFShareFunnel*)shareFunnel {
    NSParameterAssert(self.article);
    if (!self.article) {
        return nil;
    }
    if (!_shareFunnel) {
        _shareFunnel = [[WMFShareFunnel alloc] initWithArticle:self.article];
    }
    return _shareFunnel;
}

- (nullable WMFShareOptionsController*)shareOptionsController {
    NSParameterAssert(self.article);
    if (!self.article) {
        return nil;
    }
    if (!_shareOptionsController) {
        _shareOptionsController = [[WMFShareOptionsController alloc] initWithArticle:self.article
                                                                         shareFunnel:self.shareFunnel];
    }
    return _shareOptionsController;
}

- (UIProgressView*)progressView {
    if (!_progressView) {
        UIProgressView* progress = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleBar];
        progress.translatesAutoresizingMaskIntoConstraints = NO;
        progress.trackTintColor                            = [UIColor clearColor];
        progress.tintColor                                 = [UIColor wmf_blueTintColor];
        _progressView                                      = progress;
    }

    return _progressView;
}

- (UIImageView*)headerImageView {
    if (!_headerImageView) {
        _headerImageView                        = [[UIImageView alloc] initWithFrame:CGRectZero];
        _headerImageView.userInteractionEnabled = YES;
        _headerImageView.clipsToBounds          = YES;
        [_headerImageView wmf_configureWithDefaultPlaceholder];
        UITapGestureRecognizer* tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(imageViewDidTap:)];
        [_headerImageView addGestureRecognizer:tap];
    }
    return _headerImageView;
}

- (WMFReadMoreViewController*)readMoreListViewController {
    if (!_readMoreListViewController) {
        _readMoreListViewController = [[WMFReadMoreViewController alloc] initWithTitle:self.articleTitle
                                                                             dataStore:self.dataStore];
        _readMoreListViewController.delegate = self;
    }
    return _readMoreListViewController;
}

- (WMFArticleFetcher*)articleFetcher {
    if (!_articleFetcher) {
        _articleFetcher = [[WMFArticleFetcher alloc] initWithDataStore:self.dataStore];
    }
    return _articleFetcher;
}

- (WebViewController*)webViewController {
    if (!_webViewController) {
        _webViewController            = [WebViewController wmf_initialViewControllerFromClassStoryboard];
        _webViewController.delegate   = self;
        _webViewController.headerView = self.headerImageView;
    }
    return _webViewController;
}

#pragma mark - Notifications and Observations

- (void)applicationWillResignActiveWithNotification:(NSNotification*)note {
    [self saveWebViewScrollOffset];
}

- (void)articleUpdatedWithNotification:(NSNotification*)note {
    MWKArticle* article = note.userInfo[MWKArticleKey];
    if ([self.articleTitle isEqualToTitle:article.title]) {
        self.article = article;
    }
}

- (void)observeArticleUpdates {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:MWKArticleSavedNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(articleUpdatedWithNotification:)
                                                 name:MWKArticleSavedNotification
                                               object:nil];
}

- (void)unobserveArticleUpdates {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:MWKArticleSavedNotification object:nil];
}

#pragma mark - Public

- (BOOL)canRefresh {
    return self.article != nil;
}

- (BOOL)canShare {
    return self.article != nil;
}

- (BOOL)canAdjustText {
    return self.article != nil;
}

- (BOOL)hasLanguages {
    return self.article.hasMultipleLanguages;
}

- (BOOL)hasTableOfContents {
    return self.article && !self.article.isMain && self.article.sections.count > 0;
}

- (BOOL)hasReadMore {
    WMF_TECH_DEBT_TODO(filter articles outside main namespace);
    return self.article && !self.article.isMain;
}

- (BOOL)hasAboutThisArticle {
    return self.article && !self.article.isMain;
}

- (NSString*)shareText {
    NSString* text = [self.webViewController selectedText];
    if (text.length == 0) {
        text = [self.article shareSnippet];
    }
    return text;
}

#pragma mark - Toolbar Setup

- (void)updateToolbar {
    [self updateToolbarItemsIfNeeded];
    [self updateToolbarItemEnabledState];
}

- (void)updateToolbarItemsIfNeeded {
    if (!self.saveButtonController) {
        self.saveButtonController = [[WMFSaveButtonController alloc] initWithBarButtonItem:self.saveToolbarItem savedPageList:self.savedPages title:self.articleTitle];
    }

    NSArray<UIBarButtonItem*>* toolbarItems =
        [NSArray arrayWithObjects:
         self.languagesToolbarItem,
         [self flexibleSpaceToolbarItem],
         self.fontSizeToolbarItem, [UIBarButtonItem wmf_barButtonItemOfFixedWidth:22.f],
         self.shareToolbarItem, [UIBarButtonItem wmf_barButtonItemOfFixedWidth:24.f],
         self.saveToolbarItem, [UIBarButtonItem wmf_barButtonItemOfFixedWidth:2.0],
         [self flexibleSpaceToolbarItem],
         self.tableOfContentsToolbarItem,
         nil];

    if (self.toolbarItems.count != toolbarItems.count) {
        // HAX: only update toolbar if # of items has changed, otherwise items will (somehow) get lost
        [self setToolbarItems:toolbarItems animated:YES];
    }
}

- (void)updateToolbarItemEnabledState {
    self.fontSizeToolbarItem.enabled        = [self canAdjustText];
    self.shareToolbarItem.enabled           = [self canShare];
    self.languagesToolbarItem.enabled       = [self hasLanguages];
    self.tableOfContentsToolbarItem.enabled = [self hasTableOfContents];
}

#pragma mark - Toolbar Items

- (UIBarButtonItem*)tableOfContentsToolbarItem {
    if (!_tableOfContentsToolbarItem) {
        _tableOfContentsToolbarItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"toc"]
                                                                       style:UIBarButtonItemStylePlain
                                                                      target:self
                                                                      action:@selector(showTableOfContents)];
        _tableOfContentsToolbarItem.accessibilityLabel = MWLocalizedString(@"table-of-contents-button-label", nil);
        return _tableOfContentsToolbarItem;
    }
    return _tableOfContentsToolbarItem;
}

- (UIBarButtonItem*)saveToolbarItem {
    if (!_saveToolbarItem) {
        _saveToolbarItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"save"] style:UIBarButtonItemStylePlain target:nil action:nil];
    }
    return _saveToolbarItem;
}

- (UIBarButtonItem*)flexibleSpaceToolbarItem {
    return [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
                                                         target:nil
                                                         action:NULL];
}

- (UIBarButtonItem*)fontSizeToolbarItem {
    if (!_fontSizeToolbarItem) {
        @weakify(self);
        _fontSizeToolbarItem = [[UIBarButtonItem alloc] bk_initWithImage:[UIImage imageNamed:@"font-size"]
                                                                   style:UIBarButtonItemStylePlain
                                                                 handler:^(id sender){
            @strongify(self);
            [self showFontSizePopup];
        }];
    }
    return _fontSizeToolbarItem;
}

- (UIBarButtonItem*)shareToolbarItem {
    if (!_shareToolbarItem) {
        @weakify(self);
        _shareToolbarItem = [[UIBarButtonItem alloc] bk_initWithBarButtonSystemItem:UIBarButtonSystemItemAction
                                                                            handler:^(id sender){
            @strongify(self);
            [self shareArticleWithTextSnippet:nil fromButton:self->_shareToolbarItem];
        }];
    }
    return _shareToolbarItem;
}

- (UIBarButtonItem*)languagesToolbarItem {
    if (!_languagesToolbarItem) {
        _languagesToolbarItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"language"]
                                                                 style:UIBarButtonItemStylePlain
                                                                target:self
                                                                action:@selector(showLanguagePicker)];
    }
    return _languagesToolbarItem;
}

#pragma mark - Article languages

- (void)showLanguagePicker {
    WMFArticleLanguagesViewController* languagesVC = [WMFArticleLanguagesViewController articleLanguagesViewControllerWithTitle:self.articleTitle];
    languagesVC.delegate = self;
    [self presentViewController:[[UINavigationController alloc] initWithRootViewController:languagesVC] animated:YES completion:nil];
}

- (void)languagesController:(WMFLanguagesViewController*)controller didSelectLanguage:(MWKLanguageLink*)language {
    [[PiwikTracker wmf_configuredInstance] wmf_logActionSwitchLanguageInContext:self contentType:nil];
    [self dismissViewControllerAnimated:YES completion:^{
        [self pushArticleViewControllerWithTitle:language.title contentType:nil animated:YES];
    }];
}

#pragma mark - Article Footers

- (void)updateWebviewFootersIfNeeded {
    NSMutableArray* footerVCs = [NSMutableArray arrayWithCapacity:2];
    [footerVCs wmf_safeAddObject:self.footerMenuViewController];
    /*
       NOTE: only include read more if it has results (don't want an empty section). conditionally fetched in `setArticle:`
     */
    if ([self hasReadMore] && [self.readMoreListViewController hasResults]) {
        [footerVCs addObject:self.readMoreListViewController];
        [self appendReadMoreTableOfContentsItemIfNeeded];
    }
    [self.webViewController setFooterViewControllers:footerVCs];
}

#pragma mark - Progress

- (void)addProgressView {
    NSAssert(!self.progressView.superview, @"Illegal attempt to re-add progress view.");
    if (self.navigationController.navigationBarHidden) {
        return;
    }
    [self.view addSubview:self.progressView];
    [self.progressView mas_makeConstraints:^(MASConstraintMaker* make) {
        make.top.equalTo(self.progressView.superview.mas_top);
        make.left.equalTo(self.progressView.superview.mas_left);
        make.right.equalTo(self.progressView.superview.mas_right);
        make.height.equalTo(@2.0);
    }];
}

- (void)removeProgressView {
    [self.progressView removeFromSuperview];
}

- (void)showProgressViewAnimated:(BOOL)animated {
    self.progressView.progress = 0.05;

    if (!animated) {
        [self _showProgressView];
        return;
    }

    [UIView animateWithDuration:0.25 animations:^{
        [self _showProgressView];
    } completion:^(BOOL finished) {
    }];
}

- (void)_showProgressView {
    self.progressView.alpha = 1.0;
}

- (void)hideProgressViewAnimated:(BOOL)animated {
    if (!animated) {
        [self _hideProgressView];
        return;
    }

    [UIView animateWithDuration:0.25 animations:^{
        [self _hideProgressView];
    } completion:nil];
}

- (void)_hideProgressView {
    self.progressView.alpha = 0.0;
}

- (void)updateProgress:(CGFloat)progress animated:(BOOL)animated {
    if (progress < self.progressView.progress) {
        return;
    }
    [self.progressView setProgress:progress animated:animated];

    [self.delegate articleController:self didUpdateArticleLoadProgress:progress animated:animated];
}

- (void)completeAndHideProgressWithCompletion:(nullable dispatch_block_t)completion {
    [self updateProgress:1.0 animated:YES];
    dispatchOnMainQueueAfterDelayInSeconds(0.5, ^{
        [self hideProgressViewAnimated:YES];
        if (completion) {
            completion();
        }
    });
}

/**
 *  Some of the progress is in loading the HTML into the webview
 *  This leaves 20% of progress for that work.
 */
- (CGFloat)totalProgressWithArticleFetcherProgress:(CGFloat)progress {
    return 0.1 + (0.7 * progress);
}

#pragma mark - Significantly Viewed Timer

- (void)startSignificantlyViewedTimer {
    if (self.significantlyViewedTimer) {
        return;
    }
    if (!self.article) {
        return;
    }
    MWKHistoryList* historyList = self.dataStore.userDataStore.historyList;
    MWKHistoryEntry* entry      = [historyList entryForTitle:self.articleTitle];
    if (!entry.titleWasSignificantlyViewed) {
        self.significantlyViewedTimer = [NSTimer scheduledTimerWithTimeInterval:FBTweakValue(@"Explore", @"Related items", @"Required viewing time", 30.0) target:self selector:@selector(significantlyViewedTimerFired:) userInfo:nil repeats:NO];
    }
}

- (void)significantlyViewedTimerFired:(NSTimer*)timer {
    [self stopSignificantlyViewedTimer];
    MWKHistoryList* historyList = self.dataStore.userDataStore.historyList;
    [historyList setSignificantlyViewedOnPageInHistoryWithTitle:self.articleTitle];
    [historyList save];
}

- (void)stopSignificantlyViewedTimer {
    [self.significantlyViewedTimer invalidate];
    self.significantlyViewedTimer = nil;
}

#pragma mark - Title Button

- (void)setUpTitleBarButton {
    UIButton* b = [UIButton buttonWithType:UIButtonTypeCustom];
    [b adjustsImageWhenHighlighted];
    UIImage* w = [UIImage imageNamed:@"W"];
    [b setImage:w forState:UIControlStateNormal];
    [b sizeToFit];
    @weakify(self);
    [b bk_addEventHandler:^(id sender) {
        @strongify(self);
        [self.navigationController popToRootViewControllerAnimated:YES];
    } forControlEvents:UIControlEventTouchUpInside];
    self.navigationItem.titleView                        = b;
    self.navigationItem.titleView.isAccessibilityElement = YES;
    self.navigationItem.titleView.accessibilityLabel     = MWLocalizedString(@"home-button-accessibility-label", nil);
    self.navigationItem.titleView.accessibilityTraits   |= UIAccessibilityTraitButton;
}

#pragma mark - ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.navigationController.toolbar wmf_applySolidWhiteBackgroundWithTopShadow];

    [self updateToolbar];

    [self setUpTitleBarButton];
    self.view.clipsToBounds                   = NO;
    self.automaticallyAdjustsScrollViewInsets = YES;

    self.navigationItem.rightBarButtonItem = [self wmf_searchBarButtonItem];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillResignActiveWithNotification:) name:UIApplicationWillResignActiveNotification object:nil];

    [self setupWebView];
    [self addProgressView];
    [self hideProgressViewAnimated:NO];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self registerForPreviewingIfAvailable];

    if (!self.skipFetchOnViewDidAppear) {
        [self fetchArticleIfNeeded];
    }
    self.skipFetchOnViewDidAppear = NO;
    [self startSignificantlyViewedTimer];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [[NSUserDefaults standardUserDefaults] wmf_setOpenArticleTitle:self.articleTitle];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];

    [self stopSignificantlyViewedTimer];
    [self saveWebViewScrollOffset];
    [self removeProgressView];
    //HACK: we are dispatching this because viewWillDisappear is called even when the app is being terminated.
    //We use the open article to restore the current article on launch, so doing this is not acceptable
    //By dispatching we make sure the code in the block is never executed when the app closes (but is called otherwise)
    //(it will not wait for a pending GCD call)
    //We should move to the restoration APIs for restoring the open article to get aroudn this.
    //NOTE: this method is not invoked when moving to the background
    dispatchOnMainQueueAfterDelayInSeconds(1.0, ^{
        if ([[[NSUserDefaults standardUserDefaults] wmf_openArticleTitle] isEqualToTitle:self.articleTitle]) {
            [[NSUserDefaults standardUserDefaults] wmf_setOpenArticleTitle:nil];
        }
    });
}

- (void)traitCollectionDidChange:(nullable UITraitCollection*)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.presentedViewController isKindOfClass:[WMFFontSliderViewController class]]) {
        [self.presentedViewController dismissViewControllerAnimated:YES completion:nil];
    }
    [self registerForPreviewingIfAvailable];
}

#pragma mark - Web View Setup

- (void)setupWebView {
    [self addChildViewController:self.webViewController];
    [self.view addSubview:self.webViewController.view];
    [self.webViewController.view mas_makeConstraints:^(MASConstraintMaker* make) {
        make.leading.trailing.top.and.bottom.equalTo(self.view);
    }];
    [self.webViewController didMoveToParentViewController:self];

    self.pullToRefresh         = [[UIRefreshControl alloc] init];
    self.pullToRefresh.enabled = [self canRefresh];
    [self.pullToRefresh addTarget:self action:@selector(fetchArticle) forControlEvents:UIControlEventValueChanged];
    [self.webViewController.webView.scrollView addSubview:_pullToRefresh];
}

#pragma mark - Save Offset

- (void)saveWebViewScrollOffset {
    // Don't record scroll position of "main" pages.
    if (self.article.isMain) {
        return;
    }
    CGFloat offset = [self.webViewController currentVerticalOffset];
    if (offset > 0) {
        [self.recentPages setPageScrollPosition:offset onPageInHistoryWithTitle:self.articleTitle];
        [self.recentPages save];
    }
}

#pragma mark - Article Fetching

- (void)fetchArticleForce:(BOOL)force {
    NSAssert([[NSThread currentThread] isMainThread], @"Not on main thread!");
    NSAssert(self.isViewLoaded, @"Should only fetch article when view is loaded so we can update its state.");
    if (!force && self.article) {
        return;
    }

    //only show a blank view if we have nothing to show
    if (!self.article) {
        [self wmf_showEmptyViewOfType:WMFEmptyViewTypeBlank];
        [self.view bringSubviewToFront:self.progressView];
    }

    [self showProgressViewAnimated:YES];
    [self unobserveArticleUpdates];

    @weakify(self);
    self.articleFetcherPromise = [self.articleFetcher fetchLatestVersionOfTitleIfNeeded:self.articleTitle progress:^(CGFloat progress) {
        [self updateProgress:[self totalProgressWithArticleFetcherProgress:progress] animated:YES];
    }].then(^(MWKArticle* article) {
        @strongify(self);
        [self updateProgress:[self totalProgressWithArticleFetcherProgress:1.0] animated:YES];
        self.article = article;
        /*
           NOTE(bgerstle): add side effects to setArticle, not here. this ensures they happen even when falling back to
           cached content
         */
    }).catch(^(NSError* error){
        @strongify(self);
        DDLogError(@"Article Fetch Error: %@", [error localizedDescription]);
        [self hideProgressViewAnimated:YES];
        [self.delegate articleControllerDidLoadArticle:self];

        MWKArticle* cachedFallback = error.userInfo[WMFArticleFetcherErrorCachedFallbackArticleKey];
        if (cachedFallback) {
            self.article = cachedFallback;
            if (![error wmf_isNetworkConnectionError]) {
                // don't show offline banner for cached articles
                [[WMFAlertManager sharedInstance] showErrorAlert:error
                                                          sticky:NO
                                           dismissPreviousAlerts:NO
                                                     tapCallBack:NULL];
            }
        } else {
            [self wmf_showEmptyViewOfType:WMFEmptyViewTypeArticleDidNotLoad];
            [self.view bringSubviewToFront:self.progressView];
            [[WMFAlertManager sharedInstance] showErrorAlert:error
                                                      sticky:NO
                                       dismissPreviousAlerts:NO
                                                 tapCallBack:NULL];

            if ([error wmf_isNetworkConnectionError]) {
                @weakify(self);
                SCNetworkReachability().then(^{
                    @strongify(self);
                    [self fetchArticleIfNeeded];
                });
            }
        }
    }).finally(^{
        @strongify(self);
        self.articleFetcherPromise = nil;
    });
}

- (void)fetchArticle {
    [self fetchArticleForce:YES];
    [self.pullToRefresh endRefreshing];
}

- (void)fetchArticleIfNeeded {
    [self fetchArticleForce:NO];
}

- (void)fetchReadMoreIfNeeded {
    if (![self hasReadMore]) {
        return;
    }

    @weakify(self);
    [self.readMoreListViewController fetchIfNeeded].then(^{
        @strongify(self);
        if (!self) {
            return;
        }
        // update footers to include read more if there are results
        [self updateWebviewFootersIfNeeded];
    })
    .catch(^(NSError* error){
        DDLogError(@"Read More Fetch Error: %@", error);
        WMF_TECH_DEBT_TODO(show read more w / an error view and allow user to retry ? );
    });
}

#pragma mark - Share

- (void)shareAFactWithTextSnippet : (nullable NSString*)text {
    if (self.shareOptionsController.isActive) {
        return;
    }
    [self.shareOptionsController presentShareOptionsWithSnippet:text inViewController:self fromBarButtonItem:self.shareToolbarItem];
}

- (void)shareArticleFromButton:(nullable UIBarButtonItem*)button {
    [self shareArticleWithTextSnippet:nil fromButton:button];
}

- (void)shareArticleWithTextSnippet:(nullable NSString*)text fromButton:(UIBarButtonItem*)button {
    NSParameterAssert(button);
    if (!button) {
        //If we get no button, we will crash below on iPad
        //The assert above shoud help, but lets make sure we bail in prod
        return;
    }
    [self.shareFunnel logShareButtonTappedResultingInSelection:text];

    NSMutableArray* items = [NSMutableArray array];

    [items addObject:[[WMFArticleTextActivitySource alloc] initWithArticle:self.article shareText:text]];

    if (self.article.title.desktopURL) {
        NSURL* url = [[NSURL alloc] initWithString:[NSString stringWithFormat:@"%@?%@",
                                                    self.article.title.desktopURL.absoluteString,
                                                    @"wprov=sfsi1"]];

        [items addObject:url];
    }

    UIActivityViewController* vc               = [[UIActivityViewController alloc] initWithActivityItems:items applicationActivities:@[[[TUSafariActivity alloc] init]]];
    UIPopoverPresentationController* presenter = [vc popoverPresentationController];
    presenter.barButtonItem = button;

    [self presentViewController:vc animated:YES completion:NULL];
}

#pragma mark - Font Size

- (void)showFontSizePopup {
    NSArray* fontSizes = self.fontSizeMultipliers;
    NSUInteger index   = self.indexOfCurrentFontSize;

    WMFFontSliderViewController* vc = [[WMFFontSliderViewController alloc] initWithNibName:@"WMFFontSliderViewController" bundle:nil];
    vc.preferredContentSize   = vc.view.frame.size;
    vc.modalPresentationStyle = UIModalPresentationPopover;
    vc.delegate               = self;

    [vc setValuesWithSteps:fontSizes.count current:index];

    UIPopoverPresentationController* presenter = [vc popoverPresentationController];
    presenter.delegate                 = self;
    presenter.backgroundColor          = vc.view.backgroundColor;
    presenter.barButtonItem            = self.fontSizeToolbarItem;
    presenter.permittedArrowDirections = UIPopoverArrowDirectionDown;

    [self presentViewController:vc animated:YES completion:nil];
}

- (UIModalPresentationStyle)adaptivePresentationStyleForPresentationController:(UIPresentationController*)controller {
    return UIModalPresentationNone;
}

- (void)sliderValueChangedInController:(WMFFontSliderViewController*)container value:(NSInteger)value {
    NSArray* fontSizes = self.fontSizeMultipliers;

    if (value > fontSizes.count) {
        return;
    }

    [self.webViewController setFontSizeMultiplier:self.fontSizeMultipliers[value]];
}

- (NSArray<NSNumber*>*)fontSizeMultipliers {
    return @[@(FBTweakValue(@"Article", @"Font Size", @"Step 1", 70)),
             @(FBTweakValue(@"Article", @"Font Size", @"Step 2", 85)),
             @(FBTweakValue(@"Article", @"Font Size", @"Step 3", 100)),
             @(FBTweakValue(@"Article", @"Font Size", @"Step 4", 115)),
             @(FBTweakValue(@"Article", @"Font Size", @"Step 5", 130)),
             @(FBTweakValue(@"Article", @"Font Size", @"Step 6", 145)),
             @(FBTweakValue(@"Article", @"Font Size", @"Step 7", 160))
    ];
}

- (NSUInteger)indexOfCurrentFontSize {
    NSNumber* fontSize = [[NSUserDefaults standardUserDefaults] wmf_readingFontSize];

    NSUInteger index = [[self fontSizeMultipliers] indexOfObject:fontSize];

    if (index == NSNotFound) {
        index = [[[self fontSizeMultipliers] bk_reduce:@(NSIntegerMax) withBlock:^id (NSNumber* current, NSNumber* obj) {
            NSUInteger currentDistance = current.integerValue;
            NSUInteger objDistance = abs((int)(obj.integerValue - fontSize.integerValue));
            if (objDistance < currentDistance) {
                return obj;
            } else {
                return current;
            }
        }] integerValue];
    }

    return index;
}

#pragma mark - Scroll Position and Fragments

- (void)scrollWebViewToRequestedPosition {
    if (self.articleTitle.fragment) {
        [self.webViewController scrollToFragment:self.articleTitle.fragment];
    } else if (self.restoreScrollPositionOnArticleLoad && self.historyEntry.scrollPosition > 0) {
        self.restoreScrollPositionOnArticleLoad = NO;
        [self.webViewController scrollToVerticalOffset:self.historyEntry.scrollPosition];
    }
    [self markFragmentAsProcessed];
}

- (void)markFragmentAsProcessed {
    //Create a title without the fragment so it wont be followed anymore
    self.articleTitle = [[MWKTitle alloc] initWithSite:self.articleTitle.site normalizedTitle:self.articleTitle.text fragment:nil];
}

#pragma mark - WebView Transition

- (void)showWebViewAtFragment:(NSString*)fragment animated:(BOOL)animated {
    [self.webViewController scrollToFragment:fragment];
}

#pragma mark - WMFWebViewControllerDelegate

- (void)         webViewController:(WebViewController*)controller
    didTapImageWithSourceURLString:(nonnull NSString*)imageSourceURLString {
    MWKImage* selectedImage                                = [[MWKImage alloc] initWithArticle:self.article sourceURLString:imageSourceURLString];
    WMFArticleImageGalleryViewContoller* fullscreenGallery = [[WMFArticleImageGalleryViewContoller alloc] initWithArticle:self.article selectedImage:selectedImage];
    [self presentViewController:fullscreenGallery animated:YES completion:nil];
}

- (void)webViewController:(WebViewController*)controller didLoadArticle:(MWKArticle*)article {
    [self completeAndHideProgressWithCompletion:^{
        //Without this pause, the motion happens too soon after loading the article
        dispatchOnMainQueueAfterDelayInSeconds(0.5, ^{
            [self peekTableOfContentsIfNeccesary];
        });
    }];
    [self scrollWebViewToRequestedPosition];
    [self.delegate articleControllerDidLoadArticle:self];
    [self fetchReadMoreIfNeeded];
}

- (void)webViewController:(WebViewController*)controller didTapEditForSection:(MWKSection*)section {
    [self showEditorForSection:section];
}

- (void)webViewController:(WebViewController*)controller didTapOnLinkForTitle:(MWKTitle*)title {
    [self pushArticleViewControllerWithTitle:title contentType:nil animated:YES];
}

- (void)webViewController:(WebViewController*)controller didSelectText:(NSString*)text {
    [self.shareFunnel logHighlight];
}

- (void)webViewController:(WebViewController*)controller didTapShareWithSelectedText:(NSString*)text {
    [self shareAFactWithTextSnippet:text];
}

- (nullable NSString*)webViewController:(WebViewController*)controller titleForFooterViewController:(UIViewController*)footerViewController {
    if (footerViewController == self.readMoreListViewController) {
        return [MWSiteLocalizedString(self.articleTitle.site, @"article-read-more-title", nil) uppercaseStringWithLocale:[NSLocale currentLocale]];
    } else if (footerViewController == self.footerMenuViewController) {
        return [MWSiteLocalizedString(self.articleTitle.site, @"article-about-title", nil) uppercaseStringWithLocale:[NSLocale currentLocale]];
    }
    return nil;
}

#pragma mark - Header Tap Gesture

- (void)imageViewDidTap:(UITapGestureRecognizer*)tap {
    NSAssert(self.article.isCached, @"Expected article data to already be downloaded.");
    if (!self.article.isCached) {
        return;
    }

    WMFArticleImageGalleryViewContoller* fullscreenGallery = [[WMFArticleImageGalleryViewContoller alloc] initWithArticle:self.article];
    fullscreenGallery.referenceViewDelegate = self;
    [self presentViewController:fullscreenGallery animated:YES completion:nil];
}

#pragma mark - WMFImageGalleryViewContollerReferenceViewDelegate

- (UIImageView*)referenceViewForImageController:(WMFArticleImageGalleryViewContoller*)controller {
    MWKImage* currentImage = [controller currentImage];
    MWKImage* leadImage    = self.article.leadImage;
    if ([currentImage isEqualToImage:leadImage] || [currentImage isVariantOfImage:leadImage]) {
        return self.headerImageView;
    } else {
        return nil;
    }
}

#pragma mark - Edit Section

- (void)showEditorForSection:(MWKSection*)section {
    if (self.article.editable) {
        SectionEditorViewController* sectionEditVC = [SectionEditorViewController wmf_initialViewControllerFromClassStoryboard];
        sectionEditVC.section  = section;
        sectionEditVC.delegate = self;
        UINavigationController* nc = [[UINavigationController alloc] initWithRootViewController:sectionEditVC];
        [self presentViewController:nc animated:YES completion:NULL];
    } else {
        ProtectedEditAttemptFunnel* funnel = [[ProtectedEditAttemptFunnel alloc] init];
        [funnel logProtectionStatus:[[self.article.protection allowedGroupsForAction:@"edit"] componentsJoinedByString:@","]];
        [self showProtectedDialog];
    }
}

- (void)showProtectedDialog {
    UIAlertView* alert = [[UIAlertView alloc] init];
    alert.title   = MWLocalizedString(@"page_protected_can_not_edit_title", nil);
    alert.message = MWLocalizedString(@"page_protected_can_not_edit", nil);
    [alert addButtonWithTitle:@"OK"];
    alert.cancelButtonIndex = 0;
    [alert show];
}

#pragma mark - SectionEditorViewControllerDelegate

- (void)sectionEditorFinishedEditing:(SectionEditorViewController*)sectionEditorViewController {
    self.skipFetchOnViewDidAppear = YES;
    [self dismissViewControllerAnimated:YES completion:NULL];
    [self fetchArticle];
}

#pragma mark - UIViewControllerPreviewingDelegate

- (void)registerForPreviewingIfAvailable {
    [self wmf_ifForceTouchAvailable:^{
        [self unregisterForPreviewing];
        UIView* previewView = [self.webViewController.webView wmf_browserView];
        self.linkPreviewingContext =
            [self registerForPreviewingWithDelegate:self sourceView:previewView];
        for (UIGestureRecognizer* r in previewView.gestureRecognizers) {
            [r requireGestureRecognizerToFail:self.linkPreviewingContext.previewingGestureRecognizerForFailureRelationship];
        }
    } unavailable:^{
        [self unregisterForPreviewing];
    }];
}

- (void)unregisterForPreviewing {
    if (self.linkPreviewingContext) {
        [self unregisterForPreviewingWithContext:self.linkPreviewingContext];
        self.linkPreviewingContext = nil;
    }
}

- (nullable UIViewController*)previewingContext:(id<UIViewControllerPreviewing>)previewingContext
                      viewControllerForLocation:(CGPoint)location {
    JSValue* peekElement = [self.webViewController htmlElementAtLocation:location];
    if (!peekElement) {
        return nil;
    }

    NSURL* peekURL = [self.webViewController urlForHTMLElement:peekElement];
    if (!peekURL) {
        return nil;
    }

    UIViewController* peekVC = [self viewControllerForPreviewURL:peekURL];
    if (peekVC) {
        [[PiwikTracker wmf_configuredInstance] wmf_logActionPreviewInContext:self contentType:nil];
        self.webViewController.isPeeking = YES;
        previewingContext.sourceRect     = [self.webViewController rectForHTMLElement:peekElement];
        return peekVC;
    }

    return nil;
}

- (UIViewController*)viewControllerForPreviewURL:(NSURL*)url {
    if ([url.absoluteString isEqualToString:@""]) {
        return nil;
    }
    if (![url wmf_isInternalLink]) {
        if ([url wmf_isCitation]) {
            return nil;
        }
        if ([url.scheme hasPrefix:@"http"]) {
            return [[SFSafariViewController alloc] initWithURL:url];
        }
    } else {
        if (![url wmf_isIntraPageFragment]) {
            return [[WMFArticleViewController alloc] initWithArticleTitle:[[MWKTitle alloc] initWithURL:url]
                                                                dataStore:self.dataStore];
        }
    }
    return nil;
}

- (void)previewingContext:(id<UIViewControllerPreviewing>)previewingContext
     commitViewController:(UIViewController*)viewControllerToCommit {
    if ([viewControllerToCommit isKindOfClass:[WMFArticleViewController class]]) {
        [self pushArticleViewController:(WMFArticleViewController*)viewControllerToCommit contentType:nil animated:YES];
    } else {
        [self presentViewController:viewControllerToCommit animated:YES completion:nil];
    }
}

#pragma mark - Article Navigation


- (void)pushArticleViewController:(WMFArticleViewController*)articleViewController contentType:(nullable id<WMFAnalyticsContentTypeProviding>)contentType animated:(BOOL)animated {
    [[PiwikTracker wmf_configuredInstance] wmf_logActionTapThroughInContext:self contentType:contentType];
    [self wmf_pushArticleViewController:articleViewController animated:YES];
}

- (void)pushArticleViewControllerWithTitle:(MWKTitle*)title contentType:(nullable id<WMFAnalyticsContentTypeProviding>)contentType animated:(BOOL)animated {
    WMFArticleViewController* articleViewController =
        [[WMFArticleViewController alloc] initWithArticleTitle:title
                                                     dataStore:self.dataStore];
    [self pushArticleViewController:articleViewController contentType:contentType animated:animated];
}

#pragma mark - WMFArticleListTableViewControllerDelegate

- (void)listViewContoller:(WMFArticleListTableViewController*)listController didSelectTitle:(MWKTitle*)title {
    if ([self presentedViewController]) {
        [self dismissViewControllerAnimated:YES completion:NULL];
    }
    id<WMFAnalyticsContentTypeProviding> contentType = nil;
    if ([listController conformsToProtocol:@protocol(WMFAnalyticsContentTypeProviding)]) {
        contentType = (id<WMFAnalyticsContentTypeProviding>)listController;
    }
    [self pushArticleViewControllerWithTitle:title contentType:contentType animated:YES];
}

- (UIViewController*)listViewContoller:(WMFArticleListTableViewController*)listController viewControllerForPreviewingTitle:(MWKTitle*)title {
    return [[WMFArticleViewController alloc] initWithArticleTitle:title
                                                        dataStore:self.dataStore];
}

- (void)listViewContoller:(WMFArticleListTableViewController*)listController didCommitToPreviewedViewController:(UIViewController*)viewController {
    if ([self presentedViewController]) {
        [self dismissViewControllerAnimated:YES completion:NULL];
    }
    if ([viewController isKindOfClass:[WMFArticleViewController class]]) {
        id<WMFAnalyticsContentTypeProviding> contentType = nil;
        if ([listController conformsToProtocol:@protocol(WMFAnalyticsContentTypeProviding)]) {
            contentType = (id<WMFAnalyticsContentTypeProviding>)listController;
        }
        [self pushArticleViewController:(WMFArticleViewController*)viewController contentType:contentType animated:YES];
    } else {
        [self presentViewController:viewController animated:YES completion:nil];
    }
}

#pragma mark - WMFAnalyticsContextProviding

- (NSString*)analyticsContext {
    return @"Article";
}

- (NSString*)analyticsName {
    return [self.articleTitle.site urlDomainWithLanguage];
}

@end

NS_ASSUME_NONNULL_END
