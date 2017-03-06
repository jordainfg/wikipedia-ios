#import "WMFExploreViewController.h"

#import "Wikipedia-Swift.h"

#import <Masonry/Masonry.h>

#import "PiwikTracker+WMFExtensions.h"

#import "WMFContentGroupDataStore.h"
#import "MWKDataStore.h"
#import "WMFArticleDataStore.h"
#import "MWKLanguageLinkController.h"

#import "WMFLocationManager.h"
#import "CLLocation+WMFBearing.h"

#import "WMFContentGroup+WMFFeedContentDisplaying.h"
#import "MWKHistoryEntry.h"

#import "WMFFeedArticlePreview.h"
#import "WMFFeedNewsStory.h"
#import "WMFFeedImage.h"
#import "WMFAnnouncement.h"

#import "WMFSaveButtonController.h"

#import "WMFColumnarCollectionViewLayout.h"

#import "UIFont+WMFStyle.h"
#import "UIViewController+WMFEmptyView.h"
#import "UIView+WMFDefaultNib.h"

#import "WMFExploreSectionHeader.h"
#import "WMFExploreSectionFooter.h"
#import "WMFFeedNotificationHeader.h"

#import "WMFLeadingImageTrailingTextButton.h"

#import "WMFArticleListCollectionViewCell.h"
#import "WMFArticlePreviewCollectionViewCell.h"
#import "WMFPicOfTheDayCollectionViewCell.h"
#import "WMFNearbyArticleCollectionViewCell.h"
#import "WMFAnnouncementCollectionViewCell.h"

#import "UIViewController+WMFArticlePresentation.h"
#import "UIViewController+WMFSearch.h"

#import "WMFArticleViewController.h"
#import "WMFImageGalleryViewController.h"
#import "WMFRandomArticleViewController.h"
#import "WMFFirstRandomViewController.h"
#import "WMFMorePageListViewController.h"
#import "WMFSettingsViewController.h"
#import "WMFAnnouncement.h"
#import "NSProcessInfo+WMFOperatingSystemVersionChecks.h"
#import "WMFChange.h"

#import "WMFCVLAttributes.h"

@import BlocksKitUIKitExtensions;

NS_ASSUME_NONNULL_BEGIN

static NSString *const WMFFeedEmptyHeaderFooterReuseIdentifier = @"WMFFeedEmptyHeaderFooterReuseIdentifier";

static const NSTimeInterval WMFFeedRefreshTimeoutInterval = 12;

@interface WMFExploreViewController () <WMFLocationManagerDelegate, NSFetchedResultsControllerDelegate, WMFColumnarCollectionViewLayoutDelegate, WMFArticlePreviewingActionsDelegate, UIViewControllerPreviewingDelegate, WMFAnnouncementCollectionViewCellDelegate, UICollectionViewDataSourcePrefetching>

@property (nonatomic, strong) WMFLocationManager *locationManager;

@property (nonatomic, strong) NSFetchedResultsController *fetchedResultsController;

@property (nonatomic, strong) UIRefreshControl *refreshControl;

@property (nonatomic, strong, nullable) WMFContentGroup *groupForPreviewedCell;

@property (nonatomic, weak) id<UIViewControllerPreviewing> previewingContext;

@property (nonatomic, strong) WMFContentGroupDataStore *internalContentStore;

@property (nonatomic, strong, nullable) WMFFeedNotificationHeader *notificationHeader;

@property (nonatomic, strong, nullable) AFNetworkReachabilityManager *reachabilityManager;

@property (nonatomic, strong) NSMutableArray<WMFSectionChange *> *sectionChanges;
@property (nonatomic, strong) NSMutableArray<WMFObjectChange *> *objectChanges;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *sectionCounts;

@property (nonatomic, strong, nullable) WMFTaskGroup *feedUpdateTaskGroup;
@property (nonatomic, strong, nullable) WMFTaskGroup *relatedUpdatedTaskGroup;
@property (nonatomic, strong, nullable) WMFTaskGroup *nearbyUpdateTaskGroup;

@property (nonatomic, strong) NSMutableDictionary<NSString *, WMFExploreCollectionViewCell *> *placeholderCells;
@property (nonatomic, strong) NSMutableDictionary<NSString *, WMFExploreCollectionReusableView *> *placeholderFooters;

@property (nonatomic, strong) NSMutableDictionary<NSIndexPath *, NSURL *> *prefetchURLsByIndexPath;

@end

@implementation WMFExploreViewController

- (void)awakeFromNib {
    [super awakeFromNib];
    self.title = MWLocalizedString(@"home-title", nil);
    self.sectionChanges = [NSMutableArray arrayWithCapacity:10];
    self.objectChanges = [NSMutableArray arrayWithCapacity:10];
    self.sectionCounts = [NSMutableArray arrayWithCapacity:100];
    self.placeholderCells = [NSMutableDictionary dictionaryWithCapacity:10];
    self.placeholderFooters = [NSMutableDictionary dictionaryWithCapacity:10];
    self.prefetchURLsByIndexPath = [NSMutableDictionary dictionaryWithCapacity:10];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (UIButton *)titleButton {
    return (UIButton *)self.navigationItem.titleView;
}

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder {
    self = [super initWithCoder:aDecoder];
    if (self) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        [b adjustsImageWhenHighlighted];
        UIImage *w = [UIImage imageNamed:@"W"];
        [b setImage:w forState:UIControlStateNormal];
        [b sizeToFit];
        @weakify(self);
        [b bk_addEventHandler:^(id sender) {
            @strongify(self);
            [self.collectionView setContentOffset:CGPointZero animated:YES];
        }
              forControlEvents:UIControlEventTouchUpInside];
        self.navigationItem.titleView = b;
        self.navigationItem.titleView.isAccessibilityElement = YES;

        self.navigationItem.titleView.accessibilityTraits |= UIAccessibilityTraitHeader;
        self.navigationItem.leftBarButtonItem = [self settingsBarButtonItem];
        self.navigationItem.rightBarButtonItem = [self wmf_searchBarButtonItem];
    }
    return self;
}

#pragma mark - Accessors

- (void)setRefreshControl:(UIRefreshControl *)refreshControl {
    [_refreshControl removeFromSuperview];

    _refreshControl = refreshControl;

    if (_refreshControl) {
        _refreshControl.layer.zPosition = -100;
        if ([self.collectionView respondsToSelector:@selector(setRefreshControl:)]) {
            self.collectionView.refreshControl = _refreshControl;
        } else {
            [self.collectionView addSubview:_refreshControl];
        }
    }
}

- (UIBarButtonItem *)settingsBarButtonItem {
    return [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"settings"]
                                            style:UIBarButtonItemStylePlain
                                           target:self
                                           action:@selector(didTapSettingsButton:)];
}

- (WMFContentGroupDataStore *)internalContentStore {
    if (_internalContentStore == nil) {
        _internalContentStore = [[WMFContentGroupDataStore alloc] initWithDataStore:self.userStore];
    }
    return _internalContentStore;
}

- (MWKSavedPageList *)savedPages {
    NSParameterAssert(self.userStore);
    return self.userStore.savedPageList;
}

- (MWKHistoryList *)history {
    NSParameterAssert(self.userStore);
    return self.userStore.historyList;
}

- (WMFLocationManager *)locationManager {
    if (!_locationManager) {
        _locationManager = [WMFLocationManager fineLocationManager];
        _locationManager.delegate = self;
    }
    return _locationManager;
}

- (NSURL *)currentSiteURL {
    return [[[MWKLanguageLinkController sharedInstance] appLanguage] siteURL];
}

- (NSUInteger)numberOfSectionsInExploreFeed {
    return [self.fetchedResultsController.sections.firstObject numberOfObjects];
}

- (BOOL)canScrollToTop {
    WMFContentGroup *group = [self sectionAtIndex:0];
    NSParameterAssert(group);
    NSArray *content = group.content;
    return [content count] > 0;
}

#pragma mark - Actions

- (void)didTapSettingsButton:(UIBarButtonItem *)sender {
    [self showSettings];
}

- (void)showSettings {
    UINavigationController *settingsContainer =
        [[UINavigationController alloc] initWithRootViewController:
                                            [WMFSettingsViewController settingsViewControllerWithDataStore:self.userStore
                                                                                              previewStore:self.previewStore]];
    [self presentViewController:settingsContainer
                       animated:YES
                     completion:nil];
}

#pragma mark - Feed Sources

- (void)updateRelatedPages {
    WMFAssertMainThread(@"updateRelatedPages must be called on the main thread");
    if (self.relatedUpdatedTaskGroup) {
        return;
    }
    WMFTaskGroup *group = [WMFTaskGroup new];
    self.relatedUpdatedTaskGroup = group;
    [self.contentSources enumerateObjectsUsingBlock:^(id<WMFContentSource> _Nonnull obj, NSUInteger idx, BOOL *_Nonnull stop) {
        if ([obj isKindOfClass:[WMFRelatedPagesContentSource class]]) {
            [group enter];
            [obj loadNewContentForce:NO
                          completion:^{
                              [group leave];
                          }];
        }
    }];

    [group waitInBackgroundWithTimeout:WMFFeedRefreshTimeoutInterval
                            completion:^{
                                WMFAssertMainThread(@"completion must be called on the main thread");
                                self.relatedUpdatedTaskGroup = nil;
                            }];
}

- (void)updateNearby:(nullable dispatch_block_t)completion {
    WMFAssertMainThread(@"updateNearby: must be called on the main thread");
    if (self.nearbyUpdateTaskGroup || self.feedUpdateTaskGroup) {
        return;
    }
    WMFTaskGroup *group = [WMFTaskGroup new];
    self.nearbyUpdateTaskGroup = group;
    [self.contentSources enumerateObjectsUsingBlock:^(id<WMFContentSource> _Nonnull obj, NSUInteger idx, BOOL *_Nonnull stop) {
        if ([obj isKindOfClass:[WMFNearbyContentSource class]]) {
            [group enter];
            [obj loadNewContentForce:NO
                          completion:^{
                              [group leave];
                          }];
        }
    }];

    [group waitInBackgroundWithTimeout:WMFFeedRefreshTimeoutInterval
                            completion:^{
                                WMFAssertMainThread(@"completion must be called on the main thread");
                                self.nearbyUpdateTaskGroup = nil;
                                if (completion) {
                                    completion();
                                }
                            }];
}

- (void)updateFeedSources:(nullable dispatch_block_t)completion {
    WMFAssertMainThread(@"updateFeedSources: must be called on the main thread");
    if (self.feedUpdateTaskGroup) {
        if (completion) {
            completion();
        }
        return;
    }
    if (!self.refreshControl.isRefreshing) {
        [self.refreshControl beginRefreshing];
    }
    WMFTaskGroup *group = [WMFTaskGroup new];
    self.feedUpdateTaskGroup = group;
#if DEBUG
    NSMutableSet *entered = [NSMutableSet setWithCapacity:self.contentSources.count];
#endif
    [self.contentSources enumerateObjectsUsingBlock:^(id<WMFContentSource> _Nonnull obj, NSUInteger idx, BOOL *_Nonnull stop) {
        //TODO: nearby doesnt always fire
        [group enter];
#if DEBUG
        NSString *classString = NSStringFromClass([obj class]);
        [entered addObject:classString];
#endif

        [obj loadNewContentForce:NO
                      completion:^{
#if DEBUG
                          assert([entered containsObject:classString]);
                          [entered removeObject:classString];
#endif
                          [group leave];
                      }];
    }];

    [group waitInBackgroundWithTimeout:WMFFeedRefreshTimeoutInterval
                            completion:^{
                                NSError *saveError = nil;
                                if (![self.userStore save:&saveError]) {
                                    DDLogError(@"Error saving: %@", saveError);
                                }
                                [[NSUserDefaults wmf_userDefaults] wmf_setFeedRefreshDate:[NSDate date]];
                                [self resetRefreshControl];
                                [self startMonitoringReachabilityIfNeeded];
                                [self showOfflineEmptyViewIfNeeded];
                                [self showHideNotificationIfNeccesary];
                                self.feedUpdateTaskGroup = nil;
                                if (completion) {
                                    completion();
                                }

#if DEBUG
                                if ([entered count] > 0) {
                                    DDLogError(@"Didn't leave: %@", entered);
                                }
#endif
                            }];
}

#pragma mark - Section Access

- (nullable WMFContentGroup *)sectionAtIndex:(NSUInteger)sectionIndex {
    id<NSFetchedResultsSectionInfo> section = [[self.fetchedResultsController sections] firstObject];
    if (sectionIndex >= [section numberOfObjects]) {
        return nil;
    }
    return (WMFContentGroup *)[self.fetchedResultsController objectAtIndexPath:[NSIndexPath indexPathForRow:sectionIndex inSection:0]];
}

- (nullable WMFContentGroup *)sectionForIndexPath:(NSIndexPath *)indexPath {
    return [self sectionAtIndex:indexPath.section];
}

#pragma mark - Content Access

- (nullable NSArray<id> *)contentForGroup:(WMFContentGroup *)group {
    return group.content;
}

- (nullable NSArray<id> *)contentForSectionAtIndex:(NSUInteger)sectionIndex {
    WMFContentGroup *section = [self sectionAtIndex:sectionIndex];
    return [self contentForGroup:section];
}

- (nullable NSArray<NSURL *> *)contentURLsForGroup:(WMFContentGroup *)group {
    NSArray<id> *content = group.content;

    if ([group contentType] == WMFContentTypeTopReadPreview) {
        content = [content bk_map:^id(WMFFeedTopReadArticlePreview *obj) {
            return [obj articleURL];
        }];
    } else if ([group contentType] == WMFContentTypeStory) {
        content = [content bk_map:^id(WMFFeedNewsStory *obj) {
            return [[obj featuredArticlePreview] articleURL] ?: [[[obj articlePreviews] firstObject] articleURL];
        }];
    } else if ([group contentType] != WMFContentTypeURL) {
        content = nil;
    }
    return content;
}

- (nullable NSURL *)contentURLForIndexPath:(NSIndexPath *)indexPath {
    WMFContentGroup *section = [self sectionAtIndex:indexPath.section];
    if ([section contentType] == WMFContentTypeTopReadPreview) {

        NSArray<WMFFeedTopReadArticlePreview *> *content = [self contentForSectionAtIndex:indexPath.section];

        if (indexPath.row >= [content count]) {
            return nil;
        }

        return [content[indexPath.row] articleURL];

    } else if ([section contentType] == WMFContentTypeURL) {

        NSArray<NSURL *> *content = [self contentForSectionAtIndex:indexPath.section];
        if (indexPath.row >= [content count]) {
            return nil;
        }
        return content[indexPath.row];

    } else if ([section contentType] == WMFContentTypeStory) {
        NSArray<WMFFeedNewsStory *> *content = [self contentForSectionAtIndex:indexPath.section];
        if (indexPath.row >= [content count]) {
            return nil;
        }
        return [[content[indexPath.row] featuredArticlePreview] articleURL] ?: [[[content[indexPath.row] articlePreviews] firstObject] articleURL];
    } else {
        return nil;
    }
}

- (nullable WMFArticle *)articleForIndexPath:(NSIndexPath *)indexPath {
    NSURL *url = [self contentURLForIndexPath:indexPath];
    if (url == nil) {
        return nil;
    }
    return [self.userStore fetchArticleForURL:url];
}

- (nullable WMFFeedTopReadArticlePreview *)topReadPreviewForIndexPath:(NSIndexPath *)indexPath {
    NSArray<WMFFeedTopReadArticlePreview *> *content = [self contentForSectionAtIndex:indexPath.section];
    if (indexPath.row >= content.count) {
        return nil;
    }
    return [content objectAtIndex:indexPath.row];
}

- (nullable WMFFeedImage *)imageInfoForIndexPath:(NSIndexPath *)indexPath {
    WMFContentGroup *section = [self sectionAtIndex:indexPath.section];
    if ([section contentType] != WMFContentTypeImage) {
        return nil;
    }
    if (indexPath.row >= section.content.count) {
        return nil;
    }
    return (WMFFeedImage *)section.content[indexPath.row];
}

#pragma mark - Refresh Control

- (void)resetRefreshControl {
    if (![self.refreshControl isRefreshing]) {
        return;
    }
    [self.refreshControl endRefreshing];
}

#pragma mark - Notification

- (void)sizeNotificationHeader {

    WMFFeedNotificationHeader *header = self.notificationHeader;
    if (!header.superview) {
        return;
    }

    //First layout pass to get height
    [header mas_remakeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(@(-136));
        make.leading.trailing.equalTo(self.collectionView.superview);
    }];

    [header sizeToFit];
    [header setNeedsLayout];
    [header layoutIfNeeded];

    CGRect f = header.frame;

    //Second layout pass to reset the top constraint
    [header mas_remakeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(@(-f.size.height));
        make.height.equalTo(@(f.size.height));
        make.leading.trailing.equalTo(self.collectionView.superview);
    }];

    [header sizeToFit];
    [header setNeedsLayout];
    [header layoutIfNeeded];

    UIEdgeInsets insets = self.collectionView.contentInset;
    insets.top = f.size.height;
    self.collectionView.contentInset = insets;
}

- (void)setNotificationHeaderBasedOnSizeClass {
    if (self.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassCompact) {
        self.notificationHeader = [WMFFeedNotificationHeader wmf_viewFromClassNib];
    } else {
        self.notificationHeader = [[[UINib nibWithNibName:@"WmfFeedNotificationHeaderiPad" bundle:nil] instantiateWithOwner:nil options:nil] firstObject];
    }
}

- (void)showNotificationHeader {

    if (self.notificationHeader) {
        [self.notificationHeader removeFromSuperview];
        self.notificationHeader = nil;
    }

    [self setNotificationHeaderBasedOnSizeClass];

    WMFFeedNotificationHeader *header = self.notificationHeader;
    [self.collectionView addSubview:self.notificationHeader];
    [self sizeNotificationHeader];

    @weakify(self);
    [header.enableNotificationsButton bk_addEventHandler:^(id sender) {
        @strongify(self);
        [[PiwikTracker sharedInstance] wmf_logActionEnableInContext:header contentType:header];

        [[WMFNotificationsController sharedNotificationsController] requestAuthenticationIfNecessaryWithCompletionHandler:^(BOOL granted, NSError *_Nullable error) {
            if (error) {
                [self wmf_showAlertWithError:error];
            }
        }];
        [[NSUserDefaults wmf_userDefaults] wmf_setInTheNewsNotificationsEnabled:YES];
        [self showHideNotificationIfNeccesary];

    }
                                        forControlEvents:UIControlEventTouchUpInside];

    [[NSUserDefaults wmf_userDefaults] wmf_setDidShowNewsNotificationCardInFeed:YES];
}

- (void)showHideNotificationIfNeccesary {
    if (self.numberOfSectionsInExploreFeed == 0) {
        return;
    }

    if ([[NSProcessInfo processInfo] wmf_isOperatingSystemMajorVersionLessThan:10]) {
        return;
    }

    if (![[NSUserDefaults wmf_userDefaults] wmf_inTheNewsNotificationsEnabled] && ![[NSUserDefaults wmf_userDefaults] wmf_didShowNewsNotificationCardInFeed]) {
        [self showNotificationHeader];

    } else {

        if (self.notificationHeader) {

            [UIView animateWithDuration:0.3
                animations:^{

                    UIEdgeInsets insets = self.collectionView.contentInset;
                    insets.top = 0.0;
                    self.collectionView.contentInset = insets;

                    self.notificationHeader.alpha = 0.0;

                }
                completion:^(BOOL finished) {

                    [self.notificationHeader removeFromSuperview];
                    self.notificationHeader = nil;

                }];
        }
    }
}

#pragma mark - UIViewController

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return [self wmf_orientationMaskPortraitiPhoneAnyiPad];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self registerCellsAndViews];
    self.collectionView.scrollsToTop = YES;
    self.collectionView.dataSource = self;
    self.collectionView.delegate = self;
    if ([self.collectionView respondsToSelector:@selector(setPrefetchDataSource:)]) {
        self.collectionView.prefetchDataSource = self;
        self.collectionView.prefetchingEnabled = YES;
    }

    self.reachabilityManager = [AFNetworkReachabilityManager manager];

    self.refreshControl = [[UIRefreshControl alloc] init];
    [self.refreshControl bk_addEventHandler:^(id sender) {
        [self updateFeedSources:NULL];
    }
                           forControlEvents:UIControlEventValueChanged];
    [self resetRefreshControl];

    NSFetchRequest *fetchRequest = [WMFContentGroup fetchRequest];
    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"isVisible == %@", @(YES)];
    fetchRequest.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"midnightUTCDate" ascending:NO], [NSSortDescriptor sortDescriptorWithKey:@"dailySortPriority" ascending:YES], [NSSortDescriptor sortDescriptorWithKey:@"date" ascending:NO]];
    NSFetchedResultsController *frc = [[NSFetchedResultsController alloc] initWithFetchRequest:fetchRequest managedObjectContext:self.userStore.viewContext sectionNameKeyPath:nil cacheName:nil];
    frc.delegate = self;
    [frc performFetch:nil];
    self.fetchedResultsController = frc;
    [self updateSectionCounts];
    [self.collectionView reloadData];

    @weakify(self);
    [[NSNotificationCenter defaultCenter] addObserverForName:UIContentSizeCategoryDidChangeNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *note) {
                                                      @strongify(self);
                                                      [self.collectionView reloadData];
                                                  }];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self registerForPreviewingIfAvailable];
    [self showHideNotificationIfNeccesary];
    for (UICollectionViewCell *cell in self.collectionView.visibleCells) {
        cell.selected = NO;
    }
}

- (void)viewDidAppear:(BOOL)animated {
    NSParameterAssert(self.contentStore);
    NSParameterAssert(self.userStore);
    NSParameterAssert(self.contentSources);
    NSParameterAssert(self.internalContentStore);
    [super viewDidAppear:animated];

    [[PiwikTracker sharedInstance] wmf_logView:self];
    [NSUserActivity wmf_makeActivityActive:[NSUserActivity wmf_exploreViewActivity]];
    [self startMonitoringReachabilityIfNeeded];
    [self showOfflineEmptyViewIfNeeded];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [self stopMonitoringReachability];
}

- (void)traitCollectionDidChange:(nullable UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self registerForPreviewingIfAvailable];
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    if (self.notificationHeader) {
        [self showNotificationHeader];
    }
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}

#pragma mark - Offline Handling

- (void)stopMonitoringReachability {
    [self.reachabilityManager setReachabilityStatusChangeBlock:NULL];
    [self.reachabilityManager stopMonitoring];
}

- (void)startMonitoringReachabilityIfNeeded {
    if (self.numberOfSectionsInExploreFeed > 0) {
        [self stopMonitoringReachability];
    } else {
        [self.reachabilityManager startMonitoring];
        @weakify(self);
        [self.reachabilityManager setReachabilityStatusChangeBlock:^(AFNetworkReachabilityStatus status) {
            @strongify(self);
            dispatchOnMainQueue(^{
                switch (status) {
                    case AFNetworkReachabilityStatusReachableViaWWAN:
                    case AFNetworkReachabilityStatusReachableViaWiFi: {
                        [self updateFeedSources:NULL];
                    } break;
                    case AFNetworkReachabilityStatusNotReachable: {
                        [self showOfflineEmptyViewIfNeeded];
                    }
                    default:
                        break;
                }

            });
        }];
    }
}

- (void)showOfflineEmptyViewIfNeeded {
    if (!self.isViewLoaded) {
        return;
    }
    if (self.numberOfSectionsInExploreFeed > 0) {
        [self wmf_hideEmptyView];
    } else {
        if ([self wmf_isShowingEmptyView]) {
            return;
        }

        if (self.reachabilityManager.networkReachabilityStatus != AFNetworkReachabilityStatusNotReachable) {
            return;
        }

        [self.refreshControl endRefreshing];
        [self wmf_showEmptyViewOfType:WMFEmptyViewTypeNoFeed];
    }
}

- (NSInteger)numberOfItemsInContentGroup:(WMFContentGroup *)contentGroup {
    NSParameterAssert(contentGroup);
    NSArray *feedContent = contentGroup.content;
    return MIN([feedContent count], [contentGroup maxNumberOfCells]);
}

- (void)updateSectionCounts {
    [self.sectionCounts removeAllObjects];
    NSInteger sectionCount = self.numberOfSectionsInExploreFeed;

    for (NSInteger i = 0; i < sectionCount; i++) {
        [self.sectionCounts addObject:@([self numberOfItemsInSection:i])];
    }
}

- (NSInteger)numberOfItemsInSection:(NSInteger)section {
    WMFContentGroup *contentGroup = [self sectionAtIndex:section];
    return [self numberOfItemsInContentGroup:contentGroup];
}

#pragma mark - UICollectionViewDataSource

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView {
    return self.numberOfSectionsInExploreFeed;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return [self numberOfItemsInSection:section];
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    WMFContentGroup *contentGroup = [self sectionForIndexPath:indexPath];
    NSParameterAssert(contentGroup);
    if (!contentGroup) {
        return [UICollectionViewCell new];
    }
    WMFArticle *article = [self articleForIndexPath:indexPath];

    switch ([contentGroup displayType]) {
        case WMFFeedDisplayTypePage: {
            WMFArticleListCollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:[WMFArticleListCollectionViewCell wmf_nibName] forIndexPath:indexPath];
            [self configureListCell:cell withArticle:article atIndexPath:indexPath];
            return cell;
        } break;
        case WMFFeedDisplayTypePageWithPreview: {
            WMFArticlePreviewCollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:[WMFArticlePreviewCollectionViewCell wmf_nibName] forIndexPath:indexPath];
            [self configurePreviewCell:cell withSection:contentGroup withArticle:article atIndexPath:indexPath];
            return cell;
        } break;
        case WMFFeedDisplayTypePageWithLocation: {
            WMFNearbyArticleCollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:[WMFNearbyArticleCollectionViewCell wmf_nibName] forIndexPath:indexPath];
            [self configureNearbyCell:cell withArticle:article atIndexPath:indexPath];
            return cell;

        } break;
        case WMFFeedDisplayTypePhoto: {
            WMFFeedImage *imageInfo = [self imageInfoForIndexPath:indexPath];
            WMFPicOfTheDayCollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:[WMFPicOfTheDayCollectionViewCell wmf_nibName] forIndexPath:indexPath];
            [self configurePhotoCell:cell withImageInfo:imageInfo atIndexPath:indexPath];
            return cell;
        } break;
        case WMFFeedDisplayTypeStory: {
            InTheNewsCollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:[InTheNewsCollectionViewCell wmf_nibName] forIndexPath:indexPath];
            [self configureStoryCell:cell withSection:contentGroup article:article atIndexPath:indexPath];
            return cell;
        } break;

        case WMFFeedDisplayTypeAnnouncement: {
            WMFAnnouncementCollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:[WMFAnnouncementCollectionViewCell wmf_nibName] forIndexPath:indexPath];
            [self configureAnouncementCell:cell withSection:contentGroup atIndexPath:indexPath];

            return cell;
        } break;
        default:
            NSAssert(false, @"Unknown Display Type");
            return nil;
            break;
    }
}

- (nonnull UICollectionReusableView *)collectionView:(UICollectionView *)collectionView viewForSupplementaryElementOfKind:(NSString *)kind atIndexPath:(NSIndexPath *)indexPath {
    if ([kind isEqualToString:UICollectionElementKindSectionHeader]) {
        return [self collectionView:collectionView viewForSectionHeaderAtIndexPath:indexPath];
    } else if ([kind isEqualToString:UICollectionElementKindSectionFooter]) {
        return [self collectionView:collectionView viewForSectionFooterAtIndexPath:indexPath];
    } else {
        NSAssert(false, @"Unknown Supplementary View Type");
        return [UICollectionReusableView new];
    }
}

#pragma mark - UICollectionViewDelegate

- (WMFLayoutEstimate)collectionView:(UICollectionView *)collectionView estimatedHeightForItemAtIndexPath:(NSIndexPath *)indexPath forColumnWidth:(CGFloat)columnWidth {
    WMFContentGroup *section = [self sectionAtIndex:indexPath.section];
    WMFLayoutEstimate estimate;
    switch ([section displayType]) {
        case WMFFeedDisplayTypePage: {
            estimate.height = [WMFArticleListCollectionViewCell estimatedRowHeight];
        } break;
        case WMFFeedDisplayTypePageWithPreview: {
            WMFArticle *article = [self articleForIndexPath:indexPath];
            CGFloat estimatedHeight = [WMFArticlePreviewCollectionViewCell estimatedRowHeightWithImage:article.thumbnailURL != nil];
            CGRect frameToFit = CGRectMake(0, 0, columnWidth, estimatedHeight);
            WMFArticlePreviewCollectionViewCell *cell = [self placeholderCellForIdentifier:[WMFArticlePreviewCollectionViewCell wmf_nibName]];
            cell.frame = frameToFit;
            [self configurePreviewCell:cell withSection:section withArticle:article atIndexPath:indexPath];
            WMFCVLAttributes *attributesToFit = [WMFCVLAttributes new];
            attributesToFit.frame = frameToFit;
            UICollectionViewLayoutAttributes *attributes = [cell preferredLayoutAttributesFittingAttributes:attributesToFit];
            estimate.height = attributes.frame.size.height;
            estimate.precalculated = YES;
        } break;
        case WMFFeedDisplayTypePageWithLocation: {
            estimate.height = [WMFNearbyArticleCollectionViewCell estimatedRowHeight];
        } break;
        case WMFFeedDisplayTypePhoto: {
            estimate.height = [WMFPicOfTheDayCollectionViewCell estimatedRowHeight];
        } break;
        case WMFFeedDisplayTypeStory: {
            estimate.height = [InTheNewsCollectionViewCell estimatedRowHeight];
        } break;
        case WMFFeedDisplayTypeAnnouncement: {
            WMFAnnouncement *announcement = (WMFAnnouncement *)section.content.firstObject;
            CGFloat estimatedHeight = [WMFAnnouncementCollectionViewCell estimatedRowHeightWithImage:announcement.imageURL != nil];
            CGRect frameToFit = CGRectMake(0, 0, columnWidth, estimatedHeight);
            WMFAnnouncementCollectionViewCell *cell = [self placeholderCellForIdentifier:[WMFAnnouncementCollectionViewCell wmf_nibName]];
            cell.frame = frameToFit;
            [self configureAnouncementCell:cell withSection:section atIndexPath:indexPath];
            WMFCVLAttributes *attributesToFit = [WMFCVLAttributes new];
            attributesToFit.frame = frameToFit;
            UICollectionViewLayoutAttributes *attributes = [cell preferredLayoutAttributesFittingAttributes:attributesToFit];
            estimate.height = attributes.frame.size.height;
            estimate.precalculated = YES;
        } break;
        default:
            NSAssert(false, @"Unknown display Type");
            estimate.height = [WMFArticleListCollectionViewCell estimatedRowHeight];
            break;
    }
    return estimate;
}

- (CGFloat)collectionView:(UICollectionView *)collectionView estimatedHeightForHeaderInSection:(NSInteger)section forColumnWidth:(CGFloat)columnWidth {
    WMFContentGroup *sectionObject = [self sectionAtIndex:section];
    if ([sectionObject headerType] == WMFFeedHeaderTypeNone) {
        return 0.0;
    } else {
        return 69.0;
    }
}

- (CGFloat)collectionView:(UICollectionView *)collectionView estimatedHeightForFooterInSection:(NSInteger)section forColumnWidth:(CGFloat)columnWidth {
    WMFContentGroup *sectionObject = [self sectionAtIndex:section];
    if ([sectionObject moreType] == WMFFeedMoreTypeNone) {
        return 0.0;
    } else if ([sectionObject moreType] == WMFFeedMoreTypeLocationAuthorization) {
        CGRect frameToFit = CGRectMake(0, 0, columnWidth, 170);
        WMFExploreCollectionReusableView *footer = [self placeholderFooterForIdentifier:[WMFTitledExploreSectionFooter wmf_nibName]];
        footer.frame = frameToFit;
        WMFCVLAttributes *attributesToFit = [WMFCVLAttributes new];
        attributesToFit.frame = frameToFit;
        UICollectionViewLayoutAttributes *attributes = [footer preferredLayoutAttributesFittingAttributes:attributesToFit];
        CGFloat height = attributes.frame.size.height;
        return height;
    } else {
        return 50.0;
    }
}

- (BOOL)collectionView:(UICollectionView *)collectionView prefersWiderColumnForSectionAtIndex:(NSUInteger)index {
    WMFContentGroup *section = [self sectionAtIndex:index];
    return [section prefersWiderColumn];
}

- (void)collectionView:(UICollectionView *)collectionView willDisplayCell:(UICollectionViewCell *)cell forItemAtIndexPath:(NSIndexPath *)indexPath {
    WMFContentGroup *section = [self sectionAtIndex:indexPath.section];
    [[PiwikTracker sharedInstance] wmf_logActionImpressionInContext:self contentType:section value:section];

    if (![WMFLocationManager isAuthorized]) {
        return;
    }

    if ([cell isKindOfClass:[WMFNearbyArticleCollectionViewCell class]] || [self isDisplayingLocationCell]) {
        [self.locationManager startMonitoringLocation];
    } else {
        [self.locationManager stopMonitoringLocation];
    }
}

- (nonnull UICollectionReusableView *)collectionView:(UICollectionView *)collectionView viewForSectionHeaderAtIndexPath:(NSIndexPath *)indexPath {
    WMFContentGroup *section = [self sectionAtIndex:indexPath.section];
    NSParameterAssert(section);

    if ([section headerType] == WMFFeedHeaderTypeNone) {
        return [collectionView dequeueReusableSupplementaryViewOfKind:UICollectionElementKindSectionFooter withReuseIdentifier:WMFFeedEmptyHeaderFooterReuseIdentifier forIndexPath:indexPath];
    }
    NSParameterAssert([section headerIcon]);
    NSParameterAssert([section headerTitle]);
    NSParameterAssert([section headerSubTitle]);

    WMFExploreSectionHeader *header = (id)[collectionView dequeueReusableSupplementaryViewOfKind:UICollectionElementKindSectionHeader withReuseIdentifier:[WMFExploreSectionHeader wmf_nibName] forIndexPath:indexPath];

    header.image = [[section headerIcon] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    header.imageTintColor = [section headerIconTintColor];
    header.imageBackgroundColor = [section headerIconBackgroundColor];

    header.title = [[section headerTitle] mutableCopy];
    [header setTitleColor:[section headerTitleColor]];

    header.subTitle = [[section headerSubTitle] mutableCopy];
    [header setSubTitleColor:[section headerSubTitleColor]];

    @weakify(self);
    @weakify(section);
    header.whenTapped = ^{
        @strongify(self);
        NSIndexPath *indexPathForSection = [self.fetchedResultsController indexPathForObject:section];
        if (!indexPathForSection) {
            return;
        }
        [self didTapHeaderInSection:indexPathForSection.row];
    };

    if (([section blackListOptions] & WMFFeedBlacklistOptionSection) || (([section blackListOptions] & WMFFeedBlacklistOptionContent) && [section headerContentURL])) {
        header.rightButtonEnabled = YES;
        [[header rightButton] setImage:[UIImage imageNamed:@"overflow-mini"] forState:UIControlStateNormal];
        [header.rightButton bk_removeEventHandlersForControlEvents:UIControlEventTouchUpInside];
        [header.rightButton bk_addEventHandler:^(id sender) {
            @strongify(section);
            @strongify(self);
            if (!self || !section) {
                return;
            }
            UIAlertController *menuActionSheet = [self menuActionSheetForSection:section];
            if (!menuActionSheet) {
                return;
            }

            if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
                menuActionSheet.modalPresentationStyle = UIModalPresentationPopover;
                menuActionSheet.popoverPresentationController.sourceView = sender;
                menuActionSheet.popoverPresentationController.sourceRect = [sender bounds];
                menuActionSheet.popoverPresentationController.permittedArrowDirections = UIPopoverArrowDirectionAny;
                [self presentViewController:menuActionSheet animated:YES completion:nil];
            } else {
                menuActionSheet.popoverPresentationController.sourceView = self.navigationController.tabBarController.tabBar.superview;
                menuActionSheet.popoverPresentationController.sourceRect = self.navigationController.tabBarController.tabBar.frame;
                [self presentViewController:menuActionSheet animated:YES completion:nil];
            }
        }
                              forControlEvents:UIControlEventTouchUpInside];
    } else {
        header.rightButtonEnabled = NO;
        [header.rightButton bk_removeEventHandlersForControlEvents:UIControlEventTouchUpInside];
    }

    return header;
}

#pragma mark - UICollectionViewDataSourcePrefetching

- (void)collectionView:(UICollectionView *)collectionView prefetchItemsAtIndexPaths:(NSArray<NSIndexPath *> *)indexPaths {
    for (NSIndexPath *indexPath in indexPaths) {
        if (self.prefetchURLsByIndexPath[indexPath]) {
            continue;
        }
        WMFArticle *article = [self articleForIndexPath:indexPath];
        NSURL *imageURL = article.thumbnailURL;
        if (!imageURL) {
            continue;
        }
        self.prefetchURLsByIndexPath[indexPath] = imageURL;
        [[WMFImageController sharedInstance] prefetchImageWithURL:article.thumbnailURL
                                                       completion:^{
                                                           [self.prefetchURLsByIndexPath removeObjectForKey:indexPath];
                                                       }];
    }
}

- (void)collectionView:(UICollectionView *)collectionView cancelPrefetchingForItemsAtIndexPaths:(NSArray<NSIndexPath *> *)indexPaths {
    for (NSIndexPath *indexPath in indexPaths) {
        NSURL *imageURL = self.prefetchURLsByIndexPath[indexPath];
        if (!imageURL) {
            continue;
        }
        [[WMFImageController sharedInstance] cancelFetchForURL:imageURL];
        [self.prefetchURLsByIndexPath removeObjectForKey:indexPath];
    }
}

#pragma mark - WMFHeaderMenuProviding

- (nullable UIAlertController *)menuActionSheetForSection:(WMFContentGroup *)section {
    switch (section.contentGroupKind) {
        case WMFContentGroupKindRelatedPages: {
            NSURL *url = [section headerContentURL];
            UIAlertController *sheet = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
            [sheet addAction:[UIAlertAction actionWithTitle:MWLocalizedString(@"home-hide-suggestion-prompt", nil)
                                                      style:UIAlertActionStyleDestructive
                                                    handler:^(UIAlertAction *_Nonnull action) {
                                                        [self.userStore setIsExcludedFromFeed:YES forArticleURL:url];
                                                        [self.contentStore removeContentGroup:section];
                                                    }]];
            [sheet addAction:[UIAlertAction actionWithTitle:MWLocalizedString(@"home-hide-suggestion-cancel", nil) style:UIAlertActionStyleCancel handler:NULL]];
            return sheet;
        }
        case WMFContentGroupKindLocationPlaceholder: {
            UIAlertController *sheet = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
            [sheet addAction:[UIAlertAction actionWithTitle:MWLocalizedString(@"explore-nearby-placeholder-dismiss", nil)
                                                      style:UIAlertActionStyleDestructive
                                                    handler:^(UIAlertAction *_Nonnull action) {
                                                        [[NSUserDefaults wmf_userDefaults] wmf_setExploreDidPromptForLocationAuthorization:YES];
                                                        section.wasDismissed = YES;
                                                        [section updateVisibility];
                                                    }]];
            [sheet addAction:[UIAlertAction actionWithTitle:MWLocalizedString(@"explore-nearby-placeholder-cancel", nil) style:UIAlertActionStyleCancel handler:NULL]];
            return sheet;
        }
        default:
            return nil;
    }
}

- (nonnull UICollectionReusableView *)collectionView:(UICollectionView *)collectionView viewForSectionFooterAtIndexPath:(NSIndexPath *)indexPath {
    WMFContentGroup *group = [self sectionAtIndex:indexPath.section];
    NSParameterAssert(group);
    switch (group.moreType) {
        case WMFFeedMoreTypeNone:
            return [collectionView dequeueReusableSupplementaryViewOfKind:UICollectionElementKindSectionFooter withReuseIdentifier:WMFFeedEmptyHeaderFooterReuseIdentifier forIndexPath:indexPath];
        case WMFFeedMoreTypeLocationAuthorization: {
            WMFTitledExploreSectionFooter *footer = (id)[collectionView dequeueReusableSupplementaryViewOfKind:UICollectionElementKindSectionFooter withReuseIdentifier:[WMFTitledExploreSectionFooter wmf_nibName] forIndexPath:indexPath];
            [footer bk_whenTapped:^{
                [[NSUserDefaults wmf_userDefaults] wmf_setExploreDidPromptForLocationAuthorization:YES];
                if ([WMFLocationManager isAuthorizationNotDetermined]) {
                    [self.locationManager startMonitoringLocation];
                    return;
                }
                [[UIApplication sharedApplication] wmf_openAppSpecificSystemSettings];
            }];
            return footer;
        }
        default: {
            WMFExploreSectionFooter *footer = (id)[collectionView dequeueReusableSupplementaryViewOfKind:UICollectionElementKindSectionFooter withReuseIdentifier:[WMFExploreSectionFooter wmf_nibName] forIndexPath:indexPath];
            footer.visibleBackgroundView.alpha = 1.0;
            footer.moreLabel.text = [group footerText];
            footer.moreLabel.textColor = [UIColor wmf_exploreSectionFooterTextColor];
            @weakify(self);
            footer.whenTapped = ^{
                @strongify(self);
                NSIndexPath *indexPathForSection = [self.fetchedResultsController indexPathForObject:group];
                if (!indexPathForSection) {
                    return;
                }
                [self presentMoreViewControllerForSectionAtIndex:indexPathForSection.row animated:YES];
            };
            return footer;
        }
    }
}

- (BOOL)collectionView:(UICollectionView *)collectionView shouldHighlightItemAtIndexPath:(NSIndexPath *)indexPath {
    WMFContentGroup *contentGroup = [self sectionForIndexPath:indexPath];
    NSParameterAssert(contentGroup);
    if (!contentGroup) {
        return NO;
    }
    if (contentGroup.contentGroupKind == WMFContentGroupKindAnnouncement) {
        return NO;
    } else {
        return YES;
    }
}

- (BOOL)collectionView:(UICollectionView *)collectionView shouldSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    WMFContentGroup *contentGroup = [self sectionForIndexPath:indexPath];
    NSParameterAssert(contentGroup);
    if (!contentGroup) {
        return NO;
    }
    if (contentGroup.contentGroupKind == WMFContentGroupKindAnnouncement) {
        return NO;
    } else {
        return YES;
    }
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(nonnull NSIndexPath *)indexPath {
    [self presentDetailViewControllerForItemAtIndexPath:indexPath animated:YES];
}

#pragma mark - Cells, Headers and Footers

- (void)registerNib:(UINib *)nib forCellWithReuseIdentifier:(NSString *)identifier {
    [self.collectionView registerNib:nib forCellWithReuseIdentifier:identifier];
    WMFExploreCollectionViewCell *placeholderCell = [[nib instantiateWithOwner:nil options:nil] firstObject];
    if (!placeholderCell) {
        return;
    }
    placeholderCell.hidden = YES;
    [self.view insertSubview:placeholderCell atIndex:0];
    [self.placeholderCells setObject:placeholderCell forKey:identifier];
}

- (id)placeholderCellForIdentifier:(NSString *)identifier {
    return self.placeholderCells[identifier];
}

- (void)registerNib:(UINib *)nib forFooterWithReuseIdentifier:(NSString *)identifier {
    [self.collectionView registerNib:nib forSupplementaryViewOfKind:UICollectionElementKindSectionFooter withReuseIdentifier:identifier];
    WMFExploreCollectionReusableView *placeholderView = [[nib instantiateWithOwner:nil options:nil] firstObject];
    if (!placeholderView) {
        return;
    }
    placeholderView.hidden = YES;
    [self.view insertSubview:placeholderView atIndex:0];
    [self.placeholderFooters setObject:placeholderView forKey:identifier];
}

- (id)placeholderFooterForIdentifier:(NSString *)identifier {
    return self.placeholderFooters[identifier];
}

- (void)registerCellsAndViews {
    [self.collectionView registerNib:[WMFExploreSectionHeader wmf_classNib] forSupplementaryViewOfKind:UICollectionElementKindSectionHeader withReuseIdentifier:[WMFExploreSectionHeader wmf_nibName]];

    [self.collectionView registerNib:[WMFExploreSectionFooter wmf_classNib] forSupplementaryViewOfKind:UICollectionElementKindSectionFooter withReuseIdentifier:[WMFExploreSectionFooter wmf_nibName]];

    [self registerNib:[WMFTitledExploreSectionFooter wmf_classNib] forFooterWithReuseIdentifier:[WMFTitledExploreSectionFooter wmf_nibName]];

    [self.collectionView registerClass:[UICollectionReusableView class] forSupplementaryViewOfKind:UICollectionElementKindSectionFooter withReuseIdentifier:WMFFeedEmptyHeaderFooterReuseIdentifier];

    [self registerNib:[WMFAnnouncementCollectionViewCell wmf_classNib] forCellWithReuseIdentifier:[WMFAnnouncementCollectionViewCell wmf_nibName]];

    [self.collectionView registerNib:[WMFArticleListCollectionViewCell wmf_classNib] forCellWithReuseIdentifier:[WMFArticleListCollectionViewCell wmf_nibName]];

    [self registerNib:[WMFArticlePreviewCollectionViewCell wmf_classNib] forCellWithReuseIdentifier:[WMFArticlePreviewCollectionViewCell wmf_nibName]];

    [self.collectionView registerNib:[WMFNearbyArticleCollectionViewCell wmf_classNib] forCellWithReuseIdentifier:[WMFNearbyArticleCollectionViewCell wmf_nibName]];

    [self.collectionView registerNib:[WMFPicOfTheDayCollectionViewCell wmf_classNib] forCellWithReuseIdentifier:[WMFPicOfTheDayCollectionViewCell wmf_nibName]];

    [self.collectionView registerNib:[InTheNewsCollectionViewCell wmf_classNib] forCellWithReuseIdentifier:[InTheNewsCollectionViewCell wmf_nibName]];
}

- (void)configureListCell:(WMFArticleListCollectionViewCell *)cell withArticle:(WMFArticle *)article atIndexPath:(NSIndexPath *)indexPath {
    cell.titleText = [article.displayTitle wmf_stringByRemovingHTML];
    cell.titleLabel.accessibilityLanguage = article.URL.wmf_language;
    cell.descriptionText = [article.wikidataDescription wmf_stringByCapitalizingFirstCharacter];
    [cell setImageURL:article.thumbnailURL];
}

- (void)configurePreviewCell:(WMFArticlePreviewCollectionViewCell *)cell withSection:(WMFContentGroup *)section withArticle:(WMFArticle *)article atIndexPath:(NSIndexPath *)indexPath {
    cell.titleText = [article.displayTitle wmf_stringByRemovingHTML];
    cell.descriptionText = [article.wikidataDescription wmf_stringByCapitalizingFirstCharacter];
    cell.snippetText = article.snippet;
    [cell setImageURL:article.thumbnailURL];
    [cell setSaveableURL:article.URL savedPageList:self.userStore.savedPageList];
    cell.saveButtonController.analyticsContext = [self analyticsContext];
    cell.saveButtonController.analyticsContentType = [section analyticsContentType];
}

- (void)configureNearbyCell:(WMFNearbyArticleCollectionViewCell *)cell withArticle:(WMFArticle *)article atIndexPath:(NSIndexPath *)indexPath {
    cell.titleText = [article.displayTitle wmf_stringByRemovingHTML];
    cell.descriptionText = [article.wikidataDescription wmf_stringByCapitalizingFirstCharacter];
    [cell setImageURL:article.thumbnailURL];
    [self updateLocationCell:cell location:article.location];
}

- (void)configurePhotoCell:(WMFPicOfTheDayCollectionViewCell *)cell withImageInfo:(WMFFeedImage *)imageInfo atIndexPath:(NSIndexPath *)indexPath {
    [cell setImageURL:imageInfo.imageThumbURL];
    if (imageInfo.imageDescription.length) {
        [cell setDisplayTitle:[imageInfo.imageDescription wmf_stringByRemovingHTML]];
    } else {
        [cell setDisplayTitle:imageInfo.canonicalPageTitle];
    }
    //    self.referenceImageView = cell.potdImageView;
}

- (void)configureStoryCell:(InTheNewsCollectionViewCell *)cell withSection:(WMFContentGroup *)section article:(WMFArticle *)article atIndexPath:(NSIndexPath *)indexPath {
    NSArray<WMFFeedNewsStory *> *stories = [self contentForGroup:section];
    if (indexPath.item >= stories.count) {
        return;
    }
    WMFFeedNewsStory *story = stories[indexPath.item];
    cell.bodyHTML = story.storyHTML;
    cell.imageURL = article.thumbnailURL;
}

- (void)configureAnouncementCell:(WMFAnnouncementCollectionViewCell *)cell withSection:(WMFContentGroup *)section atIndexPath:(NSIndexPath *)indexPath {
    NSArray<WMFAnnouncement *> *announcements = [self contentForGroup:section];
    if (indexPath.item >= announcements.count) {
        return;
    }
    WMFAnnouncement *announcement = announcements[indexPath.item];
    [cell setImageURL:announcement.imageURL];
    [cell setMessageText:announcement.text];
    [cell setActionText:announcement.actionTitle];
    [cell setCaption:announcement.caption];
    cell.delegate = self;
}

- (BOOL)isDisplayingLocationCell {
    __block BOOL hasLocationCell = NO;
    [[self.collectionView visibleCells] enumerateObjectsUsingBlock:^(__kindof UICollectionViewCell *_Nonnull obj, NSUInteger idx, BOOL *_Nonnull stop) {
        if ([obj isKindOfClass:[WMFNearbyArticleCollectionViewCell class]]) {
            hasLocationCell = YES;
            *stop = YES;
        }

    }];
    return hasLocationCell;
}

- (void)updateLocationCells {
    [[self.collectionView indexPathsForVisibleItems] enumerateObjectsUsingBlock:^(NSIndexPath *_Nonnull obj, NSUInteger idx, BOOL *_Nonnull stop) {
        UICollectionViewCell *cell = [self.collectionView cellForItemAtIndexPath:obj];
        if ([cell isKindOfClass:[WMFNearbyArticleCollectionViewCell class]]) {
            WMFArticle *preview = [self articleForIndexPath:obj];
            [self updateLocationCell:(WMFNearbyArticleCollectionViewCell *)cell location:preview.location];
        }
    }];
}

- (void)updateLocationCell:(WMFNearbyArticleCollectionViewCell *)cell location:(CLLocation *)location {
    CLLocation *userLocation = self.locationManager.location;
    if (userLocation == nil) {
        [cell configureForUnknownDistance];
        return;
    }
    [cell setDistance:[userLocation distanceFromLocation:location]];
    [cell setBearing:[userLocation wmf_bearingToLocation:location forCurrentHeading:self.locationManager.heading]];
}

- (void)selectItem:(NSUInteger)item inSection:(NSUInteger)section {
    NSIndexPath *indexPath = [NSIndexPath indexPathForItem:item inSection:section];
    [self.collectionView selectItemAtIndexPath:indexPath animated:NO scrollPosition:UICollectionViewScrollPositionNone];
    [self collectionView:self.collectionView didSelectItemAtIndexPath:indexPath];
}

- (NSIndexPath *)topIndexPathToMaintainFocus {

    __block NSIndexPath *top = nil;
    [[self.collectionView indexPathsForVisibleItems] enumerateObjectsUsingBlock:^(NSIndexPath *_Nonnull obj, NSUInteger idx, BOOL *_Nonnull stop) {
        WMFContentGroup *group = [self sectionAtIndex:obj.section];
        if (group.contentGroupKind != WMFContentGroupKindMainPage) {
            return;
        }
        top = obj;
        *stop = YES;
    }];

    return top;
}

#pragma mark - Header Action

- (void)didTapHeaderInSection:(NSUInteger)section {
    WMFContentGroup *group = [self sectionAtIndex:section];

    switch ([group headerActionType]) {
        case WMFFeedHeaderActionTypeOpenHeaderContent: {
            NSURL *url = [group headerContentURL];
            [self wmf_pushArticleWithURL:url dataStore:self.userStore previewStore:self.previewStore animated:YES];
        } break;
        case WMFFeedHeaderActionTypeOpenFirstItem: {
            [self selectItem:0 inSection:section];
        } break;
        case WMFFeedHeaderActionTypeOpenMore: {
            [self presentMoreViewControllerForSectionAtIndex:section animated:YES];
        } break;
        default:
            NSAssert(false, @"Unknown header action");
            break;
    }
}

#pragma mark - More View Controller

- (void)presentMoreViewControllerForGroup:(WMFContentGroup *)group animated:(BOOL)animated {
    [[PiwikTracker sharedInstance] wmf_logActionTapThroughMoreInContext:self contentType:group value:group];
    NSArray<NSURL *> *URLs = [self contentURLsForGroup:group];
    NSAssert([[URLs firstObject] isKindOfClass:[NSURL class]], @"Attempting to present More VC with somehting other than URLs");
    if (![[URLs firstObject] isKindOfClass:[NSURL class]]) {
        return;
    }

    switch (group.moreType) {
        case WMFFeedMoreTypePageList: {
            WMFMorePageListViewController *vc = [[WMFMorePageListViewController alloc] initWithGroup:group articleURLs:URLs userDataStore:self.userStore previewStore:self.previewStore];
            vc.cellType = WMFMorePageListCellTypeNormal;
            [self.navigationController pushViewController:vc animated:animated];
        } break;
        case WMFFeedMoreTypePageListWithPreview: {
            WMFMorePageListViewController *vc = [[WMFMorePageListViewController alloc] initWithGroup:group articleURLs:URLs userDataStore:self.userStore previewStore:self.previewStore];
            vc.cellType = WMFMorePageListCellTypePreview;
            [self.navigationController pushViewController:vc animated:animated];
        } break;
        case WMFFeedMoreTypePageListWithLocation: {
            WMFMorePageListViewController *vc = [[WMFMorePageListViewController alloc] initWithGroup:group articleURLs:URLs userDataStore:self.userStore previewStore:self.previewStore];
            vc.cellType = WMFMorePageListCellTypeLocation;
            [self.navigationController pushViewController:vc animated:animated];
        } break;
        case WMFFeedMoreTypePageWithRandomButton: {
            WMFFirstRandomViewController *vc = [[WMFFirstRandomViewController alloc] initWithSiteURL:[self currentSiteURL] dataStore:self.userStore previewStore:self.previewStore];
            [self.navigationController pushViewController:vc animated:animated];
        } break;

        default:
            NSAssert(false, @"Unknown More Type");
            break;
    }
}

- (void)presentMoreViewControllerForSectionAtIndex:(NSUInteger)sectionIndex animated:(BOOL)animated {
    WMFContentGroup *group = [self sectionAtIndex:sectionIndex];
    [self presentMoreViewControllerForGroup:group animated:animated];
}

#pragma mark - Detail View Controller

- (nullable UIViewController *)detailViewControllerForItemAtIndexPath:(NSIndexPath *)indexPath {
    WMFContentGroup *group = [self sectionAtIndex:indexPath.section];

    switch ([group detailType]) {
        case WMFFeedDetailTypePage: {
            NSURL *url = [self contentURLForIndexPath:indexPath];
            WMFArticleViewController *vc = [[WMFArticleViewController alloc] initWithArticleURL:url dataStore:self.userStore previewStore:self.previewStore];
            return vc;
        } break;
        case WMFFeedDetailTypePageWithRandomButton: {
            NSURL *url = [self contentURLForIndexPath:indexPath];
            WMFRandomArticleViewController *vc = [[WMFRandomArticleViewController alloc] initWithArticleURL:url dataStore:self.userStore previewStore:self.previewStore];
            return vc;
        } break;
        case WMFFeedDetailTypeGallery: {
            return [[WMFPOTDImageGalleryViewController alloc] initWithDates:@[group.date]];
        } break;
        case WMFFeedDetailTypeStory: {
            NSArray<WMFFeedNewsStory *> *stories = [self contentForGroup:group];
            if (indexPath.item >= stories.count) {
                return nil;
            }
            WMFFeedNewsStory *story = stories[indexPath.item];
            InTheNewsViewController *vc = [self inTheNewsViewControllerForStory:story date:group.date];
            return vc;
        } break;
        case WMFFeedDetailTypeNone:
            break;
        default:
            NSAssert(false, @"Unknown Detail Type");
            break;
    }
    return nil;
}

- (void)presentDetailViewControllerForItemAtIndexPath:(NSIndexPath *)indexPath animated:(BOOL)animated {
    UIViewController *vc = [self detailViewControllerForItemAtIndexPath:indexPath];

    WMFContentGroup *group = [self sectionAtIndex:indexPath.section];
    [[PiwikTracker sharedInstance] wmf_logActionTapThroughInContext:self contentType:group value:group];

    if (vc == nil || vc == self) {
        return;
    }

    switch ([group detailType]) {
        case WMFFeedDetailTypePage: {
            [self wmf_pushArticleViewController:(WMFArticleViewController *)vc animated:animated];
        } break;
        case WMFFeedDetailTypePageWithRandomButton: {
            [self.navigationController pushViewController:vc animated:animated];
        } break;
        case WMFFeedDetailTypeGallery: {
            [self presentViewController:vc animated:animated completion:nil];
        } break;
        case WMFFeedDetailTypeStory: {
            [self.navigationController pushViewController:vc animated:animated];
        } break;
        default:
            NSAssert(false, @"Unknown Detail Type");
            break;
    }
}

#pragma mark - WMFLocationManager

- (void)locationManager:(WMFLocationManager *)controller didUpdateLocation:(CLLocation *)location {
    [self updateLocationCells];
}

- (void)locationManager:(WMFLocationManager *)controller didUpdateHeading:(CLHeading *)heading {
    [self updateLocationCells];
}

- (void)locationManager:(WMFLocationManager *)controller didReceiveError:(NSError *)error {
    //TODO: probably not displaying the error, but maybe?
}

- (void)locationManager:(WMFLocationManager *)controller didChangeEnabledState:(BOOL)enabled {
    [[NSUserDefaults wmf_userDefaults] wmf_setLocationAuthorized:enabled];
    [self updateNearby:NULL];
}

#pragma mark - Previewing

- (void)registerForPreviewingIfAvailable {
    [self wmf_ifForceTouchAvailable:^{
        [self unregisterPreviewing];
        self.previewingContext = [self registerForPreviewingWithDelegate:self
                                                              sourceView:self.collectionView];
    }
        unavailable:^{
            [self unregisterPreviewing];
        }];
}

- (void)unregisterPreviewing {
    if (self.previewingContext) {
        [self unregisterForPreviewingWithContext:self.previewingContext];
        self.previewingContext = nil;
    }
}

#pragma mark - WMFArticlePreviewingActionsDelegate

- (void)readMoreArticlePreviewActionSelectedWithArticleController:(WMFArticleViewController *)articleController {
    [self wmf_pushArticleViewController:articleController animated:YES];
}

- (void)shareArticlePreviewActionSelectedWithArticleController:(WMFArticleViewController *)articleController
                                       shareActivityController:(UIActivityViewController *)shareActivityController {
    [self presentViewController:shareActivityController animated:YES completion:NULL];
}

- (void)viewOnMapArticlePreviewActionSelectedWithArticleController:(WMFArticleViewController *)articleController {
    NSURL *placesURL = [NSUserActivity wmf_URLForActivityOfType:WMFUserActivityTypePlaces withArticleURL:articleController.article.url];
    [[UIApplication sharedApplication] openURL:placesURL];
}

#pragma mark - UIViewControllerPreviewingDelegate

- (nullable UIViewController *)previewingContext:(id<UIViewControllerPreviewing>)previewingContext
                       viewControllerForLocation:(CGPoint)location {
    UICollectionViewLayoutAttributes *layoutAttributes = nil;

    if ([self.collectionViewLayout respondsToSelector:@selector(layoutAttributesAtPoint:)]) {
        layoutAttributes = [(id)self.collectionViewLayout layoutAttributesAtPoint:location];
    }

    if (layoutAttributes == nil) {
        return nil;
    }

    NSIndexPath *previewIndexPath = layoutAttributes.indexPath;
    NSInteger section = previewIndexPath.section;
    NSInteger sectionCount = [self numberOfItemsInSection:section];

    if ([layoutAttributes.representedElementKind isEqualToString:UICollectionElementKindSectionFooter] && sectionCount > 0) {
        //preview the last item in the section when tapping the footer
        previewIndexPath = [NSIndexPath indexPathForItem:sectionCount - 1 inSection:section];
    }

    if (previewIndexPath.row >= sectionCount) {
        return nil;
    }

    WMFContentGroup *group = [self sectionForIndexPath:previewIndexPath];
    if (!group) {
        return nil;
    }
    self.groupForPreviewedCell = group;

    previewingContext.sourceRect = [self.collectionView cellForItemAtIndexPath:previewIndexPath].frame;

    UIViewController *vc = [self detailViewControllerForItemAtIndexPath:previewIndexPath];
    [[PiwikTracker sharedInstance] wmf_logActionPreviewInContext:self contentType:group];

    if ([vc isKindOfClass:[WMFArticleViewController class]]) {
        ((WMFArticleViewController *)vc).articlePreviewingActionsDelegate = self;
    }

    return vc;
}

- (void)previewingContext:(id<UIViewControllerPreviewing>)previewingContext
     commitViewController:(UIViewController *)viewControllerToCommit {
    [[PiwikTracker sharedInstance] wmf_logActionTapThroughInContext:self contentType:self.groupForPreviewedCell];
    self.groupForPreviewedCell = nil;

    if ([viewControllerToCommit isKindOfClass:[WMFArticleViewController class]]) {
        [self wmf_pushArticleViewController:(WMFArticleViewController *)viewControllerToCommit animated:YES];
    } else if ([viewControllerToCommit isKindOfClass:[InTheNewsViewController class]]) {
        [self.navigationController pushViewController:viewControllerToCommit animated:YES];
    } else if (![viewControllerToCommit isKindOfClass:[WMFExploreViewController class]]) {
        [self presentViewController:viewControllerToCommit animated:YES completion:nil];
    }
}

#pragma mark - In The News

- (InTheNewsViewController *)inTheNewsViewControllerForStory:(WMFFeedNewsStory *)story date:(nullable NSDate *)date {
    InTheNewsViewController *vc = [[InTheNewsViewController alloc] initWithStory:story dataStore:self.userStore previewStore:self.previewStore];
    NSString *format = MWLocalizedString(@"in-the-news-title-for-date", nil);
    if (format && date) {
        NSString *dateString = [[NSDateFormatter wmf_shortDayNameShortMonthNameDayOfMonthNumberDateFormatter] stringFromDate:date];
        NSString *title = [format stringByReplacingOccurrencesOfString:@"$1" withString:dateString];
        vc.title = title;
    } else {
        vc.title = MWLocalizedString(@"in-the-news-title", nil);
    }
    return vc;
}

- (void)showInTheNewsForStory:(WMFFeedNewsStory *)story date:(nullable NSDate *)date animated:(BOOL)animated {
    InTheNewsViewController *vc = [self inTheNewsViewControllerForStory:story date:date];
    [self.navigationController pushViewController:vc animated:animated];
}

#pragma mark - NSFetchedResultsControllerDelegate

- (void)controllerWillChangeContent:(NSFetchedResultsController *)controller {
}

- (void)controller:(NSFetchedResultsController *)controller didChangeSection:(id<NSFetchedResultsSectionInfo>)sectionInfo atIndex:(NSUInteger)sectionIndex forChangeType:(NSFetchedResultsChangeType)type {
    WMFSectionChange *sectionChange = [WMFSectionChange new];
    sectionChange.type = type;
    sectionChange.sectionIndex = sectionIndex;
    [self.sectionChanges addObject:sectionChange];
}

- (void)controller:(NSFetchedResultsController *)controller didChangeObject:(id)anObject atIndexPath:(nullable NSIndexPath *)indexPath forChangeType:(NSFetchedResultsChangeType)type newIndexPath:(nullable NSIndexPath *)newIndexPath {
    WMFObjectChange *objectChange = [WMFObjectChange new];
    objectChange.type = type;
    objectChange.fromIndexPath = indexPath;
    objectChange.toIndexPath = newIndexPath;
    [self.objectChanges addObject:objectChange];
}

- (void)controllerDidChangeContent:(NSFetchedResultsController *)controller {

    BOOL shouldReload = self.sectionChanges.count > 0;

    NSArray *previousSectionCounts = [self.sectionCounts copy];
    NSInteger previousNumberOfSections = previousSectionCounts.count;

    NSInteger sectionDelta = 0;
    for (WMFObjectChange *change in self.objectChanges) {
        switch (change.type) {
            case NSFetchedResultsChangeInsert:
                sectionDelta++;
                break;
            case NSFetchedResultsChangeDelete:
                sectionDelta--;
                break;
            case NSFetchedResultsChangeUpdate:
                break;
            case NSFetchedResultsChangeMove:
                break;
        }
    }

    [self updateSectionCounts];
    NSInteger currentNumberOfSections = self.sectionCounts.count;
    BOOL sectionCountsMatch = ((sectionDelta + previousNumberOfSections) == currentNumberOfSections);

    if (!sectionCountsMatch) {
        DDLogError(@"Mismatched section update counts: %@ + %@ != %@", @(sectionDelta), @(previousNumberOfSections), @(currentNumberOfSections));
    }

    shouldReload = shouldReload || !sectionCountsMatch;

    if (shouldReload) {
        [self.collectionView reloadData];
    } else {
        [self.collectionView performBatchUpdates:^{
            NSMutableIndexSet *deletedSections = [NSMutableIndexSet indexSet];
            NSMutableIndexSet *insertedSections = [NSMutableIndexSet indexSet];
            for (WMFObjectChange *change in self.objectChanges) {
                switch (change.type) {
                    case NSFetchedResultsChangeInsert: {
                        NSInteger insertedIndex = change.toIndexPath.row;
                        [self.collectionView insertSections:[NSIndexSet indexSetWithIndex:insertedIndex]];
                        [insertedSections addIndex:insertedIndex];
                    } break;
                    case NSFetchedResultsChangeDelete: {
                        NSInteger deletedIndex = change.fromIndexPath.row;
                        [self.collectionView deleteSections:[NSIndexSet indexSetWithIndex:deletedIndex]];
                        [deletedSections addIndex:deletedIndex];
                    } break;
                    case NSFetchedResultsChangeUpdate: {
                        if (change.toIndexPath && change.fromIndexPath && ![change.toIndexPath isEqual:change.fromIndexPath]) {
                            if ([deletedSections containsIndex:change.fromIndexPath.row]) {
                                [self.collectionView insertSections:[NSIndexSet indexSetWithIndex:change.toIndexPath.row]];
                            } else {
                                [self.collectionView deleteSections:[NSIndexSet indexSetWithIndex:change.fromIndexPath.row]];
                                [self.collectionView insertSections:[NSIndexSet indexSetWithIndex:change.toIndexPath.row]];
                            }
                        } else {
                            NSIndexPath *updatedIndexPath = change.toIndexPath ?: change.fromIndexPath;
                            NSInteger sectionIndex = updatedIndexPath.row;
                            if ([insertedSections containsIndex:updatedIndexPath.row]) {
                                [self.collectionView insertSections:[NSIndexSet indexSetWithIndex:sectionIndex]];
                            } else {
                                NSInteger previousCount = [previousSectionCounts[sectionIndex] integerValue];
                                NSInteger currentCount = [self.sectionCounts[sectionIndex] integerValue];
                                if (previousCount == currentCount) {
                                    [self.collectionView reloadSections:[NSIndexSet indexSetWithIndex:sectionIndex]];
                                    continue;
                                }

                                while (previousCount > currentCount) {
                                    [self.collectionView deleteItemsAtIndexPaths:@[[NSIndexPath indexPathForItem:previousCount - 1 inSection:sectionIndex]]];
                                    previousCount--;
                                }

                                while (previousCount < currentCount) {
                                    [self.collectionView insertItemsAtIndexPaths:@[[NSIndexPath indexPathForItem:previousCount inSection:sectionIndex]]];
                                    previousCount++;
                                }

                                [self.collectionView reloadSections:[NSIndexSet indexSetWithIndex:sectionIndex]];
                            }
                        }
                    } break;
                    case NSFetchedResultsChangeMove:
                        [self.collectionView deleteSections:[NSIndexSet indexSetWithIndex:change.fromIndexPath.row]];
                        [self.collectionView insertSections:[NSIndexSet indexSetWithIndex:change.toIndexPath.row]];
                        break;
                }
            }
        }
                                      completion:^(BOOL finished){

                                      }];
    }

    [self.objectChanges removeAllObjects];
    [self.sectionChanges removeAllObjects];
}

#pragma mark - WMFAnnouncementCollectionViewCellDelegate

- (void)announcementCellDidTapDismiss:(WMFAnnouncementCollectionViewCell *)cell {
    NSIndexPath *indexPath = [self.collectionView indexPathForCell:cell];
    WMFContentGroup *group = [self sectionAtIndex:indexPath.section];
    [[PiwikTracker sharedInstance] wmf_logActionDismissInContext:self contentType:group value:group];
    [self dismissAnnouncementCell:cell];
}

- (void)announcementCellDidTapActionButton:(WMFAnnouncementCollectionViewCell *)cell {
    NSIndexPath *indexPath = [self.collectionView indexPathForCell:cell];
    WMFContentGroup *group = [self sectionAtIndex:indexPath.section];
    [[PiwikTracker sharedInstance] wmf_logActionTapThroughInContext:self contentType:group value:group];
    NSArray<WMFAnnouncement *> *announcements = [self contentForGroup:group];
    if (indexPath.item >= announcements.count) {
        return;
    }
    WMFAnnouncement *announcement = announcements[indexPath.item];
    NSURL *url = announcement.actionURL;
    [self wmf_openExternalUrl:url];
    [self dismissAnnouncementCell:cell];
}

- (void)announcementCell:(WMFAnnouncementCollectionViewCell *)cell didTapLinkURL:(NSURL *)url {
    [self wmf_openExternalUrl:url];
}

- (void)dismissAnnouncementCell:(WMFAnnouncementCollectionViewCell *)cell {
    NSIndexPath *indexPath = [self.collectionView indexPathForCell:cell];
    WMFContentGroup *contentGroup = [self sectionForIndexPath:indexPath];
    NSParameterAssert(contentGroup);
    if (!contentGroup) {
        return;
    }
    if (contentGroup.contentGroupKind != WMFContentGroupKindAnnouncement) {
        return;
    }
    [contentGroup markDismissed];
    [contentGroup updateVisibility];
    NSError *saveError = nil;
    [self.userStore save:&saveError];
    if (saveError) {
        DDLogError(@"Error saving after announcement dismissal: %@", saveError);
    }
}

#pragma mark - Analytics

- (NSString *)analyticsContext {
    return @"Explore";
}

- (NSString *)analyticsName {
    return [self analyticsContext];
}

@end

NS_ASSUME_NONNULL_END
