#import <Foundation/Foundation.h>

#import "MWKDataObject.h"

@class MWKArticle;

@interface MWKProtectionStatus : MWKDataObject <NSCopying>

- (instancetype)initWithData:(id)data;

- (NSArray *)protectedActions;
- (NSArray *)allowedGroupsForAction:(NSString *)action;

@end
