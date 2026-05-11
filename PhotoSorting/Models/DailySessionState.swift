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
            currentKeptIDs: []
        )
    }
}
