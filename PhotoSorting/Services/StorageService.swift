import Foundation

// База всех данных пользователя. Singleton
@Observable
final class StorageService {
    
    static let shared = StorageService()
    
    private init() {
        // Счётчики «удалено» (фото/видео отдельно)
        self.totalDeletedPhotos = defaults.integer(forKey: Keys.totalDeletedPhotos)
        self.totalDeletedVideos = defaults.integer(forKey: Keys.totalDeletedVideos)
        
        // Освобождённое место
        self.totalFreedBytes = (defaults.object(forKey: Keys.totalFreedBytes) as? Int64) ?? 0
        
        self.onboardingCompleted = defaults.bool(forKey: Keys.onboardingCompleted)
        
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
    
    // MARK: - Минимум фото за день
    
    // Порог нужен для будущей фичи «блокировка приложений, пока не выполнена
    // дневная цель». После него на экране сортировки появляется кнопка
    // «Завершить сортировку». Стрик к порогу больше не привязан.
    static let dailyMinimum = 3
    
    // MARK: - Ключи
    
    private enum Keys {
        // Пул необработанных
        static let sortedPhotoIDs = "sortedPhotoIDs"
        
        // Статистика «удалено»
        static let totalDeletedPhotos = "totalDeletedPhotos"
        static let totalDeletedVideos = "totalDeletedVideos"
        static let totalFreedBytes = "totalFreedBytes"
        
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
    
    // MARK: - Статистика: удалено
    
    // Сколько фото физически удалено за всё время
    var totalDeletedPhotos: Int {
        didSet {
            defaults.set(totalDeletedPhotos, forKey: Keys.totalDeletedPhotos)
        }
    }
    
    // Сколько видео физически удалено за всё время
    var totalDeletedVideos: Int {
        didSet {
            defaults.set(totalDeletedVideos, forKey: Keys.totalDeletedVideos)
        }
    }
    
    // Всего удалено = фото + видео.
    // Вычисляемое: всегда сумма частей, рассогласовать нельзя.
    var totalDeleted: Int { totalDeletedPhotos + totalDeletedVideos }
    
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
        defaults.removeObject(forKey: Keys.totalDeletedPhotos)
        defaults.removeObject(forKey: Keys.totalDeletedVideos)
        defaults.removeObject(forKey: Keys.totalFreedBytes)
        defaults.removeObject(forKey: Keys.onboardingCompleted)
        defaults.removeObject(forKey: Keys.hapticsEnabled)
        defaults.removeObject(forKey: Keys.currentSession)
        
        // Обнуляем память
        totalDeletedPhotos = 0
        totalDeletedVideos = 0
        totalFreedBytes = 0
        onboardingCompleted = false
        sortedPhotoIDs = []
        currentSession = DailySessionState.newToday()
        hapticsEnabled = true
    }
}
