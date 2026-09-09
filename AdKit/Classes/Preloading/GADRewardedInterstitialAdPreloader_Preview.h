//
//  GADRewardedInterstitialAdPreloader_Preview.h
//  Google Mobile Ads SDK
//
//  Copyright © 2025 Google Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <GoogleMobileAds/GADMobileAds.h>
#import <GoogleMobileAds/GADRewardedInterstitialAd.h>
#import "GADPreloadDelegate_Preview.h"

@class GADRewardedInterstitialAd;
@class GADPreloadConfigurationV2;

NS_SWIFT_NAME(RewardedInterstitialAdPreloader)
@interface GADRewardedInterstitialAdPreloader : NSObject

/// Returns the shared GADRewardedInterstitialAdPreloader instance.
@property(class, nonatomic, readonly, nonnull)
    GADRewardedInterstitialAdPreloader *sharedInstance NS_SWIFT_NAME(shared);

/// Starts preloading rewarded interstitial ads from the configuration for the given preload ID.
/// If a delegate is provided, ad events will be forwarded to the delegate.
/// Returns false if preload failed to start. Check console for error log.
- (BOOL)preloadForPreloadID:(nonnull NSString *)preloadID
              configuration:(nonnull GADPreloadConfigurationV2 *)configuration
                   delegate:(nullable id<GADPreloadDelegate>)delegate
    NS_SWIFT_NAME(preload(for:configuration:delegate:));

/// Returns whether a rewarded interstitial ad is preloaded for the given preload ID.
- (BOOL)isAdAvailableWithPreloadID:(nonnull NSString *)preloadID
    NS_SWIFT_NAME(isAdAvailable(with:));

/// Returns a preloaded rewarded interstitial ad for the given preload ID. Returns nil if an ad is
/// not available.
- (nullable GADRewardedInterstitialAd *)adWithPreloadID:(nonnull NSString *)preloadID
    NS_SWIFT_NAME(ad(with:));

/// Returns the corresponding configuration for the given preload ID.
- (nullable GADPreloadConfigurationV2 *)configurationWithPreloadID:(nonnull NSString *)preloadID
    NS_SWIFT_NAME(configuration(with:));

/// Returns a map of preload IDs to their corresponding configurations.
- (nonnull NSDictionary<NSString *, GADPreloadConfigurationV2 *> *)configurations;

/// Returns the number of preloaded rewarded interstitial ads available for the given preload ID.
- (NSUInteger)numberOfAdsAvailableWithPreloadID:(nonnull NSString *)preloadID
    NS_SWIFT_NAME(numberOfAdsAvailable(with:));

/// Stops preloading rewarded interstitial ads for the given preload ID.
/// Removes preloaded rewarded interstitial ads for the given preload ID.
- (void)stopPreloadingAndRemoveAdsForPreloadID:(nonnull NSString *)preloadID
    NS_SWIFT_NAME(stopPreloadingAndRemoveAds(for:));

/// Stops preloading all rewarded interstitial ads.
/// Removes all preloaded rewarded interstitial ads.
- (void)stopPreloadingAndRemoveAllAds;

@end