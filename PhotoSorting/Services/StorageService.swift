import Foundation

// База всех данных пользователя. Singleton
@Observable
final class StorageService {
    
    static let shared = StorageService()
    
    private init() {
        // Простые числовые
        self.totalDeleted = defaults.integer(forKey: Keys.totalDeleted)
        self.totalFreedBytes = (defaults.object(forKey: Keys.totalFreedBytes) as? Int64) ?? 0
        self.currentStreak = defaults.integer(forKey: Keys.currentStreak)
        self.onboardingCompleted = defaults.bool(forKey: Keys.onboardingCompleted)
        
        // Дата (опциональная)
        self.lastStreakDate = defaults.object(forKey: Keys.lastStreakDate) as? Date
        
        // Множество строк
        let array = defaults.stringArray(forKey: Keys.sortedPhotoIDs) ?? []
        self.sortedPhotoIDs = Set(array)
        
        // Сессия (JSON-decoded)
        if let data = defaults.data(forKey: Keys.currentSession),
           let session = try? JSONDecoder().decode(DailySessionState.self, from: data),
           session.isToday {
            self.currentSession = session
        } else {
            self.currentSession = DailySessionState.newToday()
        }
        // Если ключа нет — дефолт true (вибрация включена для нового пользователя)
        if defaults.object(forKey: Keys.hapticsEnabled) == nil {
            self.hapticsEnabled = true
        } else {
            self.hapticsEnabled = defaults.bool(forKey: Keys.hapticsEnabled)
        }
    }
    
    @ObservationIgnored
    private let defaults = UserDefaults.standard // упрощаем обращение к встроенной бд
    
    // MARK: - Минимум фото для засчитывания Стрика
    
    static let dailyMinimum = 30
    
    // MARK: - Ключи
    
    private enum Keys {
        // Статистика
        static let sortedPhotoIDs = "sortedPhotoIDs"
        static let totalDeleted = "totalDeleted"
        static let totalFreedBytes = "totalFreedBytes"
        
        // Стрик
        static let currentStreak = "currentStreak"
        static let lastStreakDate = "lastStreakDate"
        
        // Настройки
        static let onboardingCompleted = "onboardingCompleted"
        static let hapticsEnabled = "hapticsEnabled"
        
        // Состояние сегодняшнего дня
        static let currentSession = "currentSession"
    }
    
    // MARK: - Текущая сессия
    
    var currentSession: DailySessionState {
        didSet {
            if let data = try? JSONEncoder().encode(currentSession) {
                defaults.set(data, forKey: Keys.currentSession)
            }
        }
    }
    
    // MARK: - Статистика
    
    // Всего удалённых фото за всё время
    var totalDeleted: Int {
        didSet {
            defaults.set(totalDeleted, forKey: Keys.totalDeleted)
        }
    }
    
    // Освобождено байт за всё время (примерно)
    var totalFreedBytes: Int64 {
        didSet {
            defaults.set(totalFreedBytes, forKey: Keys.totalFreedBytes)
        }
    }
    
    // Множество ID всех когда-либо обработанных фото, для фильтрации в галерее
    // Чтобы не показывать пользователю то что он уже видел в прошлые дни
    var sortedPhotoIDs: Set<String> {
        didSet {
            defaults.set(Array(sortedPhotoIDs), forKey: Keys.sortedPhotoIDs)
        }
    }
    
    // MARK: - Стрик
    
    var currentStreak: Int {
        didSet {
            defaults.set(currentStreak, forKey: Keys.currentStreak)
        }
    }
    
    private var lastStreakDate: Date? {
        didSet {
            defaults.set(lastStreakDate, forKey: Keys.lastStreakDate)
        }
    }
    
    // Засчитан ли стрик за сегодня
    var todayStreakReached: Bool {
        guard let date = lastStreakDate else { return false }
        return Calendar.current.isDateInToday(date)
    }
    
    // Сколько ещё нужно обработать фото для засчитывания стрика за сегодня
    var photosRemainingForStreak: Int {
        let needed = Self.dailyMinimum - currentSession.totalProcessedToday
        return max(0, needed)
    }
    
    // Засчитывает стрик за сегодня
    func updateStreak() {
        let calendar = Calendar.current
        let today = Date()
        
        if let last = lastStreakDate { // если нет стрика, стрик = 1
            if calendar.isDateInToday(last) { // есть стрик и он сегодняшний
                return
            } else if calendar.isDateInYesterday(last) { // есть стрик и он вчерашний
                currentStreak += 1
            } else {
                currentStreak = 0
            }
        } else {
            currentStreak = 1
        }
        
        lastStreakDate = today
    }
    
    // MARK: - Настройки
    
    var onboardingCompleted: Bool {
        didSet {
            defaults.set(onboardingCompleted, forKey: Keys.onboardingCompleted)
        }
    }
    
    var hapticsEnabled: Bool {
        didSet {
            defaults.set(hapticsEnabled, forKey: Keys.hapticsEnabled)
        }
    }
    
    func ensureFreshSession() {
        // Если сессия уже сегодняшняя — ничего не делаем
        guard !currentSession.isToday else { return }
        
        // не прерываем пока чел сортирует или на финальной стадии
        let activePhases: [DailySessionState.Phase] = [.sorting, .awaitingDecision]
        if activePhases.contains(currentSession.phase) {
            return
        }
        
        currentSession = DailySessionState.newToday()
    }
    
    // MARK: - Сброс (для отладки)
    
    func resetAll() {
        defaults.removeObject(forKey: Keys.sortedPhotoIDs)
        defaults.removeObject(forKey: Keys.totalDeleted)
        defaults.removeObject(forKey: Keys.totalFreedBytes)
        defaults.removeObject(forKey: Keys.currentStreak)
        defaults.removeObject(forKey: Keys.lastStreakDate)
        defaults.removeObject(forKey: Keys.onboardingCompleted)
        defaults.removeObject(forKey: Keys.hapticsEnabled)
        defaults.removeObject(forKey: Keys.currentSession)
        
        // Обнуляем память
        totalDeleted = 0
        totalFreedBytes = 0
        currentStreak = 0
        onboardingCompleted = false
        lastStreakDate = nil
        sortedPhotoIDs = []
        currentSession = DailySessionState.newToday()
        hapticsEnabled = true
    }
}
