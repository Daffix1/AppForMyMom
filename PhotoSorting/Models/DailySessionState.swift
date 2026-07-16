import Foundation

// Состояние одной "ежедневной сессии"
// Хранится целиком как JSON в UserDefaults
//
// Codable означает: умею превращать себя в JSON и обратно
struct DailySessionState: Codable {
    
    // MARK: - Фазы сессии
    
    // В каком состоянии сегодняшний день
    enum Phase: String, Codable {
        case idle              // день только начался, ничего не свайпали
        case sorting           // идёт сортировка
        case awaitingDecision  // на финальном экране, ждём кнопку
        case completed         // день закрыт по решению пользователя
    }
    
    // MARK: - Запись об одном свайпе
    
    // Одна запись в журнале свайпов.
    // Нужна чтобы при переоткрытии SortingView мы могли:
    //   1. Понять на каком фото остановились (длина swipeLog)
    //   2. Восстановить историю для кнопки "назад" (последний свайп — в конце)
    //   3. Сохранить порядок: delete-keep-delete-keep нельзя восстановить
    //      из двух отдельных массивов, нужен один упорядоченный список
    struct SwipeEntry: Codable, Equatable {
        let photoID: String
        let direction: Direction
        
        enum Direction: String, Codable {
            case left   // удалить
            case right  // оставить
        }
    }
    
    // MARK: - Поля
    
    let date: Date
    var phase: Phase
    
    // ID всех обработанных фото за сегодня
    var processedIDs: Set<String>
    
    // ID фото которые ждут удаления
    var pendingDeleteIDs: [String]
    
    // ID оставленных в текущей сессии, для подсчёта на финальном экране
    var currentDeletedIDs: [String]
    var currentKeptIDs: [String]
    
    // Журнал всех свайпов за эту сессию, в порядке совершения.
    // Используется для восстановления состояния SortingView после
    // повторного открытия и для работы кнопки "назад".
    var swipeLog: [SwipeEntry]
        
    // MARK: - Сортируемый день (число + месяц, БЕЗ года)
    //
    // Какой календарный день пользователь сортирует: 7 июля → (month: 7, day: 7).
    // Год намеренно не храним — механика "этот день во всех прошлых годах"
    // ищет фото по (месяц, день) сразу по всем годам.
    //
    // Почему компонентами Int, а не Date: Date без года не существует, а с
    // годом 29 февраля в невисокосный год не создаётся корректно. Отдельные
    // month/day хранят намерение пользователя чисто, независимо от високосности.
    //
    // ВАЖНО: это НЕ то же самое, что поле date. date — календарный день,
    // к которому привязана сессия (по нему работает полуночный сброс, isToday).
    // selectedMonth/Day — какой день СОРТИРУЕМ. Для сегодняшней сессии они
    // совпадают; для дня, выбранного в календаре, разойдутся (это сделаем позже).
    var selectedMonth: Int
    var selectedDay: Int
    
    private enum CodingKeys: String, CodingKey {
        case date, phase, processedIDs, pendingDeleteIDs,
             currentDeletedIDs, currentKeptIDs, swipeLog,
             selectedMonth, selectedDay
    }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        
        // Поля которые БЫЛИ всегда — декодируем как обычно.
        // Если их вдруг нет в JSON, это настоящая ошибка — пусть бросает.
        self.date = try c.decode(Date.self, forKey: .date)
        self.phase = try c.decode(Phase.self, forKey: .phase)
        self.processedIDs = try c.decode(Set<String>.self, forKey: .processedIDs)
        self.pendingDeleteIDs = try c.decode([String].self, forKey: .pendingDeleteIDs)
        self.currentDeletedIDs = try c.decode([String].self, forKey: .currentDeletedIDs)
        self.currentKeptIDs = try c.decode([String].self, forKey: .currentKeptIDs)
        
        // НОВОЕ поле — используем decodeIfPresent + ?? []
        // decodeIfPresent возвращает nil если ключа нет (вместо ошибки)
        // ?? [] подставляет пустой массив как дефолт
        self.swipeLog = try c.decodeIfPresent([SwipeEntry].self, forKey: .swipeLog) ?? []
        
        let today = Calendar.current.dateComponents([.month, .day], from: Date())
        self.selectedMonth = try c.decodeIfPresent(Int.self, forKey: .selectedMonth) ?? (today.month ?? 1)
        self.selectedDay = try c.decodeIfPresent(Int.self, forKey: .selectedDay) ?? (today.day ?? 1)
    }
    
    // MARK: - Обычный init (нужен потому что мы написали свой init(from:))
    
    // Когда добавляешь свой init(from:), Swift больше не генерирует
    // memberwise init автоматически. Поэтому пишем явный init для
    // создания новых сессий из кода.
    init(
        date: Date,
        phase: Phase,
        processedIDs: Set<String>,
        pendingDeleteIDs: [String],
        currentDeletedIDs: [String],
        currentKeptIDs: [String],
        swipeLog: [SwipeEntry],
        selectedMonth: Int,
        selectedDay: Int
    ) {
        self.date = date
        self.phase = phase
        self.processedIDs = processedIDs
        self.pendingDeleteIDs = pendingDeleteIDs
        self.currentDeletedIDs = currentDeletedIDs
        self.currentKeptIDs = currentKeptIDs
        self.swipeLog = swipeLog
        self.selectedMonth = selectedMonth
        self.selectedDay = selectedDay
    }
    
    // MARK: - Удобные вычисляемые свойства
    
    var deletedCount: Int { currentDeletedIDs.count }
    var keptCount: Int { currentKeptIDs.count }
    
    // Сколько всего обработано за сегодня, для нужного минимума
    var totalProcessedToday: Int { processedIDs.count }
    
    // Сессия сегодня или нет
    var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }
    
    // MARK: - Создание новой сессии
    
    // Пустая сессия. Разводим две даты:
    //   livesOn — календарный день, В КОТОРЫЙ живёт сессия. По нему работает
    //             полуночный сброс (isToday). Обычно это Date() — сегодня.
    //   sorting — какой день СОРТИРУЕМ (число+месяц). Для сегодняшней сортировки
    //             совпадает с livesOn; для дня из календаря — отличается.
    static func newSession(livesOn: Date, sorting: Date) -> DailySessionState {
        let comps = Calendar.current.dateComponents([.month, .day], from: sorting)
        return DailySessionState(
            date: livesOn,
            phase: .idle,
            processedIDs: [],
            pendingDeleteIDs: [],
            currentDeletedIDs: [],
            currentKeptIDs: [],
            swipeLog: [],
            selectedMonth: comps.month ?? 1,
            selectedDay: comps.day ?? 1
        )
    }

    static func newToday() -> DailySessionState {
        newSession(livesOn: Date(), sorting: Date())
    }
}
