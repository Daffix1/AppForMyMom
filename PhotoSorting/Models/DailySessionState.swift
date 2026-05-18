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
    
    // MARK: - Codable: ручной декодер с дефолтами для новых полей
    
    // Проблема: когда пользователь обновит приложение, в UserDefaults
    // уже лежит JSON старой сессии БЕЗ поля swipeLog. По умолчанию
    // JSONDecoder бросит ошибку и сессия не загрузится — потеряется
    // прогресс за сегодня.
    //
    // Решение: пишем свой init(from:) который для отсутствующих полей
    // подставляет пустые значения. Декодеру всё равно есть поле или нет.
    //
    // CodingKeys — это enum со всеми именами полей. Нужен для ручного
    // декодера: говорит "вот эти строки ищи в JSON".
    private enum CodingKeys: String, CodingKey {
        case date, phase, processedIDs, pendingDeleteIDs,
             currentDeletedIDs, currentKeptIDs, swipeLog
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
        swipeLog: [SwipeEntry]
    ) {
        self.date = date
        self.phase = phase
        self.processedIDs = processedIDs
        self.pendingDeleteIDs = pendingDeleteIDs
        self.currentDeletedIDs = currentDeletedIDs
        self.currentKeptIDs = currentKeptIDs
        self.swipeLog = swipeLog
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
    
    // Пустая сессия для текущего дня
    static func newToday() -> DailySessionState {
        DailySessionState(
            date: Date(),
            phase: .idle,
            processedIDs: [],
            pendingDeleteIDs: [],
            currentDeletedIDs: [],
            currentKeptIDs: [],
            swipeLog: []
        )
    }
}
