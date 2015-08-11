
#import "WMFAppViewController.h"
#import "SessionSingleton.h"
#import "WMFStyleManager.h"
#import "WMFSearchViewController.h"
#import "WMFArticleListCollectionViewController.h"
#import "DataMigrationProgressViewController.h"
#import "WMFSavedPagesDataSource.h"
#import "WMFRecentPagesDataSource.h"
#import "UIStoryboard+WMFExtensions.h"
#import "UITabBarController+WMFExtensions.h"
#import "UIViewController+WMFHideKeyboard.h"
#import <Masonry/Masonry.h>
#import "MediaWikiKit.h"
#import "UIFont+WMFStyle.h"
#import "NSString+WMFGlyphs.h"
#import "WMFNavigationTransitionController.h"

/**
 *  Enums for each tab in the main tab bar.
 *
 *  @warning Be sure to update `WMFAppTabCount` when these enums change, and always initialize the first enum to 0.
 *
 *  @see WMFAppTabCount
 */
typedef NS_ENUM (NSUInteger, WMFAppTabType){
    WMFAppTabTypeHome = 0,
    WMFAppTabTypeSearch,
    WMFAppTabTypeSaved,
    WMFAppTabTypeRecent
};

/**
 *  Number of tabs in the main tab bar.
 *
 *  @warning Kept as a separate constant to prevent switch statements from being considered inexhaustive. This means we
 *           need to make sure it's manually kept in sync by ensuring:
 *              - The tab enum we increment is the last one
 *              - The first tab enum is initialized to 0
 *
 *  @see WMFAppTabType
 */
static NSUInteger const WMFAppTabCount = WMFAppTabTypeRecent + 1;


@interface WMFAppViewController ()<UITabBarControllerDelegate>
@property (strong, nonatomic) IBOutlet UIView* tabControllerContainerView;

@property (nonatomic, strong) IBOutlet UIView* splashView;
@property (nonatomic, strong) UITabBarController* rootTabBarController;

@property (nonatomic, strong, readonly) WMFSearchViewController* searchViewController;
@property (nonatomic, strong, readonly) WMFArticleListCollectionViewController* savedArticlesViewController;
@property (nonatomic, strong, readonly) WMFArticleListCollectionViewController* recentArticlesViewController;

@property (nonatomic, strong) SessionSingleton* session;

@property (nonatomic, strong) WMFNavigationTransitionController* navigationTransitionController;

@end

@implementation WMFAppViewController

#pragma mark - Setup

- (void)loadMainUI {
    [self configureTabController];
    [self configureSearchViewController];
    [self configureSavedViewController];
    [self configureRecentViewController];
}

- (void)configureTabController {
    self.rootTabBarController.delegate = self;

    for (WMFAppTabType i = 0; i < WMFAppTabCount; i++) {
        UINavigationController* navigationController = [self navigationControllerForTab:i];
//        navigationController.delegate = self.navigationTransitionController;
        navigationController.hidesBarsOnSwipe             = YES;
        navigationController.hidesBarsOnTap               = YES;
        navigationController.hidesBarsWhenKeyboardAppears = YES;
        navigationController.navigationBarHidden          = NO;
    }
}

- (void)configureSearchViewController {
    self.searchViewController.searchSite  = [self.session searchSite];
    self.searchViewController.dataStore   = self.session.dataStore;
    self.searchViewController.savedPages  = self.session.userDataStore.savedPageList;
    self.searchViewController.recentPages = self.session.userDataStore.historyList;
}

- (void)configureArticleListController:(WMFArticleListCollectionViewController*)controller {
    controller.dataStore   = self.session.dataStore;
    controller.savedPages  = self.session.userDataStore.savedPageList;
    controller.recentPages = self.session.userDataStore.historyList;
}

- (void)configureSavedViewController {
    [self configureArticleListController:self.savedArticlesViewController];
    if (!self.savedArticlesViewController.dataSource) {
        self.savedArticlesViewController.dataSource =
            [[WMFSavedPagesDataSource alloc] initWithSavedPagesList:[self userDataStore].savedPageList];
    }
}

- (void)configureRecentViewController {
    [self configureArticleListController:self.recentArticlesViewController];
    if (!self.recentArticlesViewController.dataSource) {
        self.recentArticlesViewController.dataSource =
            [[WMFRecentPagesDataSource alloc] initWithRecentPagesList:[self userDataStore].historyList];
    }
}

#pragma mark - Public

+ (WMFAppViewController*)initialAppViewControllerFromDefaultStoryBoard {
    return [[UIStoryboard wmf_appRootStoryBoard] instantiateInitialViewController];
}

- (void)launchAppInWindow:(UIWindow*)window {
    WMFStyleManager* manager = [WMFStyleManager new];
    [manager applyStyleToWindow:window];
    [WMFStyleManager setSharedStyleManager:manager];

    [window setRootViewController:self];
    [window makeKeyAndVisible];
}

- (void)resumeApp {
    //TODO: restore any UI, show Today
}

#pragma mark - Utilities

- (UINavigationController*)navigationControllerForTab:(WMFAppTabType)tab {
    return (UINavigationController*)[self.rootTabBarController viewControllers][tab];
}

- (UIViewController*)rootViewControllerForTab:(WMFAppTabType)tab {
    return [[[self navigationControllerForTab:tab] viewControllers] firstObject];
}

#pragma mark - Accessors

- (WMFNavigationTransitionController*)navigationTransitionController {
    if (!_navigationTransitionController) {
        _navigationTransitionController = [WMFNavigationTransitionController new];
    }
    return _navigationTransitionController;
}

- (SessionSingleton*)session {
    if (!_session) {
        _session = [SessionSingleton sharedInstance];
    }

    return _session;
}

- (MWKDataStore*)dataStore {
    return self.session.dataStore;
}

- (MWKUserDataStore*)userDataStore {
    return self.session.userDataStore;
}

- (WMFSearchViewController*)searchViewController {
    return (WMFSearchViewController*)[self rootViewControllerForTab:WMFAppTabTypeSearch];
}

- (WMFArticleListCollectionViewController*)savedArticlesViewController {
    return (WMFArticleListCollectionViewController*)[self rootViewControllerForTab:WMFAppTabTypeSaved];
}

- (WMFArticleListCollectionViewController*)recentArticlesViewController {
    return (WMFArticleListCollectionViewController*)[self rootViewControllerForTab:WMFAppTabTypeRecent];
}

#pragma mark - UIViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self showSplashView];

    [self runDataMigrationIfNeededWithCompletion:^{
        [self hideSplashViewAnimated:YES];
        [self loadMainUI];
    }];
}

- (void)prepareForSegue:(UIStoryboardSegue*)segue sender:(id)sender {
    if ([segue.destinationViewController isKindOfClass:[UITabBarController class]]) {
        self.rootTabBarController = segue.destinationViewController;
        [self configureTabController];
    }
}

- (BOOL)shouldAutorotate {
    return YES;
}

- (NSUInteger)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAll;
}

#pragma mark - Splash

- (void)showSplashView {
    self.splashView.hidden          = NO;
    self.splashView.layer.transform = CATransform3DIdentity;
    self.splashView.alpha           = 1.0;
}

- (void)hideSplashViewAnimated:(BOOL)animated {
    NSTimeInterval duration = animated ? 0.3 : 0.0;

    [UIView animateWithDuration:duration animations:^{
        self.splashView.layer.transform = CATransform3DMakeScale(10.0f, 10.0f, 1.0f);
        self.splashView.alpha = 0.0;
    } completion:^(BOOL finished) {
        self.splashView.hidden = YES;
        self.splashView.layer.transform = CATransform3DIdentity;
    }];
}

- (BOOL)isShowingSplashView {
    return self.splashView.hidden == NO;
}

#pragma mark - Migration

- (void)runDataMigrationIfNeededWithCompletion:(dispatch_block_t)completion {
    DataMigrationProgressViewController* migrationVC = [[DataMigrationProgressViewController alloc] init];
    [migrationVC removeOldDataBackupIfNeeded];

    if (![migrationVC needsMigration]) {
        if (completion) {
            completion();
        }
        return;
    }

    [self presentViewController:migrationVC animated:YES completion:^{
        [migrationVC runMigrationWithCompletion:^(BOOL migrationCompleted) {
            [migrationVC dismissViewControllerAnimated:YES completion:NULL];
            if (completion) {
                completion();
            }
        }];
    }];
}

- (void)tabBarController:(UITabBarController*)tabBarController didSelectViewController:(UIViewController*)viewController {
    [self wmf_hideKeyboard];
}

@end
