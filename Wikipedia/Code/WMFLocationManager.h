#import <Foundation/Foundation.h>
@import CoreLocation;

@class WMFLocationSearchResults;
@protocol WMFLocationManagerDelegate;

NS_ASSUME_NONNULL_BEGIN

@interface WMFLocationManager : NSObject

@property(nonatomic, strong, readonly) CLLocationManager *locationManager;

@property(nonatomic, weak, nullable) id<WMFLocationManagerDelegate> delegate;

@property(nonatomic, strong, readonly) CLLocation *location;

@property(nonatomic, strong, readonly) CLHeading *heading;

+ (instancetype)fineLocationManager;

+ (instancetype)coarseLocationManager;

/**
 *  Use one of the above factory methods instead.
 *
 *  @see fineLocationManager
 *  @see coarseLocationManager
 */
- (instancetype)init NS_UNAVAILABLE;

/**
 *  Start monitoring location and heading updates.
 *
 *  @note
 *  This method is idempotent. To force new values to be sent, use @c restartLocationMonitoring.
 */
- (void)startMonitoringLocation;

/**
 *  Stop monitoring location and heading updates.
 */
- (void)stopMonitoringLocation;

/**
 *  Restart location monitoring, forcing the receiver to emit new location and heading values (if possible).
 */
- (void)restartLocationMonitoring;

+ (BOOL)isAuthorized;

+ (BOOL)isDeniedOrDisabled;

- (AnyPromise *)reverseGeocodeLocation:(CLLocation *)location;

@end

@protocol WMFLocationManagerDelegate <NSObject>

- (void)nearbyController:(WMFLocationManager *)controller didUpdateLocation:(CLLocation *)location;

- (void)nearbyController:(WMFLocationManager *)controller didUpdateHeading:(CLHeading *)heading;

- (void)nearbyController:(WMFLocationManager *)controller didReceiveError:(NSError *)error;

@optional

- (void)nearbyController:(WMFLocationManager *)controller didChangeEnabledState:(BOOL)enabled;

@end

NS_ASSUME_NONNULL_END