import Foundation
import SwiftUI

/// Закрытый словарь причин ожидания V2 (`CauseCode`). Контракт:
/// `docs/server/coordination-resolver.md`, документ `a8bfa7ea-…` в проекте
/// TaskFlow — NewTodoist. UI iOS обязан показать текст для **всех 20
/// значений** — отсутствие видимого представления считается дефектом.
///
/// Смысл для владельца и кнопка в Action bar зафиксированы UX-документом
/// (`docs/ios/coordination-resolver-view.md`). Тексты короткие, чтобы
/// Reason strip не разрастался: 3–6 слов в строке.
///
/// 14 значений `ActionCode` живут рядом: `CoordinationAction` ниже.
public enum CoordinationCause: String, CaseIterable, Sendable {
    case readyToStart = "ready_to_start"
    case waitingPredecessor = "waiting_predecessor"
    case blockedDependency = "blocked_dependency"
    case waitingOwner = "waiting_owner"
    case waitingHuman = "waiting_human"
    case waitingTransient = "waiting_transient"
    case activeRun = "active_run"
    case durableQueuedWake = "durable_queued_wake"
    case recoveryPending = "recovery_pending"
    case stalledManualReview = "stalled_manual_review"
    case providerLimit = "provider_limit"
    case permissionOrOwner = "permission_or_owner"
    case missingConfig = "missing_config"
    case contextOverflow = "context_overflow"
    case stepStalled = "step_stalled"
    case review = "review"
    case branchRework = "branch_rework"
    case awaitingFinalReview = "awaiting_final_review"
    case completedPendingReview = "completed_pending_review"
    case unknown = "unknown"

    /// Короткий заголовок для Reason strip (RU).
    public var title: String {
        switch self {
        case .readyToStart: return "Можно запустить"
        case .waitingPredecessor: return "Ждём шаг"
        case .blockedDependency: return "Ждём зависимость"
        case .waitingOwner: return "Нужно ваше решение"
        case .waitingHuman: return "Нет подходящей роли"
        case .waitingTransient: return "Временная пауза"
        case .activeRun: return "Идёт работа"
        case .durableQueuedWake: return "В очереди"
        case .recoveryPending: return "Восстановление"
        case .stalledManualReview: return "Зависло"
        case .providerLimit: return "Лимит провайдера"
        case .permissionOrOwner: return "Нет доступа"
        case .missingConfig: return "Не настроено"
        case .contextOverflow: return "Контекст переполнен"
        case .stepStalled: return "Шаг остановился"
        case .review: return "На проверке"
        case .branchRework: return "Доработка"
        case .awaitingFinalReview: return "Финальная проверка"
        case .completedPendingReview: return "Готово, ждёт приёмки"
        case .unknown: return "Статус неизвестен"
        }
    }

    /// Подсказка для Details sheet (RU). Может быть длиннее title.
    public var hint: String {
        switch self {
        case .readyToStart:
            return "Шаг свободен, откройте цепочку или подтвердите"
        case .waitingPredecessor:
            return "Предшественник ещё не завершён"
        case .blockedDependency:
            return "Зависимость карточки не выполнена — поднимется автоматически"
        case .waitingOwner:
            return "Нужно ваше решение по этому шагу"
        case .waitingHuman:
            return "У текущей роли нет нужной компетенции"
        case .waitingTransient:
            return "Сервер снимет паузу сам"
        case .activeRun:
            return "Исполнитель активен, ждите"
        case .durableQueuedWake:
            return "Задание в очереди, worker подхватит"
        case .recoveryPending:
            return "Сервер поднимет шаг после рестарта"
        case .stalledManualReview:
            return "Сервер дошёл до лимита автоперезапусков"
        case .providerLimit:
            return "Цепочка моделей исчерпана"
        case .permissionOrOwner:
            return "Проверьте ключ или права"
        case .missingConfig:
            return "Не настроена маршрутизация для роли"
        case .contextOverflow:
            return "Шаг слишком длинный"
        case .stepStalled:
            return "Запуск завершился без сдачи"
        case .review:
            return "Ждём вердикт проверяющего"
        case .branchRework:
            return "После вердикта открыты rework-узлы"
        case .awaitingFinalReview:
            return "Все доработки сданы"
        case .completedPendingReview:
            return "План сдан, авто-проверка отключена"
        case .unknown:
            return "Сервер не смог объяснить причину"
        }
    }

    /// Кнопка в Action bar (`ActionCode`). Если nil — кнопки нет, ждём
    /// автоматического развития.
    public var actionCode: CoordinationAction? {
        switch self {
        case .readyToStart: return .start
        case .waitingPredecessor: return nil  // ждём автоматически
        case .blockedDependency: return nil
        case .waitingOwner: return .askOwner
        case .waitingHuman: return .switchRole
        case .waitingTransient: return nil
        case .activeRun: return nil
        case .durableQueuedWake: return nil
        case .recoveryPending: return nil
        case .stalledManualReview: return .replaceAttempt
        case .providerLimit: return .switchProvider
        case .permissionOrOwner: return .askOwner
        case .missingConfig: return .fixConfig
        case .contextOverflow: return .retryWithDelay
        case .stepStalled: return .replaceAttempt
        case .review: return nil
        case .branchRework: return .pickUpAfterReview
        case .awaitingFinalReview: return .runFinalReview
        case .completedPendingReview: return .acceptReview
        case .unknown: return nil  // «Обновить» — отдельная UI-кнопка
        }
    }

    /// Цветовая семантика узла графа и чипа. Высокий контраст на
    /// `tfCard`/`tfCard2` обязателен (WCAG AA 4.5:1, для
    /// `stalledManualReview`/`stepStalled` — AAA 7:1).
    public var tint: CoordinationTint {
        switch self {
        case .readyToStart: return .neutralBlue
        case .waitingPredecessor: return .dimGray
        case .blockedDependency: return .dimGray
        case .waitingOwner: return .amber
        case .waitingHuman: return .pink
        case .waitingTransient: return .dottedGray
        case .activeRun: return .accentPulse
        case .durableQueuedWake: return .softBlue
        case .recoveryPending: return .softCyan
        case .stalledManualReview: return .darkRedCritical
        case .providerLimit: return .pink
        case .permissionOrOwner: return .pink
        case .missingConfig: return .pink
        case .contextOverflow: return .darkRedCritical
        case .stepStalled: return .darkRedCritical
        case .review: return .violet
        case .branchRework: return .darkOrange
        case .awaitingFinalReview: return .violetOutline
        case .completedPendingReview: return .softGreen
        case .unknown: return .unknownGray
        }
    }
}

/// Закрытый словарь действий V2 (`ActionCode`). 14 значений. Кнопка в
/// Action bar: `label` + опционально URL для существующего маршрута.
/// `confirmRequired` поднимает sheet-подтверждение (как у bash-блоков).
public enum CoordinationAction: String, CaseIterable, Sendable {
    case start
    case waitPredecessor
    case liftDependency
    case askOwner
    case switchRole
    case retryWithDelay
    case replaceAttempt
    case switchProvider
    case fixConfig
    case acceptReview
    case runFinalReview
    case pickUpAfterReview
    case noAction
    case none

    /// Видимый текст кнопки (RU).
    public var label: String {
        switch self {
        case .start: return "Запустить"
        case .waitPredecessor: return "Ждём"
        case .liftDependency: return "Поднять блок"
        case .askOwner: return "Ответить"
        case .switchRole: return "Сменить роль"
        case .retryWithDelay: return "Перезапустить с задержкой"
        case .replaceAttempt: return "Перезапустить"
        case .switchProvider: return "Сменить провайдера"
        case .fixConfig: return "Открыть настройки"
        case .acceptReview: return "Принять"
        case .runFinalReview: return "Запустить ревью"
        case .pickUpAfterReview: return "Взять в работу"
        case .noAction: return "—"
        case .none: return "—"
        }
    }

    /// Требуется ли подтверждение владельца перед действием.
    public var confirmRequired: Bool {
        switch self {
        case .start, .replaceAttempt, .acceptReview: return true
        default: return false
        }
    }
}

/// Цветовая палитра причин. Маппинг на существующие tf-токены — это
/// **фиксация UX-документа**, чтобы один и тот же `cause` всегда
/// выглядел одинаково (проверка №7 QA: «зависшая ветвь рядом с
/// работающей, не маскируется»).
public enum CoordinationTint: Sendable {
    case neutralBlue
    case dimGray
    case dottedGray
    case amber
    case pink
    case accentPulse
    case softBlue
    case softCyan
    case darkRedCritical
    case violet
    case darkOrange
    case violetOutline
    case softGreen
    case unknownGray
}