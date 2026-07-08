import Foundation

// MARK: - Протокол SessionStore
//
// Абстракция над "где живёт сессия сортировки за конкретный день".
//
// Зачем он нужен:
//   Раньше SortingView был намертво завязан на StorageService.shared.currentSession
//   — то есть на ЕДИНСТВЕННУЮ сегодняшнюю сессию, которая пишется в UserDefaults.
//   Чтобы тот же экран умел сортировать и произвольный день из календаря,
//   мы прячем "куда читать/писать сессию" за этот протокол.
//
// Две реализации:
//   - TodaySessionStore     — сегодня. Проксирует в StorageService (персист + resume).
//   - EphemeralSessionStore — прошлый день из календаря. Состояние в памяти,
//                             ничего не сохраняется, resume нет.
//
// Что НЕ входит в протокол (намеренно):
//   Глобальные эффекты — статистика удалений (totalDeleted*, totalFreedBytes)
//   и общий пул sortedPhotoIDs — одинаковы для всех дней и остаются в
//   StorageService. SortingView пишет их туда напрямую. Единственное отличие
//   по пулу между сторами выражено флагом persistsPoolImmediately (см. ниже).
protocol SessionStore: AnyObject {
    
    // За какой день эта сессия.
    var date: Date { get }
    
    // Само состояние сессии. Читается и пишется.
    // У TodaySessionStore запись уходит в UserDefaults, у Ephemeral — в память.
    var session: DailySessionState { get set }
    
    // Можно ли писать в глобальный пул sortedPhotoIDs СРАЗУ при каждом свайпе.
    //
    //   true  (TodaySessionStore)     — как раньше: помечаем фото обработанным
    //                                   немедленно. Брошенная сессия резюмится,
    //                                   поэтому пул и журнал не рассинхронятся.
    //
    //   false (EphemeralSessionStore) — НЕ трогаем пул во время свайпов.
    //                                   У эфемерного дня нет resume: если
    //                                   пользователь закрыл на середине, фото
    //                                   не должны исчезнуть из будущих сессий
    //                                   без подтверждённого решения. Пул
    //                                   обновляется только на финальном экране.
    var persistsPoolImmediately: Bool { get }
}


// MARK: - TodaySessionStore
//
// Сегодняшняя сессия. Тонкая обёртка над StorageService.shared.
// Всё поведение — ровно как было до рефакторинга: currentSession пишется
// в UserDefaults через didSet в StorageService, resume работает.
final class TodaySessionStore: SessionStore {
    
    // Ссылка на глобальное хранилище. Синглтон, как и везде в приложении.
    private let storage = StorageService.shared
    
    // Дата сессии — берём из текущей сохранённой сессии (она сегодняшняя).
    var date: Date {
        storage.currentSession.date
    }
    
    // session просто проксирует в storage.currentSession.
    // get — читаем из синглтона; set — пишем обратно (это триггерит
    // didSet в StorageService и сохранение в UserDefaults).
    var session: DailySessionState {
        get { storage.currentSession }
        set { storage.currentSession = newValue }
    }
    
    // Сегодня пишем в пул сразу — старое поведение, resume это прикрывает.
    var persistsPoolImmediately: Bool { true }
}


// MARK: - EphemeralSessionStore
//
// Сессия для произвольного дня из календаря. Состояние живёт ТОЛЬКО в памяти
// этого объекта. Когда SortingView закрывается и объект уничтожается —
// прогресс исчезает. Это и есть режим "отсортируй этот день один раз":
// закрыл на середине — начинаешь заново, никакого resume.
final class EphemeralSessionStore: SessionStore {
    
    // Дата, за которую сортируем. Задаётся при создании и не меняется.
    let date: Date
    
    // Состояние сессии целиком в памяти. Никакой записи в UserDefaults.
    var session: DailySessionState
    
    // Эфемерный день НЕ трогает общий пул во время свайпов — только на финале.
    var persistsPoolImmediately: Bool { false }
    
    // При создании собираем пустую сессию для нужной даты через общую фабрику.
    init(date: Date) {
        self.date = date
        self.session = DailySessionState.newSession(for: date)
    }
}
