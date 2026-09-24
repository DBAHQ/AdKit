Pod::Spec.new do |s|
  s.name             = 'AdKit'
  s.version          = '0.1.4'
  s.summary          = 'Общий рекламный слой для приложений DBAHQ.'
  s.description      = <<-DESC
                       Медиация, загрузка и показ рекламы (AppOpen, interstitial, rewarded,
                       banner, native), CPM-бэкофф, preload и инициализация рекламных SDK.
                       Всё прикладное — плейсменты, Remote Config, аналитика, хранилище,
                       оформление — приложение передаёт через протоколы из AdKit/Classes/API.
                       DESC
  s.homepage         = 'https://github.com/DBAHQ/AdKit'
  s.license          = { :type => 'Proprietary', :file => 'LICENSE' }
  s.author           = { 'ak' => 'ak@ironsum.com' }
  s.source           = { :git => 'git@github.com:DBAHQ/AdKit.git', :tag => s.version.to_s }

  # Часть рекламных SDK (Yandex, Vungle, Mintegral, UserMessagingPlatform) поставляется
  # статическими xcframework. Динамический фреймворк их прилинковать не может, поэтому
  # AdKit собирается статически. Заодно это совпадает с линковкой в GoTrading/Gocrypto.
  s.static_framework      = true
  s.ios.deployment_target = '15.0'
  s.swift_version         = '5.0'
  # .h — вендоренные Google превью-заголовки для preload-API: они лежат внутри
  # GoogleMobileAds.framework, но не входят в его modulemap, поэтому в Swift без них
  # не видно PreloadDelegate/PreloadConfigurationV2/InterstitialAdPreloader.
  s.source_files          = 'AdKit/Classes/**/*.{swift,h}'

  # Рекламные SDK, которые импортирует код пакета. Версии намеренно не пиннятся:
  # их выбирает Podfile приложения, чтобы не разъехаться с остальными подами.
  s.dependency 'Google-Mobile-Ads-SDK'
  s.dependency 'GoogleUserMessagingPlatform'
  s.dependency 'AppLovinSDK'
  s.dependency 'YandexMobileAds'
  s.dependency 'GoogleMobileAdsMediationMintegral'
  s.dependency 'VungleAds'
  s.dependency 'FBAudienceNetwork'
  s.dependency 'Adjust/AdjustGoogleOdm'
end
