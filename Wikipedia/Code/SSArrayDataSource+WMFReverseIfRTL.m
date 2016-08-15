#import "SSArrayDataSource+WMFReverseIfRTL.h"
#import "NSProcessInfo+WMFOperatingSystemVersionChecks.h"
#import "NSArray+WMFLayoutDirectionUtilities.h"

@implementation SSArrayDataSource (WMFReverseIfRTL)

- (instancetype)initWithItemsAndReverseIfNeeded:(NSArray *)items {
    if ([[NSProcessInfo processInfo] wmf_isOperatingSystemVersionLessThan9_0_0]) {
        items = [items wmf_reverseArrayIfApplicationIsRTL];
    }
    return [self initWithItems:items];
}

@end
