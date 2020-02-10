#import <WMF/WMF-Swift.h>
#include <notify.h>
#import <sqlite3.h>
#import "WMFArticlePreview.h"
#import "WMFAnnouncement.h"

@import CoreData;

// Emitted when article state changes. Can be used for things such as being notified when article 'saved' state changes.
NSString *const WMFArticleUpdatedNotification = @"WMFArticleUpdatedNotification";
NSString *const WMFArticleDeletedNotification = @"WMFArticleDeletedNotification";
NSString *const WMFArticleDeletedNotificationUserInfoArticleKeyKey = @"WMFArticleDeletedNotificationUserInfoArticleKeyKey";
NSString *const WMFBackgroundContextDidSave = @"WMFBackgroundContextDidSave";
NSString *const WMFFeedImportContextDidSave = @"WMFFeedImportContextDidSave";
NSString *const WMFViewContextDidSave = @"WMFViewContextDidSave";

NSString *const WMFLibraryVersionKey = @"WMFLibraryVersion";
static const NSInteger WMFCurrentLibraryVersion = 9;

NSString *const MWKDataStoreValidImageSitePrefix = @"//upload.wikimedia.org/";

NSString *MWKCreateImageURLWithPath(NSString *path) {
    return [MWKDataStoreValidImageSitePrefix stringByAppendingString:path];
}

static NSString *const MWKImageInfoFilename = @"ImageInfo.plist";

@interface MWKDataStore () {
    dispatch_semaphore_t _handleCrossProcessChangesSemaphore;
}

@property (readwrite, strong, nonatomic) MWKHistoryList *historyList;
@property (readwrite, strong, nonatomic) MWKSavedPageList *savedPageList;
@property (readwrite, strong, nonatomic) MWKRecentSearchList *recentSearchList;

@property (nonatomic, strong) WMFReadingListsController *readingListsController;
@property (nonatomic, strong) WMFExploreFeedContentController *feedContentController;
@property (nonatomic, strong) WikidataDescriptionEditingController *wikidataDescriptionEditingController;
@property (nonatomic, strong) RemoteNotificationsController *remoteNotificationsController;
@property (nonatomic, strong) WMFArticleSummaryController *articleSummaryController;

@property (nonatomic, strong) WMFCacheControllerWrapper *imageCacheControllerWrapper;
@property (nonatomic, strong) WMFCacheControllerWrapper *articleCacheControllerWrapper;

@property (nonatomic, strong) MobileviewToMobileHTMLConverter *mobileviewConverter;

@property (readwrite, copy, nonatomic) NSString *basePath;
@property (readwrite, strong, nonatomic) NSCache *articleCache;
@property (readwrite, strong, nonatomic) NSCache *articlePreviewCache;

@property (readwrite, nonatomic, strong) dispatch_queue_t cacheRemovalQueue;
@property (readwrite, nonatomic, getter=isCacheRemovalActive) BOOL cacheRemovalActive;
@property (readwrite, strong, nullable) dispatch_block_t cacheRemovalCompletion;

@property (nonatomic, strong) NSPersistentStoreCoordinator *persistentStoreCoordinator;
@property (nonatomic, strong) NSManagedObjectContext *viewContext;
@property (nonatomic, strong) NSManagedObjectContext *feedImportContext;

@property (nonatomic, strong) NSString *crossProcessNotificationChannelName;
@property (nonatomic) int crossProcessNotificationToken;

@property (nonatomic, strong) NSURL *containerURL;

@property (readwrite, nonatomic) RemoteConfigOption remoteConfigsThatFailedUpdate;

@end

@implementation MWKDataStore

- (void)cacheArticle:(MWKArticle *)article toDisk:(BOOL)toDisk error:(NSError **)error {
    if (!article) {
        return;
    }
    [self addArticleToMemoryCache:article];
    if (!toDisk) {
        return;
    }
    [article save:error];
}

#pragma mark - NSObject

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (instancetype)init {
    self = [self initWithContainerURL:[[NSFileManager defaultManager] wmf_containerURL]];
    return self;
}

static uint64_t bundleHash() {
    static dispatch_once_t onceToken;
    static uint64_t bundleHash;
    dispatch_once(&onceToken, ^{
        bundleHash = (uint64_t)[[[NSBundle mainBundle] bundleIdentifier] hash];
    });
    return bundleHash;
}

- (instancetype)initWithContainerURL:(NSURL *)containerURL {
    self = [super init];
    if (self) {
        _handleCrossProcessChangesSemaphore = dispatch_semaphore_create(1);
        self.containerURL = containerURL;
        self.basePath = [self.containerURL URLByAppendingPathComponent:@"Data" isDirectory:YES].path;
        [self setupLegacyDataStore];
        NSDictionary *infoDictionary = [self loadSharedInfoDictionaryWithContainerURL:containerURL];
        self.crossProcessNotificationChannelName = infoDictionary[@"CrossProcessNotificiationChannelName"];
        [self setupCrossProcessCoreDataNotifier];
        [self setupCoreDataStackWithContainerURL:containerURL];
        [self setupHistoryAndSavedPageLists];
        self.feedContentController = [[WMFExploreFeedContentController alloc] init];
        self.feedContentController.dataStore = self;
        self.feedContentController.siteURLs = [[MWKLanguageLinkController sharedInstance] preferredSiteURLs];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didReceiveMemoryWarningWithNotification:) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
        self.wikidataDescriptionEditingController = [[WikidataDescriptionEditingController alloc] initWithSession:[WMFSession shared] configuration:[WMFConfiguration current]];
        self.remoteNotificationsController = [[RemoteNotificationsController alloc] initWithSession:[WMFSession shared] configuration:[WMFConfiguration current]];
        WMFArticleSummaryFetcher *fetcher = [[WMFArticleSummaryFetcher alloc] initWithSession:[WMFSession shared] configuration:[WMFConfiguration current]];
        self.articleSummaryController = [[WMFArticleSummaryController alloc] initWithFetcher:fetcher dataStore:self];
        self.imageCacheControllerWrapper = [[WMFCacheControllerWrapper alloc] initWithType:WMFCacheControllerTypeImage];
        self.articleCacheControllerWrapper = [[WMFCacheControllerWrapper alloc] initWithArticleCacheWithImageCacheControllerWrapper:self.imageCacheControllerWrapper];
        self.mobileviewConverter = [[MobileviewToMobileHTMLConverter alloc] init];
    }
    return self;
}

- (NSDictionary *)loadSharedInfoDictionaryWithContainerURL:(NSURL *)containerURL {
    NSURL *infoDictionaryURL = [containerURL URLByAppendingPathComponent:@"Wikipedia.info" isDirectory:NO];
    NSData *infoDictionaryData = [NSData dataWithContentsOfURL:infoDictionaryURL];
    NSDictionary *infoDictionary = [NSKeyedUnarchiver unarchiveObjectWithData:infoDictionaryData];
    if (!infoDictionary[@"CrossProcessNotificiationChannelName"]) {
        NSString *channelName = [NSString stringWithFormat:@"org.wikimedia.wikipedia.cd-cpn-%@", [NSUUID new].UUIDString].lowercaseString;
        infoDictionary = @{@"CrossProcessNotificiationChannelName": channelName};
        NSData *data = [NSKeyedArchiver archivedDataWithRootObject:infoDictionary];
        [data writeToURL:infoDictionaryURL atomically:YES];
    }
    return infoDictionary;
}

- (void)setupCrossProcessCoreDataNotifier {
    NSString *channelName = self.crossProcessNotificationChannelName;
    assert(channelName);
    if (!channelName) {
        DDLogError(@"missing channel name");
        return;
    }
    const char *name = [channelName UTF8String];
    notify_register_dispatch(name, &_crossProcessNotificationToken, dispatch_get_main_queue(), ^(int token) {
        uint64_t state;
        notify_get_state(token, &state);
        BOOL isExternal = state != bundleHash();
        if (isExternal) {
            [self handleCrossProcessCoreDataNotificationWithState:state];
        }
    });
}

- (void)handleCrossProcessCoreDataNotificationWithState:(uint64_t)state {
    NSURL *baseURL = self.containerURL;
    NSString *fileName = [NSString stringWithFormat:@"%llu.changes", state];
    NSURL *fileURL = [baseURL URLByAppendingPathComponent:fileName isDirectory:NO];
    NSData *data = [NSData dataWithContentsOfURL:fileURL];
    NSDictionary *userInfo = [NSKeyedUnarchiver unarchiveObjectWithData:data];
    [NSManagedObjectContext mergeChangesFromRemoteContextSave:userInfo intoContexts:@[self.viewContext]];
}

- (void)setupCoreDataStackWithContainerURL:(NSURL *)containerURL {
    NSURL *modelURL = [[NSBundle wmf] URLForResource:@"Wikipedia" withExtension:@"momd"];
    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL];
    NSString *coreDataDBName = @"Wikipedia.sqlite";

    NSURL *coreDataDBURL = [containerURL URLByAppendingPathComponent:coreDataDBName isDirectory:NO];
    NSPersistentStoreCoordinator *persistentStoreCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
    NSDictionary *options = @{NSMigratePersistentStoresAutomaticallyOption: @YES,
                              NSInferMappingModelAutomaticallyOption: @YES};
    NSError *persistentStoreError = nil;
    if (nil == [persistentStoreCoordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:coreDataDBURL options:options error:&persistentStoreError]) {
        // TODO: Metrics
        DDLogError(@"Error adding persistent store: %@", persistentStoreError);
        NSError *moveError = nil;
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSString *uuid = [[NSUUID UUID] UUIDString];
        NSURL *moveURL = [[containerURL URLByAppendingPathComponent:uuid] URLByAppendingPathExtension:@"sqlite"];
        [fileManager moveItemAtURL:coreDataDBURL toURL:moveURL error:&moveError];
        if (moveError) {
            // TODO: Metrics
            [fileManager removeItemAtURL:coreDataDBURL error:nil];
        }
        persistentStoreError = nil;
        if (nil == [persistentStoreCoordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:coreDataDBURL options:options error:&persistentStoreError]) {
            // TODO: Metrics
            DDLogError(@"Second error after adding persistent store: %@", persistentStoreError);
        }
    }

    self.persistentStoreCoordinator = persistentStoreCoordinator;
    self.viewContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
    self.viewContext.persistentStoreCoordinator = persistentStoreCoordinator;
    self.viewContext.mergePolicy = NSMergeByPropertyStoreTrumpMergePolicy;
    self.viewContext.automaticallyMergesChangesFromParent = YES;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(managedObjectContextDidSave:) name:NSManagedObjectContextDidSaveNotification object:self.viewContext];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(viewContextDidChange:) name:NSManagedObjectContextObjectsDidChangeNotification object:self.viewContext];
}

- (nullable id)archiveableNotificationValueForValue:(id)value {
    if ([value isKindOfClass:[NSManagedObject class]]) {
        return [[value objectID] URIRepresentation];
    } else if ([value isKindOfClass:[NSManagedObjectID class]]) {
        return [value URIRepresentation];
    } else if ([value isKindOfClass:[NSSet class]] || [value isKindOfClass:[NSArray class]]) {
        return [value wmf_map:^id(id obj) {
            return [self archiveableNotificationValueForValue:obj];
        }];
    } else if ([value conformsToProtocol:@protocol(NSCoding)]) {
        return value;
    } else {
        return nil;
    }
}

- (NSDictionary *)archivableNotificationUserInfoForUserInfo:(NSDictionary *)userInfo {
    NSMutableDictionary *archiveableUserInfo = [NSMutableDictionary dictionaryWithCapacity:userInfo.count];
    NSArray *allKeys = userInfo.allKeys;
    for (NSString *key in allKeys) {
        id value = userInfo[key];
        if ([value isKindOfClass:[NSDictionary class]]) {
            value = [self archivableNotificationUserInfoForUserInfo:value];
        } else {
            value = [self archiveableNotificationValueForValue:value];
        }
        if (value) {
            archiveableUserInfo[key] = value;
        }
    }
    return archiveableUserInfo;
}

- (void)handleCrossProcessChangesFromContextDidSaveNotification:(NSNotification *)note {
    dispatch_semaphore_wait(_handleCrossProcessChangesSemaphore, DISPATCH_TIME_FOREVER);
    NSDictionary *userInfo = note.userInfo;
    if (!userInfo) {
        return;
    }

    uint64_t state = bundleHash();

    NSDictionary *archiveableUserInfo = [self archivableNotificationUserInfoForUserInfo:userInfo];
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:archiveableUserInfo];
    NSURL *baseURL = [[NSFileManager defaultManager] wmf_containerURL];
    NSString *fileName = [NSString stringWithFormat:@"%llu.changes", state];
    NSURL *fileURL = [baseURL URLByAppendingPathComponent:fileName isDirectory:NO];
    [data writeToURL:fileURL atomically:YES];

    const char *name = [self.crossProcessNotificationChannelName UTF8String];
    notify_set_state(_crossProcessNotificationToken, state);
    notify_post(name);
    dispatch_semaphore_signal(_handleCrossProcessChangesSemaphore);
}

- (void)viewContextDidChange:(NSNotification *)note {
    NSDictionary *userInfo = note.userInfo;
    NSArray<NSString *> *keys = @[NSInsertedObjectsKey, NSUpdatedObjectsKey, NSDeletedObjectsKey, NSRefreshedObjectsKey, NSInvalidatedObjectsKey];
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    for (NSString *key in keys) {
        NSSet<NSManagedObject *> *changedObjects = userInfo[key];
        for (NSManagedObject *object in changedObjects) {
            if ([object isKindOfClass:[WMFArticle class]]) {
                WMFArticle *article = (WMFArticle *)object;
                NSString *articleKey = article.key;
                NSURL *articleURL = article.URL;
                if (!articleKey || !articleURL) {
                    continue;
                }
                [self.articlePreviewCache removeObjectForKey:articleKey];
                if ([key isEqualToString:NSDeletedObjectsKey]) { // Could change WMFArticleUpdatedNotification to use UserInfo for consistency but want to keep change set minimal at this point
                    [nc postNotificationName:WMFArticleDeletedNotification object:[note object] userInfo:@{WMFArticleDeletedNotificationUserInfoArticleKeyKey: articleKey}];
                } else {
                    [nc postNotificationName:WMFArticleUpdatedNotification object:article];
                }
            }
        }
    }
}

- (void)migrateArticlePreviews:(NSDictionary<NSString *, WMFArticlePreview *> *)articlePreviews historyEntries:(NSDictionary<NSString *, MWKHistoryEntry *> *)historyEntries toManagedObjectContext:(NSManagedObjectContext *)moc {
    if (articlePreviews.count == 0 && historyEntries.count == 0) {
        return;
    }

    NSMutableSet *keysToAdd = [NSMutableSet setWithArray:articlePreviews.allKeys];
    [keysToAdd unionSet:[NSSet setWithArray:historyEntries.allKeys]];

    NSFetchRequest *existingObjectFetchRequest = [WMFArticle fetchRequest];
    existingObjectFetchRequest.predicate = [NSPredicate predicateWithFormat:@"key in %@", keysToAdd];
    NSArray<WMFArticle *> *allExistingObjects = [moc executeFetchRequest:existingObjectFetchRequest error:nil];

    void (^updateBlock)(MWKHistoryEntry *, WMFArticlePreview *, WMFArticle *) = ^(MWKHistoryEntry *entry, WMFArticlePreview *preview, WMFArticle *article) {
        if (entry) {
            article.viewedDate = entry.dateViewed;
            [article updateViewedDateWithoutTime];
            article.viewedFragment = entry.fragment;
            article.viewedScrollPosition = entry.scrollPosition;
            article.savedDate = entry.dateSaved;
            article.isExcludedFromFeed = entry.blackListed;
            article.wasSignificantlyViewed = entry.titleWasSignificantlyViewed;
            article.newsNotificationDate = entry.inTheNewsNotificationDate;
            article.viewedScrollPosition = entry.scrollPosition;
        }
        if (preview) {
            article.displayTitleHTML = preview.displayTitle;
            article.wikidataDescription = preview.wikidataDescription;
            article.snippet = preview.snippet;
            article.thumbnailURL = preview.thumbnailURL;
            article.location = preview.location;
            article.pageViews = preview.pageViews;
        }
    };

    for (WMFArticle *article in allExistingObjects) {
        NSString *key = article.key;
        if (!key) {
            [moc deleteObject:article];
            continue;
        }
        MWKHistoryEntry *entry = historyEntries[key];
        WMFArticlePreview *preview = articlePreviews[key];
        [keysToAdd removeObject:key];
        updateBlock(entry, preview, article);
    }

    for (NSString *key in keysToAdd) {
        MWKHistoryEntry *entry = historyEntries[key];
        WMFArticlePreview *preview = articlePreviews[key];
        WMFArticle *article = [moc createArticleWithKey:key];
        updateBlock(entry, preview, article);
    }
}

#pragma mark - Background Contexts

- (void)managedObjectContextDidSave:(NSNotification *)note {
    NSManagedObjectContext *moc = note.object;
    NSNotificationName notificationName;
    if (moc == _viewContext) {
        notificationName = WMFViewContextDidSave;
    } else if (moc == _feedImportContext) {
        notificationName = WMFFeedImportContextDidSave;
    } else {
        notificationName = WMFBackgroundContextDidSave;
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:notificationName object:note.object userInfo:note.userInfo];
    [self handleCrossProcessChangesFromContextDidSaveNotification:note];
}

- (void)performBackgroundCoreDataOperationOnATemporaryContext:(nonnull void (^)(NSManagedObjectContext *moc))mocBlock {
    WMFAssertMainThread(@"Background Core Data operations must be started from the main thread.");
    NSManagedObjectContext *backgroundContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
    backgroundContext.persistentStoreCoordinator = _persistentStoreCoordinator;
    backgroundContext.automaticallyMergesChangesFromParent = YES;
    backgroundContext.mergePolicy = NSMergeByPropertyStoreTrumpMergePolicy;
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(managedObjectContextDidSave:) name:NSManagedObjectContextDidSaveNotification object:backgroundContext];
    [backgroundContext performBlock:^{
        mocBlock(backgroundContext);
        [nc removeObserver:self name:NSManagedObjectContextDidSaveNotification object:backgroundContext];
    }];
}

- (NSManagedObjectContext *)feedImportContext {
    WMFAssertMainThread(@"feedImportContext must be created on the main thread");
    if (!_feedImportContext) {
        _feedImportContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
        _feedImportContext.persistentStoreCoordinator = _persistentStoreCoordinator;
        _feedImportContext.automaticallyMergesChangesFromParent = YES;
        _feedImportContext.mergePolicy = NSMergeByPropertyStoreTrumpMergePolicy;
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(managedObjectContextDidSave:) name:NSManagedObjectContextDidSaveNotification object:_feedImportContext];
    }
    return _feedImportContext;
}

- (void)teardownFeedImportContext {
    WMFAssertMainThread(@"feedImportContext must be torn down on the main thread");
    if (_feedImportContext) {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:NSManagedObjectContextDidSaveNotification object:_feedImportContext];
        _feedImportContext = nil;
    }
}

#pragma mark - Migrations

- (BOOL)migrateToReadingListsInManagedObjectContext:(NSManagedObjectContext *)moc error:(NSError **)migrationError {
    ReadingList *defaultReadingList = [moc wmf_fetchDefaultReadingList];
    if (!defaultReadingList) {
        defaultReadingList = [[ReadingList alloc] initWithContext:moc];
        defaultReadingList.canonicalName = [ReadingList defaultListCanonicalName];
        defaultReadingList.isDefault = YES;
    }

    for (ReadingListEntry *entry in defaultReadingList.entries) {
        entry.isUpdatedLocally = YES;
    }

    if ([moc hasChanges] && ![moc save:migrationError]) {
        return NO;
    }

    NSFetchRequest<WMFArticle *> *request = [WMFArticle fetchRequest];
    request.fetchLimit = 500;
    request.predicate = [NSPredicate predicateWithFormat:@"savedDate != NULL && readingLists.@count == 0", defaultReadingList];

    NSArray<WMFArticle *> *results = [moc executeFetchRequest:request error:migrationError];
    if (!results) {
        return NO;
    }

    NSError *addError = nil;

    while (results.count > 0) {
        for (WMFArticle *article in results) {
            [self.readingListsController addArticleToDefaultReadingList:article error:&addError];
            if (addError) {
                break;
            }
        }
        if (addError) {
            break;
        }
        if (![moc save:migrationError]) {
            return NO;
        }
        [moc reset];
        defaultReadingList = [moc wmf_fetchDefaultReadingList]; // needs to re-fetch after reset
        results = [moc executeFetchRequest:request error:migrationError];
        if (!defaultReadingList || !results) {
            return NO;
        }
    }
    if (addError) {
        DDLogError(@"Error adding to default reading list: %@", addError);
    } else {
        [moc wmf_setValue:@(5) forKey:WMFLibraryVersionKey];
    }

    return [moc save:migrationError];
}

- (BOOL)migrateMainPageContentGroupInManagedObjectContext:(NSManagedObjectContext *)moc error:(NSError **)migrationError {
    NSArray *mainPages = [moc contentGroupsOfKind:WMFContentGroupKindMainPage];
    for (WMFContentGroup *mainPage in mainPages) {
        [moc deleteObject:mainPage];
    }
    [moc wmf_setValue:@(6) forKey:WMFLibraryVersionKey];
    return [moc save:migrationError];
}

- (void)performUpdatesFromLibraryVersion:(NSUInteger)currentLibraryVersion inManagedObjectContext:(NSManagedObjectContext *)moc {
    NSError *migrationError = nil;
    if (currentLibraryVersion < 1) {
        if ([self migrateContentGroupsToPreviewContentInManagedObjectContext:moc error:nil]) {
            [moc wmf_setValue:@(1) forKey:WMFLibraryVersionKey];
            if ([moc hasChanges] && ![moc save:&migrationError]) {
                DDLogError(@"Error saving during migration: %@", migrationError);
                return;
            }
        } else {
            return;
        }
    }

    if (currentLibraryVersion < 5) {
        if (![self migrateToReadingListsInManagedObjectContext:moc error:&migrationError]) {
            DDLogError(@"Error during migration: %@", migrationError);
            return;
        }
    }

    if (currentLibraryVersion < 6) {
        if (![self migrateMainPageContentGroupInManagedObjectContext:moc error:&migrationError]) {
            DDLogError(@"Error during migration: %@", migrationError);
            return;
        }
    }

    if (currentLibraryVersion < 7) {
        NSError *fileProtectionError = nil;
        if ([self.containerURL setResourceValue:NSURLFileProtectionCompleteUntilFirstUserAuthentication forKey:NSURLFileProtectionKey error:&fileProtectionError]) {
            [moc wmf_setValue:@(7) forKey:WMFLibraryVersionKey];
            NSError *migrationSaveError = nil;
            if ([moc hasChanges] && ![moc save:&migrationSaveError]) {
                DDLogError(@"Error saving during migration: %@", migrationSaveError);
                return;
            }
        } else {
            DDLogError(@"Error enabling file protection: %@", fileProtectionError);
            return;
        }
    }

    if (currentLibraryVersion < 8) {
        NSUserDefaults *ud = [NSUserDefaults wmf];
        [ud removeObjectForKey:@"WMFOpenArticleURLKey"];
        [ud removeObjectForKey:@"WMFOpenArticleTitleKey"];
        [ud synchronize];
        [moc wmf_setValue:@(8) forKey:WMFLibraryVersionKey];
        if ([moc hasChanges] && ![moc save:&migrationError]) {
            DDLogError(@"Error saving during migration: %@", migrationError);
            return;
        }
    }

    if (currentLibraryVersion < 9) {
        [self markAllDownloadedArticlesInManagedObjectContextAsNeedingConversionFromMobileview:moc];
        [moc wmf_setValue:@(9) forKey:WMFLibraryVersionKey];
        if ([moc hasChanges] && ![moc save:&migrationError]) {
            DDLogError(@"Error saving during migration: %@", migrationError);
            return;
        }
    }

    // IMPORTANT: When adding a new library version and migration, update WMFCurrentLibraryVersion to the latest version number
}

/// Library updates are separate from Core Data migration and can be used to orchestrate migrations that are more complex than automatic Core Data migration allows.
/// They can also be used to perform migrations when the underlying Core Data model has not changed version but the apps' logic has changed in a way that requires data migration.
- (void)performLibraryUpdates:(dispatch_block_t)completion {
    NSNumber *libraryVersionNumber = [self.viewContext wmf_numberValueForKey:WMFLibraryVersionKey];
    // If the library value doesn't exist, it's a new library and can be set to the latest version
    if (!libraryVersionNumber) {
        [self.viewContext wmf_setValue:@(WMFCurrentLibraryVersion) forKey:WMFLibraryVersionKey];
        if (completion) {
            completion();
        }
        return;
    }
    NSInteger currentUserLibraryVersion = [libraryVersionNumber integerValue];
    // If the library version is >= the current version, we can skip the migration
    if (currentUserLibraryVersion >= WMFCurrentLibraryVersion) {
        if (completion) {
            completion();
        }
        return;
    }
    [self performBackgroundCoreDataOperationOnATemporaryContext:^(NSManagedObjectContext *moc) {
        dispatch_block_t done = ^{
            dispatch_async(dispatch_get_main_queue(), completion);
        };
        [self performUpdatesFromLibraryVersion:currentUserLibraryVersion inManagedObjectContext:moc];
        done();
    }];
}

- (void)markAllDownloadedArticlesInManagedObjectContextAsNeedingConversionFromMobileview:(NSManagedObjectContext *)moc {
    NSFetchRequest *request = [WMFArticle fetchRequest];
    request.predicate = [NSPredicate predicateWithFormat:@"isDownloaded == YES && isConversionFromMobileViewNeeded == NO"];
    request.fetchLimit = 500;
    request.propertiesToFetch = @[];
    NSError *fetchError = nil;
    NSArray *downloadedArticles = [moc executeFetchRequest:request error:&fetchError];
    if (fetchError) {
        DDLogError(@"Error fetching downloaded articles: %@", fetchError);
        return;
    }
    while (downloadedArticles.count > 0) {
        @autoreleasepool {
            for (WMFArticle *article in downloadedArticles) {
                article.isConversionFromMobileViewNeeded = YES;
            }
            if ([moc hasChanges]) {
                NSError *saveError = nil;
                [moc save:&saveError];
                if (saveError) {
                    DDLogError(@"Error saving downloaded articles: %@", fetchError);
                    return;
                }
                [moc reset];
            }
        }
        downloadedArticles = [moc executeFetchRequest:request error:&fetchError];
        if (fetchError) {
            DDLogError(@"Error fetching downloaded articles: %@", fetchError);
            return;
        }
    }
}

- (BOOL)migrateContentGroupsToPreviewContentInManagedObjectContext:(NSManagedObjectContext *)moc error:(NSError **)error {
    NSFetchRequest *request = [WMFContentGroup fetchRequest];
    request.predicate = [NSPredicate predicateWithFormat:@"content != NULL"];
    request.fetchLimit = 500;
    NSError *fetchError = nil;
    NSArray *contentGroups = [moc executeFetchRequest:request error:&fetchError];
    if (fetchError) {
        DDLogError(@"Error fetching content groups: %@", fetchError);
        if (error) {
            *error = fetchError;
        }
        return false;
    }

    while (contentGroups.count > 0) {
        @autoreleasepool {
            NSMutableArray *toDelete = [NSMutableArray arrayWithCapacity:1];
            for (WMFContentGroup *contentGroup in contentGroups) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
                NSArray *content = contentGroup.content;
                if (!content) {
                    continue;
                }
                contentGroup.fullContentObject = content;
                contentGroup.featuredContentIdentifier = contentGroup.articleURLString;
                [contentGroup updateContentPreviewWithContent:content];
                contentGroup.content = nil;
#pragma clang diagnostic pop
                if (contentGroup.contentPreview == nil) {
                    [toDelete addObject:contentGroup];
                }
            }
            for (WMFContentGroup *group in toDelete) {
                [moc deleteObject:group];
            }

            if ([moc hasChanges]) {
                NSError *saveError = nil;
                [moc save:&saveError];
                if (saveError) {
                    DDLogError(@"Error saving downloaded articles: %@", fetchError);
                    if (error) {
                        *error = saveError;
                    }
                    return false;
                }
                [moc reset];
            }
        }

        contentGroups = [moc executeFetchRequest:request error:&fetchError];
        if (fetchError) {
            DDLogError(@"Error fetching content groups: %@", fetchError);
            if (error) {
                *error = fetchError;
            }
            return false;
        }
    }
    return true;
}

- (void)markAllDownloadedArticlesInManagedObjectContextAsUndownloaded:(NSManagedObjectContext *)moc {
    NSFetchRequest *request = [WMFArticle fetchRequest];
    request.predicate = [NSPredicate predicateWithFormat:@"isDownloaded == YES"];
    request.fetchLimit = 500;
    NSError *fetchError = nil;
    NSArray *downloadedArticles = [moc executeFetchRequest:request error:&fetchError];
    if (fetchError) {
        DDLogError(@"Error fetching downloaded articles: %@", fetchError);
        return;
    }

    while (downloadedArticles.count > 0) {
        @autoreleasepool {
            for (WMFArticle *article in downloadedArticles) {
                article.isDownloaded = NO;
            }

            if ([moc hasChanges]) {
                NSError *saveError = nil;
                [moc save:&saveError];
                if (saveError) {
                    DDLogError(@"Error saving downloaded articles: %@", fetchError);
                    return;
                }
                [moc reset];
            }
        }

        downloadedArticles = [moc executeFetchRequest:request error:&fetchError];
        if (fetchError) {
            DDLogError(@"Error fetching downloaded articles: %@", fetchError);
            return;
        }
    }
}

#pragma mark - Memory

- (void)didReceiveMemoryWarningWithNotification:(NSNotification *)note {
    [self clearMemoryCache];
}

#pragma - Accessors

- (MWKRecentSearchList *)recentSearchList {
    if (!_recentSearchList) {
        _recentSearchList = [[MWKRecentSearchList alloc] initWithDataStore:self];
    }
    return _recentSearchList;
}

#pragma mark - History and Saved Page List

- (void)setupHistoryAndSavedPageLists {
    WMFAssertMainThread(@"History and saved page lists must be setup on the main thread");
    self.historyList = [[MWKHistoryList alloc] initWithDataStore:self];
    self.savedPageList = [[MWKSavedPageList alloc] initWithDataStore:self];
    self.readingListsController = [[WMFReadingListsController alloc] initWithDataStore:self];
}

#pragma mark - Legacy DataStore

+ (NSString *)mainDataStorePath {
    NSString *documentsFolder = [[NSFileManager defaultManager] wmf_containerPath];
    return [documentsFolder stringByAppendingPathComponent:@"Data"];
}

+ (NSString *)appSpecificMainDataStorePath { //deprecated, use the group folder from mainDataStorePath
    NSString *documentsFolder =
        [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    return [documentsFolder stringByAppendingPathComponent:@"Data"];
}

- (void)setupLegacyDataStore {
    NSString *pathToExclude = [self pathForSites];
    NSError *directoryCreationError = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:pathToExclude withIntermediateDirectories:YES attributes:nil error:&directoryCreationError]) {
        DDLogError(@"Error creating MWKDataStore path: %@", directoryCreationError);
    }
    NSURL *directoryURL = [NSURL fileURLWithPath:pathToExclude isDirectory:YES];
    NSError *excludeBackupError = nil;
    if (![directoryURL setResourceValue:@(YES) forKey:NSURLIsExcludedFromBackupKey error:&excludeBackupError]) {
        DDLogError(@"Error excluding MWKDataStore path from backup: %@", excludeBackupError);
    }
    self.articleCache = [[NSCache alloc] init];
    self.articleCache.countLimit = 50;

    self.articlePreviewCache = [[NSCache alloc] init];
    self.articlePreviewCache.countLimit = 1000;

    self.cacheRemovalQueue = dispatch_queue_create("org.wikimedia.cache_removal", DISPATCH_QUEUE_SERIAL);
}

#pragma mark - path methods

- (NSString *)joinWithBasePath:(NSString *)path {
    return [self.basePath stringByAppendingPathComponent:path];
}

- (NSString *)pathForSites {
    return [self joinWithBasePath:@"sites"];
}

- (NSString *)pathForDomainInURL:(NSURL *)url {
    NSString *sitesPath = [self pathForSites];
    NSString *domainPath = [sitesPath stringByAppendingPathComponent:url.wmf_domain];
    return [domainPath stringByAppendingPathComponent:url.wmf_language];
}

- (NSString *)pathForArticlesInDomainFromURL:(NSURL *)url {
    NSString *sitePath = [self pathForDomainInURL:url];
    return [sitePath stringByAppendingPathComponent:@"articles"];
}

/// Returns the folder where data for the correspnoding title is stored.
- (NSString *)pathForArticleURL:(NSURL *)url {
    NSString *articlesPath = [self pathForArticlesInDomainFromURL:url];
    NSString *encTitle = [self safeFilenameWithString:url.wmf_titleWithUnderscores];
    return [articlesPath stringByAppendingPathComponent:encTitle];
}

- (NSString *)pathForArticle:(MWKArticle *)article {
    return [self pathForArticleURL:article.url];
}

- (NSString *)pathForSectionsInArticleWithURL:(NSURL *)url {
    NSString *articlePath = [self pathForArticleURL:url];
    return [articlePath stringByAppendingPathComponent:@"sections"];
}

- (NSString *)pathForSectionId:(NSUInteger)sectionId inArticleWithURL:(NSURL *)url {
    NSString *sectionsPath = [self pathForSectionsInArticleWithURL:url];
    NSString *sectionName = [NSString stringWithFormat:@"%d", (int)sectionId];
    return [sectionsPath stringByAppendingPathComponent:sectionName];
}

- (NSString *)pathForSection:(MWKSection *)section {
    return [self pathForSectionId:section.sectionId inArticleWithURL:section.url];
}

- (NSString *)pathForImagesWithArticleURL:(NSURL *)url {
    NSString *articlePath = [self pathForArticleURL:url];
    return [articlePath stringByAppendingPathComponent:@"Images"];
}

- (NSString *)pathForImageURL:(NSString *)imageURL forArticleURL:(NSURL *)articleURL {
    NSString *imagesPath = [self pathForImagesWithArticleURL:articleURL];
    NSString *encURL = [self safeFilenameWithImageURL:imageURL];
    return encURL ? [imagesPath stringByAppendingPathComponent:encURL] : nil;
}

- (NSString *)pathForImage:(MWKImage *)image {
    return [self pathForImageURL:image.sourceURLString forArticleURL:image.article.url];
}

- (NSString *)pathForImageInfoForArticleWithURL:(NSURL *)url {
    return [[self pathForArticleURL:url] stringByAppendingPathComponent:MWKImageInfoFilename];
}

- (NSString *)safeFilenameWithString:(NSString *)str {
    // Escape only % and / with percent style for readability
    NSString *encodedStr = [str stringByReplacingOccurrencesOfString:@"%" withString:@"%25"];
    encodedStr = [encodedStr stringByReplacingOccurrencesOfString:@"/" withString:@"%2F"];

    return encodedStr;
}

- (NSString *)stringWithSafeFilename:(NSString *)str {
    return [str stringByRemovingPercentEncoding];
}

- (NSString *)safeFilenameWithImageURL:(NSString *)str {
    str = [str wmf_schemelessURL];

    if (![str hasPrefix:MWKDataStoreValidImageSitePrefix]) {
        return nil;
    }

    NSString *suffix = [str substringFromIndex:[MWKDataStoreValidImageSitePrefix length]];
    NSString *fileName = [suffix lastPathComponent];

    // Image URLs are already percent-encoded, so don't double-encode em.
    // In fact, we want to decode them...
    // If we don't, long Unicode filenames may not fit in the filesystem.
    NSString *decodedFileName = [fileName stringByRemovingPercentEncoding];

    return decodedFileName;
}

#pragma mark - save methods

- (BOOL)ensurePathExists:(NSString *)path error:(NSError **)error {
    return [[NSFileManager defaultManager] createDirectoryAtPath:path
                                     withIntermediateDirectories:YES
                                                      attributes:nil
                                                           error:error];
}

- (void)ensurePathExists:(NSString *)path {
    [self ensurePathExists:path error:NULL];
}

- (BOOL)saveData:(NSData *)data toFile:(NSString *)filename atPath:(NSString *)path error:(NSError **)error {
    NSAssert([filename length] > 0, @"No file path given for saving data");
    if (!filename) {
        return NO;
    }
    [self ensurePathExists:path error:error];
    NSString *absolutePath = [path stringByAppendingPathComponent:filename];
    return [data writeToFile:absolutePath options:NSDataWritingAtomic error:error];
}

- (void)saveData:(NSData *)data path:(NSString *)path name:(NSString *)name {
    NSError *error = nil;
    [self saveData:data toFile:name atPath:path error:&error];
    NSAssert(error == nil, @"Error saving image to data store: %@", error);
}

- (BOOL)saveArray:(NSArray *)array path:(NSString *)path name:(NSString *)name error:(NSError **)error {
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:array format:NSPropertyListXMLFormat_v1_0 options:0 error:error];
    return [self saveData:data toFile:name atPath:path error:error];
}

- (void)saveArray:(NSArray *)array path:(NSString *)path name:(NSString *)name {
    [self saveArray:array path:path name:name error:NULL];
}

- (BOOL)saveDictionary:(NSDictionary *)dict path:(NSString *)path name:(NSString *)name error:(NSError **)error {
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:dict format:NSPropertyListXMLFormat_v1_0 options:0 error:error];
    return [self saveData:data toFile:name atPath:path error:error];
}

- (BOOL)saveString:(NSString *)string path:(NSString *)path name:(NSString *)name error:(NSError **)error {
    return [self saveData:[string dataUsingEncoding:NSUTF8StringEncoding] toFile:name atPath:path error:error];
}

- (BOOL)saveArticle:(MWKArticle *)article error:(NSError **)outError {
    if (article.url.wmf_title == nil) {
        return YES; // OK to fail without error
    }

    if (article.url.wmf_isNonStandardURL) {
        return YES; // OK to fail without error
    }
    [self addArticleToMemoryCache:article];
    NSString *path = [self pathForArticle:article];
    NSDictionary *export = [article dataExport];
    return [self saveDictionary:export path:path name:@"Article.plist" error:outError];
}

- (BOOL)saveSection:(MWKSection *)section error:(NSError **)outError {
    NSString *path = [self pathForSection:section];
    NSDictionary *export = [section dataExport];
    return [self saveDictionary:export path:path name:@"Section.plist" error:outError];
}

- (BOOL)saveSectionText:(NSString *)html section:(MWKSection *)section error:(NSError **)outError {
    NSString *path = [self pathForSection:section];
    return [self saveString:html path:path name:@"Section.html" error:outError];
}

- (BOOL)saveRecentSearchList:(MWKRecentSearchList *)list error:(NSError **)error {
    NSString *path = self.basePath;
    NSDictionary *export = @{@"entries": [list dataExport]};
    return [self saveDictionary:export path:path name:@"RecentSearches.plist" error:error];
}

- (void)saveImageInfo:(NSArray *)imageInfo forArticleURL:(NSURL *)url {
    NSArray *export = [imageInfo wmf_map:^id(MWKImageInfo *obj) {
        return [obj dataExport];
    }];

    [self saveArray:export
               path:[self pathForArticleURL:url]
               name:MWKImageInfoFilename];
}

- (void)addArticleToMemoryCache:(MWKArticle *)article forKey:(NSString *)key {
    if (!key || !article) {
        return;
    }
    @synchronized(self.articleCache) {
        [self.articleCache setObject:article forKey:key];
    }
}

- (void)addArticleToMemoryCache:(MWKArticle *)article {
    [self addArticleToMemoryCache:article forKey:article.url.wmf_databaseKey];
}

#pragma mark - load methods

- (MWKArticle *)memoryCachedArticleWithKey:(NSString *)key {
    return [self.articleCache objectForKey:key];
}

- (MWKArticle *)memoryCachedArticleWithURL:(NSURL *)url {
    return [self memoryCachedArticleWithKey:url.wmf_databaseKey];
}

- (nullable MWKArticle *)existingArticleWithURL:(NSURL *)url {
    NSString *key = [url wmf_databaseKey];
    MWKArticle *existingArticle =
        [self memoryCachedArticleWithKey:key] ?: [self articleFromDiskWithURL:url];
    if (existingArticle) {
        [self addArticleToMemoryCache:existingArticle forKey:key];
    }
    return existingArticle;
}

- (MWKArticle *)articleFromDiskWithURL:(NSURL *)url {
    NSString *path = [self pathForArticleURL:url];
    NSString *filePath = [path stringByAppendingPathComponent:@"Article.plist"];
    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:filePath];
    if (!dict) {
        return nil;
    }
    return [[MWKArticle alloc] initWithURL:url dataStore:self dict:dict];
}

- (MWKArticle *)articleWithURL:(NSURL *)url {
    MWKArticle *article = [self existingArticleWithURL:url];
    if (!article) {
        article = [[MWKArticle alloc] initWithURL:url dataStore:self];
    }
    return article;
}

- (MWKSection *)sectionWithId:(NSUInteger)sectionId article:(MWKArticle *)article {
    NSString *path = [self pathForSectionId:sectionId inArticleWithURL:article.url];
    NSString *filePath = [path stringByAppendingPathComponent:@"Section.plist"];
    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:filePath];
    return [[MWKSection alloc] initWithArticle:article dict:dict];
}

- (NSString *)sectionTextWithId:(NSUInteger)sectionId article:(MWKArticle *)article {
    NSString *path = [self pathForSectionId:sectionId inArticleWithURL:article.url];
    NSString *filePath = [path stringByAppendingPathComponent:@"Section.html"];

    NSError *err;
    NSString *html = [NSString stringWithContentsOfFile:filePath encoding:NSUTF8StringEncoding error:&err];
    if (err) {
        return nil;
    }

    return html;
}

- (BOOL)hasHTMLFileForSection:(MWKSection *)section {
    NSString *path = [self pathForSectionId:section.sectionId inArticleWithURL:section.article.url];
    NSString *filePath = [path stringByAppendingPathComponent:@"Section.html"];
    return [[NSFileManager defaultManager] fileExistsAtPath:filePath];
}

- (nullable MWKImage *)imageWithURL:(NSString *)url article:(MWKArticle *)article {
    if (url == nil) {
        return nil;
    }
    NSString *path = [self pathForImageURL:url forArticleURL:article.url];
    NSString *filePath = [path stringByAppendingPathComponent:@"Image.plist"];
    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:filePath];
    if (dict) {
        return [[MWKImage alloc] initWithArticle:article dict:dict];
    } else {
        // Not 100% sure if we should return an object here or not,
        // but it seems useful to do so.
        return [[MWKImage alloc] initWithArticle:article sourceURLString:url];
    }
}

- (NSArray *)historyListData {
    NSString *path = self.basePath;
    NSString *filePath = [path stringByAppendingPathComponent:@"History.plist"];
    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:filePath];
    return dict[@"entries"];
}

- (NSDictionary *)savedPageListData {
    NSString *path = self.basePath;
    NSString *filePath = [path stringByAppendingPathComponent:@"SavedPages.plist"];
    return [NSDictionary dictionaryWithContentsOfFile:filePath];
}

- (NSArray *)recentSearchListData {
    NSString *path = self.basePath;
    NSString *filePath = [path stringByAppendingPathComponent:@"RecentSearches.plist"];
    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:filePath];
    return dict[@"entries"];
}

- (NSArray<NSURL *> *)cacheRemovalListFromDisk {
    NSString *path = self.basePath;
    NSString *filePath = [path stringByAppendingPathComponent:@"TitlesToRemove.plist"];
    NSArray *URLStrings = [NSArray arrayWithContentsOfFile:filePath];
    NSArray<NSURL *> *urls = [URLStrings wmf_mapAndRejectNil:^NSURL *(id obj) {
        if (obj && [obj isKindOfClass:[NSString class]]) {
            return [NSURL URLWithString:obj];
        } else {
            return nil;
        }
    }];
    return urls;
}

- (BOOL)saveCacheRemovalListToDisk:(NSArray<NSURL *> *)cacheRemovalList error:(NSError **)error {
    NSArray *URLStrings = [cacheRemovalList wmf_map:^id(NSURL *obj) {
        return [obj absoluteString];
    }];
    return [self saveArray:URLStrings path:self.basePath name:@"TitlesToRemove.plist" error:error];
}

- (NSArray *)imageInfoForArticleWithURL:(NSURL *)url {
    MWKArticle *article = [self articleWithURL:url];
    NSArray *infos = [article imageInfosForGallery];
    if (infos) {
        return infos;
    }
    return [[NSArray arrayWithContentsOfFile:[self pathForImageInfoForArticleWithURL:url]] wmf_mapAndRejectNil:^MWKImageInfo *(id obj) {
        return [MWKImageInfo imageInfoWithExportedData:obj];
    }];
}

#pragma mark - helper methods

- (NSInteger)sitesDirectorySize {
    NSURL *sitesURL = [NSURL fileURLWithPath:[self pathForSites]];
    return (NSInteger)[[NSFileManager defaultManager] sizeOfDirectoryAt:sitesURL];
}

- (void)removeUnreferencedArticlesFromDiskCacheWithFailure:(WMFErrorHandler)failure success:(WMFSuccessHandler)success {
    [self performBackgroundCoreDataOperationOnATemporaryContext:^(NSManagedObjectContext *moc) {
        NSFetchRequest *articlesWithHTMLInTitlesFetchRequest = [WMFArticle fetchRequest];
        articlesWithHTMLInTitlesFetchRequest.predicate = [NSPredicate predicateWithFormat:@"displayTitle CONTAINS '<' || wikidataDescription CONTAINS '<'"];
        NSError *htmlFetchError = nil;
        NSArray *articlesWithHTMLInTheTitle = [moc executeFetchRequest:articlesWithHTMLInTitlesFetchRequest error:&htmlFetchError];
        if (htmlFetchError) {
            DDLogError(@"Error fetching articles with HTML in the title: %@", htmlFetchError);
        }

        for (WMFArticle *article in articlesWithHTMLInTheTitle) {
            article.wikidataDescription = [article.wikidataDescription wmf_stringByRemovingHTML];
        }

        NSError *saveError = nil;
        [moc save:&saveError];
        if (saveError) {
            DDLogError(@"Error saving after fixing articles with HTML in the title: %@", saveError);
        }

        NSFetchRequest *allValidArticleKeysFetchRequest = [WMFArticle fetchRequest];
        allValidArticleKeysFetchRequest.predicate = [NSPredicate predicateWithFormat:@"savedDate != NULL"];
        allValidArticleKeysFetchRequest.resultType = NSDictionaryResultType;
        allValidArticleKeysFetchRequest.propertiesToFetch = @[@"key"];

        NSError *fetchError = nil;
        NSArray *arrayOfAllValidArticleDictionaries = [moc executeFetchRequest:allValidArticleKeysFetchRequest error:&fetchError];

        if (fetchError) {
            failure(fetchError);
            return;
        }

        dispatch_block_t deleteEverythingAndSucceed = ^{
            dispatch_async(self.cacheRemovalQueue, ^{
                [[NSFileManager defaultManager] removeItemAtPath:[self pathForSites] error:nil];
                dispatch_async(dispatch_get_main_queue(), success);
            });
        };

        if (arrayOfAllValidArticleDictionaries.count == 0) {
            deleteEverythingAndSucceed();
            return;
        }

        NSMutableSet *allValidArticleKeys = [NSMutableSet setWithCapacity:arrayOfAllValidArticleDictionaries.count];
        for (NSDictionary *article in arrayOfAllValidArticleDictionaries) {
            NSString *key = article[@"key"];
            if (!key) {
                continue;
            }
            [allValidArticleKeys addObject:key];
        }

        if (allValidArticleKeys.count == 0) {
            deleteEverythingAndSucceed();
            return;
        }

        dispatch_async(self.cacheRemovalQueue, ^{
            NSMutableArray<NSURL *> *articleURLsToRemove = [NSMutableArray arrayWithCapacity:10];
            [self iterateOverArticleURLs:^(NSURL *articleURL) {
                NSString *key = articleURL.wmf_databaseKey;
                if (!key) {
                    return;
                }
                if ([allValidArticleKeys containsObject:key]) {
                    return;
                }

                [articleURLsToRemove addObject:articleURL];
            }];
            [self removeArticlesWithURLsFromCache:articleURLsToRemove];
            dispatch_async(dispatch_get_main_queue(), success);
        });
    }];
}

- (void)iterateOverArticleURLs:(void (^)(NSURL *))block {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *articlePath = [self pathForSites];
    for (NSString *path in [fm enumeratorAtPath:articlePath]) {
        NSArray *components = [path pathComponents];

        //HAX: We make assumptions about the length of paths below.
        //This is due to our title handling assumptions
        WMF_TECH_DEBT_TODO(We should remove this when we move to a DB)
        if ([components count] < 5) {
            continue;
        }

        NSUInteger count = [components count];
        NSString *filename = components[count - 1];
        if ([filename isEqualToString:@"Article.plist"]) {
            NSString *dirname = components[count - 2];
            NSString *titleText = [self stringWithSafeFilename:dirname];

            NSString *language = components[count - 4];
            NSString *domain = components[count - 5];

            NSURL *url = [NSURL wmf_URLWithDomain:domain language:language title:titleText fragment:nil];
            block(url);
        }
    }
}

- (void)startCacheRemoval:(dispatch_block_t)completion {
    dispatch_async(self.cacheRemovalQueue, ^{
        if (!self.isCacheRemovalActive) {
            self.cacheRemovalActive = true;
            self.cacheRemovalCompletion = completion;
            [self removeNextArticleFromCacheRemovalList];
        } else {
            dispatch_block_t existingCompletion = self.cacheRemovalCompletion;
            self.cacheRemovalCompletion = ^{
                if (existingCompletion) {
                    existingCompletion();
                }
                if (completion) {
                    completion();
                }
            };
        }
    });
}

- (void)_stopCacheRemoval {
    dispatch_block_t completion = self.cacheRemovalCompletion;
    if (completion) {
        completion();
    }
    self.cacheRemovalActive = false;
    self.cacheRemovalCompletion = nil;
}

- (void)stopCacheRemoval {
    dispatch_sync(self.cacheRemovalQueue, ^{
        [self _stopCacheRemoval];
    });
}

- (void)removeNextArticleFromCacheRemovalList {
    if (!self.cacheRemovalActive) {
        return;
    }
    NSMutableArray<NSURL *> *urlsOfArticlesToRemove = [[self cacheRemovalListFromDisk] mutableCopy];
    if (urlsOfArticlesToRemove.count == 0) {
        [self _stopCacheRemoval];
        return;
    }
    NSURL *urlToRemove = urlsOfArticlesToRemove[0];
    [self removeArticleWithURL:urlToRemove
        fromDiskWithCompletion:^{
            dispatch_async(self.cacheRemovalQueue, ^{
                [urlsOfArticlesToRemove removeObjectAtIndex:0];
                NSError *error = nil;
                if ([self saveCacheRemovalListToDisk:urlsOfArticlesToRemove error:&error]) {
                    dispatch_async(self.cacheRemovalQueue, ^{
                        [self removeNextArticleFromCacheRemovalList];
                    });
                } else {
                    DDLogError(@"Error saving cache removal list: %@", error);
                }
            });
        }];
}

- (void)removeArticlesWithURLsFromCache:(NSArray<NSURL *> *)urlsToRemove {
    if (urlsToRemove.count == 0) {
        return;
    }
    dispatch_async(self.cacheRemovalQueue, ^{
        NSMutableArray<NSURL *> *allURLsToRemove = [[self cacheRemovalListFromDisk] mutableCopy];
        if (allURLsToRemove == nil) {
            allURLsToRemove = [NSMutableArray arrayWithArray:urlsToRemove];
        } else {
            [allURLsToRemove addObjectsFromArray:urlsToRemove];
        }
        NSError *error = nil;
        if (![self saveCacheRemovalListToDisk:allURLsToRemove error:&error]) {
            DDLogError(@"Error saving cache removal list to disk: %@", error);
        }
    });
}

- (NSArray *)legacyImageURLsForArticle:(MWKArticle *)article {
    NSString *path = [self pathForArticle:article];
    NSDictionary *legacyImageDictionary = [NSDictionary dictionaryWithContentsOfFile:[path stringByAppendingPathComponent:@"Images.plist"]];
    if ([legacyImageDictionary isKindOfClass:[NSDictionary class]]) {
        NSArray *legacyImageURLStrings = [legacyImageDictionary objectForKey:@"entries"];
        if ([legacyImageURLStrings isKindOfClass:[NSArray class]]) {
            NSArray *legacyImageURLs = [legacyImageURLStrings wmf_mapAndRejectNil:^id(id obj) {
                if ([obj isKindOfClass:[NSString class]]) {
                    return [NSURL URLWithString:obj];
                } else {
                    return nil;
                }
            }];
            return legacyImageURLs;
        }
    }
    return @[];
}

#pragma mark - Deletion

- (NSError *)removeFolderAtBasePath {
    NSError *err;
    [[NSFileManager defaultManager] removeItemAtPath:self.basePath error:&err];
    return err;
}

- (void)removeArticleWithURL:(NSURL *)articleURL fromDiskWithCompletion:(dispatch_block_t)completion {
    if (!articleURL) {
        if (completion) {
            completion();
        }
        return;
    }
    dispatch_async(self.cacheRemovalQueue, ^{
        NSString *path = [self pathForArticleURL:articleURL];
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
        dispatch_block_t combinedCompletion = ^{
            dispatch_async(dispatch_get_main_queue(), ^{
                WMFArticle *article = [self fetchArticleWithURL:articleURL];
                article.isDownloaded = NO;
                NSError *saveError = nil;
                if (![self save:&saveError]) {
                    DDLogError(@"Error saving after cache removal: %@", saveError);
                }
                if (completion) {
                    completion();
                }
            });
        };
        NSString *groupKey = articleURL.wmf_databaseKey;
        if (groupKey) {
            [[WMFImageController sharedInstance] removePermanentlyCachedImagesWithGroupKey:groupKey completion:combinedCompletion];
        } else {
            combinedCompletion();
        }
    });
}

#pragma mark - Cache

- (void)prefetchArticles {
    NSFetchRequest *request = [WMFArticle fetchRequest];
    request.fetchLimit = 1000;
    NSManagedObjectContext *moc = self.viewContext;
    NSArray<WMFArticle *> *prefetchedArticles = [moc executeFetchRequest:request error:nil];
    for (WMFArticle *article in prefetchedArticles) {
        NSString *key = article.key;
        if (!key) {
            continue;
        }
        [self.articlePreviewCache setObject:article forKey:key];
    }
}

- (void)clearMemoryCache {
    @synchronized(self.articleCache) {
        [self.articleCache removeAllObjects];
    }
    [self.articlePreviewCache removeAllObjects];
}

- (void)clearCachesForUnsavedArticles {
    [[WMFImageController sharedInstance] deleteTemporaryCache];
    //[[WMFImageController sharedInstance] removeLegacyCache];
    [self
        removeUnreferencedArticlesFromDiskCacheWithFailure:^(NSError *_Nonnull error) {
            DDLogError(@"Error removing unreferenced articles: %@", error);
        }
        success:^{
            DDLogDebug(@"Successfully removed unreferenced articles");
        }];
}

#pragma mark - Remote Configuration

- (void)updateLocalConfigurationFromRemoteConfigurationWithCompletion:(nullable void (^)(NSError *nullable))completion {
    void (^combinedCompletion)(NSError *) = ^(NSError *error) {
        if (completion) {
            completion(error);
        }
    };

    __block NSError *updateError = nil;
    WMFTaskGroup *taskGroup = [[WMFTaskGroup alloc] init];

    // Site info
    NSURLComponents *components = [[WMFConfiguration current] mediaWikiAPIURLComponentsForHost:@"meta.wikimedia.org" withQueryParameters:@{@"action": @"query", @"format": @"json", @"meta": @"siteinfo"}];
    [taskGroup enter];
    [[WMFSession shared] getJSONDictionaryFromURL:components.URL
                                      ignoreCache:YES
                                completionHandler:^(NSDictionary<NSString *, id> *_Nullable siteInfo, NSURLResponse *_Nullable response, NSError *_Nullable error) {
                                    dispatch_async(dispatch_get_main_queue(), ^{
                                        if (error) {
                                            updateError = error;
                                            [taskGroup leave];
                                            return;
                                        }
                                        NSDictionary *generalProps = [siteInfo valueForKeyPath:@"query.general"];
                                        NSDictionary *readingListsConfig = generalProps[@"readinglists-config"];
                                        if (self.isLocalConfigUpdateAllowed) {
                                            [self updateReadingListsLimits:readingListsConfig];
                                            self.remoteConfigsThatFailedUpdate &= ~RemoteConfigOptionReadingLists;
                                        } else {
                                            self.remoteConfigsThatFailedUpdate |= RemoteConfigOptionReadingLists;
                                        }
                                        [taskGroup leave];
                                    });
                                }];
    // Remote config
    NSURL *remoteConfigURL = [NSURL URLWithString:@"https://meta.wikimedia.org/static/current/extensions/MobileApp/config/ios.json"];
    [taskGroup enter];
    [[WMFSession shared] getJSONDictionaryFromURL:remoteConfigURL
                                      ignoreCache:YES
                                completionHandler:^(NSDictionary<NSString *, id> *_Nullable remoteConfigurationDictionary, NSURLResponse *_Nullable response, NSError *_Nullable error) {
                                    dispatch_async(dispatch_get_main_queue(), ^{
                                        if (error) {
                                            updateError = error;
                                            [taskGroup leave];
                                            return;
                                        }
                                        if (self.isLocalConfigUpdateAllowed) {
                                            [self updateLocalConfigurationFromRemoteConfiguration:remoteConfigurationDictionary];
                                            self.remoteConfigsThatFailedUpdate &= ~RemoteConfigOptionGeneric;
                                        } else {
                                            self.remoteConfigsThatFailedUpdate |= RemoteConfigOptionGeneric;
                                        }
                                        [taskGroup leave];
                                    });
                                }];

    [taskGroup waitInBackgroundWithCompletion:^{
        combinedCompletion(updateError);
    }];
}

- (void)updateLocalConfigurationFromRemoteConfiguration:(NSDictionary *)remoteConfigurationDictionary {
    NSNumber *disableReadingListSyncNumber = remoteConfigurationDictionary[@"disableReadingListSync"];
    BOOL shouldDisableReadingListSync = [disableReadingListSyncNumber boolValue];
    self.readingListsController.isSyncRemotelyEnabled = !shouldDisableReadingListSync;
}

- (void)updateReadingListsLimits:(NSDictionary *)readingListsConfig {
    NSNumber *maxEntriesPerList = readingListsConfig[@"maxEntriesPerList"];
    NSNumber *maxListsPerUser = readingListsConfig[@"maxListsPerUser"];
    self.readingListsController.maxEntriesPerList = maxEntriesPerList;
    self.readingListsController.maxListsPerUser = [maxListsPerUser intValue];
}

#pragma mark - Core Data

#if DEBUG
- (NSManagedObjectContext *)viewContext {
    NSAssert([NSThread isMainThread], @"View context must only be accessed on the main thread");
    return _viewContext;
}
#endif

- (BOOL)save:(NSError **)error {
    if (![self.viewContext hasChanges]) {
        return YES;
    }
    return [self.viewContext save:error];
}

- (nullable WMFArticle *)fetchArticleWithURL:(NSURL *)URL inManagedObjectContext:(nonnull NSManagedObjectContext *)moc {
    return [self fetchArticleWithKey:[URL wmf_databaseKey] inManagedObjectContext:moc];
}

- (nullable WMFArticle *)fetchArticleWithKey:(NSString *)key inManagedObjectContext:(nonnull NSManagedObjectContext *)moc {
    WMFArticle *article = nil;
    if (moc == _viewContext) { // use ivar to avoid main thread check
        article = [self.articlePreviewCache objectForKey:key];
        if (article) {
            return article;
        }
    }
    article = [moc fetchArticleWithKey:key];
    if (article && moc == _viewContext) { // use ivar to avoid main thread check
        [self.articlePreviewCache setObject:article forKey:key];
    }
    return article;
}

- (nullable WMFArticle *)fetchArticleWithWikidataID:(NSString *)wikidataID {
    return [_viewContext fetchArticleWithWikidataID:wikidataID];
}

- (nullable WMFArticle *)fetchOrCreateArticleWithURL:(NSURL *)URL inManagedObjectContext:(NSManagedObjectContext *)moc {
    NSString *language = URL.wmf_language;
    NSString *title = URL.wmf_title;
    NSString *key = [URL wmf_databaseKey];
    if (!language || !title || !key) {
        return nil;
    }
    WMFArticle *article = [self fetchArticleWithKey:key inManagedObjectContext:moc];
    if (!article) {
        article = [moc createArticleWithKey:key];
        article.displayTitleHTML = article.displayTitle;
        if (moc == self.viewContext) {
            [self.articlePreviewCache setObject:article forKey:key];
        }
    }
    return article;
}

- (nullable WMFArticle *)fetchArticleWithURL:(NSURL *)URL {
    return [self fetchArticleWithKey:[URL wmf_databaseKey]];
}

- (nullable WMFArticle *)fetchArticleWithKey:(NSString *)key {
    WMFAssertMainThread(@"Article fetch must be performed on the main thread.");
    return [self fetchArticleWithKey:key inManagedObjectContext:self.viewContext];
}

- (nullable WMFArticle *)fetchOrCreateArticleWithURL:(NSURL *)URL {
    WMFAssertMainThread(@"Article fetch must be performed on the main thread.");
    return [self fetchOrCreateArticleWithURL:URL inManagedObjectContext:self.viewContext];
}

- (void)setIsExcludedFromFeed:(BOOL)isExcludedFromFeed withArticleURL:(NSURL *)articleURL inManagedObjectContext:(NSManagedObjectContext *)moc {
    NSParameterAssert(articleURL);
    if ([articleURL wmf_isNonStandardURL]) {
        return;
    }
    if ([articleURL.wmf_title length] == 0) {
        return;
    }

    WMFArticle *article = [self fetchOrCreateArticleWithURL:articleURL inManagedObjectContext:moc];
    article.isExcludedFromFeed = isExcludedFromFeed;
    [self save:nil];
}

- (BOOL)isArticleWithURLExcludedFromFeed:(NSURL *)articleURL inManagedObjectContext:(NSManagedObjectContext *)moc {
    WMFArticle *article = [self fetchArticleWithURL:articleURL inManagedObjectContext:moc];
    if (!article) {
        return NO;
    }
    return article.isExcludedFromFeed;
}

- (void)setIsExcludedFromFeed:(BOOL)isExcludedFromFeed withArticleURL:(NSURL *)articleURL {
    [self setIsExcludedFromFeed:isExcludedFromFeed withArticleURL:articleURL inManagedObjectContext:self.viewContext];
}

- (BOOL)isArticleWithURLExcludedFromFeed:(NSURL *)articleURL {
    return [self isArticleWithURLExcludedFromFeed:articleURL inManagedObjectContext:self.viewContext];
}

@end
