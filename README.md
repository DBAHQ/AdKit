# AdKit

Общий рекламный слой для приложений DBAHQ (TradingGuru, GoTrading, Gocrypto, Cryptoguru/ironsum, TradingClub).

Пока подключается только к TradingGuru и только локально:

```ruby
pod 'AdKit', :path => '../../AdKit'
```

Всё прикладное приложение отдаёт через протоколы из `AdKit/Classes/API`:
плейсменты, Remote Config, настройки с бекенда, аналитику, хранилище,
оформление и хост-окружение.
