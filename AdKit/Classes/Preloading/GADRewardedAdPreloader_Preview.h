//
//  GADRewardedAdPreloader_Preview.h
//  Google Mobile Ads SDK
//
//  Copyright © 2025 Google Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <GoogleMobileAds/GADMobileAds.h>
#import <GoogleMobileAds/GADRewardedAd.h>
#import "GADPreloadDelegate_Preview.h"

@class GADRewardedAd;
@class GADPreloadConfigurationV2;

NS_SWIFT_NAME(RewardedAdPreloader)
@interface GADRewardedAdPreloader : NSObject

/// Returns the shared GADRewardedAdPreloader instance.
@property(class, nonatomic, readonly, nonnull)
    GADRewardedAdPreloader *sharedInstance NS_SWIFT_NAME(shared);

/// Starts preloading rewarded ads from the configuration for the given preload ID.
/// If a delegate is provided, ad events will be forwarded to the delegate.
/// Returns false if preload failed to start. Check console for error log.
- (BOOL)preloadForPreloadID:(nonnull NSString *)preloadID
              configuration:(nonnull GADPreloadConfigurationV2 *)configuration
                   delegate:(nullable id<GADPreloadDelegate>)delegate
    NS_SWIFT_NAME(preload(for:configuration:delegate:));

/// Returns whether a rewarded ad is preloaded for the given preload ID.
- (BOOL)isAdAvailableWithPreloadID:(nonnull NSString *)preloadID
    NS_SWIFT_NAME(isAdAvailable(with:));

/// Returns a preloaded rewarded ad for the given preload ID. Returns nil if an ad is not available.
- (nullable GADRewardedAd *)adWithPreloadID:(nonnull NSString *)preloadID NS_SWIFT_NAME(ad(with:));

/// Returns the corresponding configuration for the given preload ID.
- (nullable GADPreloadConfigurationV2 *)configurationWithPreloadID:(nonnull NSString *)preloadID
    NS_SWIFT_NAME(configuration(with:));

/// Returns a map of preload IDs to their corresponding configurations.
- (nonnull NSDictionary<NSString *, GADPreloadConfigurationV2 *> *)configurations;

/// Returns the number of preloaded rewarded ads available for the given preload ID.
- (NSUInteger)numberOfAdsAvailableWithPreloadID:(nonnull NSString *)preloadID
    NS_SWIFT_NAME(numberOfAdsAvailable(with:));

/// Stops preloading rewarded ads for the given preload ID.
/// Removes preloaded rewarded ads for the given preload ID.
- (void)stopPreloadingAndRemoveAdsForPreloadID:(nonnull NSString *)preloadID
    NS_SWIFT_NAME(stopPreloadingAndRemoveAds(for:));

/// Stops preloading all interstitial ads.
/// Removes all preloaded interstitial ads.
- (void)stopPreloadingAndRemoveAllAds;

@end