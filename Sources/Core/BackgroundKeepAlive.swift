// BackgroundKeepAlive.swift
// Не даёт системе усыпить приложение, пока в островке висит задача.
//
// ЗАЧЕМ ЭТО ВООБЩЕ НУЖНО. Островок рисует не приложение, а система, и
// двигать карточку можно только двумя путями: из работающего приложения
// через ActivityKit, либо пушем через APNs. Второй путь требует платного
// аккаунта разработчика (проверено 10.09.2026: с `pushType: .token`
// ActivityKit отвечает `PermissionsError Code=3`). Первый упирается в то,
// что свёрнутое приложение не выполняется вовсе.
//
// Отсюда обход: пока карточка висит, приложение объявляет себя работающим
// с геопозицией и остаётся живым — держит связь с сервером и двигает
// островок само.
//
// ЧЕСТНАЯ ЦЕНА. Батарея садится быстрее, в статусной строке индикатор.
// Поэтому фон живёт РОВНО пока висит островок: включается вместе с ним,
// гаснет вместе с ним. Отдельного переключателя нет сознательно — владелец
// 10.09.2026: «я же всё равно сам нажимаю, какую задачу показать; она
// прошла, я выключил. Одну задачу раз в сто лет».
//
// Точность выкручена в самую грубую, а порог смещения — в километры: сама
// геопозиция нам не нужна ни на что, нужен только сам факт работающего
// фона.

import CoreLocation
import Foundation

final class BackgroundKeepAlive: NSObject, CLLocationManagerDelegate {
    static let shared = BackgroundKeepAlive()

    private let manager = CLLocationManager()
    private var isRunning = false

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        manager.distanceFilter = 3000
        manager.pausesLocationUpdatesAutomatically = false
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true

        // Разрешение спрашиваем ровно в этот момент, а не при запуске
        // приложения: человек должен понимать, за что его спрашивают.
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
        NSLog("[KeepAlive] фон включён — островок будет живым")
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        NSLog("[KeepAlive] фон выключен")
    }

    /// Координаты нам не нужны — метод обязателен, но делать в нём нечего.
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {}

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        NSLog("[KeepAlive] геопозиция отказала: %@", error.localizedDescription)
    }
}
