#import <Mantle/Mantle.h>

@class MWKSavedPageList, MWKHistoryList, WMFExploreSection, WMFRelatedSectionBlackList;

@protocol WMFExploreSectionSchemaDelegate;

NS_ASSUME_NONNULL_BEGIN

@interface WMFExploreSectionSchema : MTLModel

/**
 *  Creates a schema by loading a persisted one from disk or
 *  if none is available, will create one
 *
 *  @param site site for populating sections
 *  @param savedPages Saved pages for populating sections
 *  @param history    History for populating sections
 *  @param blackList  Blacklist for removing realated sections
 *
 *  @return The schema
 */
+ (instancetype)schemaWithSiteURL:(NSURL *)siteURL
                       savedPages:(MWKSavedPageList *)savedPages
                          history:(MWKHistoryList *)history
                        blackList:(WMFRelatedSectionBlackList *)blackList;

@property(nonatomic, strong, readonly) NSURL *siteURL;
@property(nonatomic, strong, readonly) MWKSavedPageList *savedPages;
@property(nonatomic, strong, readonly) MWKHistoryList *historyPages;
@property(nonatomic, strong, readonly) WMFRelatedSectionBlackList *blackList;
@property(nonatomic, strong, readonly) NSURL *fileURL;

@property(nonatomic, strong, readonly, nullable) NSDate *lastUpdatedAt;

@property(nonatomic, weak, readwrite) id<WMFExploreSectionSchemaDelegate> delegate;

/**
 *  An array of the sections to be displayed on the home screen
 */
@property(nonatomic, strong, readonly) NSArray<WMFExploreSection *> *sections;

- (void)updateSiteURL:(NSURL *)siteURL;

/**
 *  Update the schema based on the internal business rules
 *  When the update is complete the delegate will be notified
 *  Note that some sections (like Nearby) can take while to update.
 */
- (void)update;

/**
 *  The same as above, but always performs an update even if
 *  the business rules would dicatate otherwise.
 *  This is most useful for user inititiated updates
 *
 *  @param force If YES force an update
 */
- (BOOL)update:(BOOL)force;

@end

@protocol WMFExploreSectionSchemaDelegate <NSObject>

- (void)sectionSchemaDidUpdateSections:(WMFExploreSectionSchema *)schema;
- (void)sectionSchema:(WMFExploreSectionSchema *)schema didRemoveSection:(WMFExploreSection *)section atIndex:(NSUInteger)index;

@end

NS_ASSUME_NONNULL_END