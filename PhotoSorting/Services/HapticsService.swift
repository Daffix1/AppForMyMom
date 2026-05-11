import UIKit

// Сервис для тактильной отдачи (вибраций)
// Singleton — один экземпляр на всё приложение
class HapticsService {
    
    static let shared = HapticsService()
    private init() {}
    
    // MARK: - Типы вибраций
    
    // enum — удобный способ описать "виды вибраций"
    // вместо магических строк или чисел
    enum FeedbackType {
        case light       // лёгкая — для интерактивных моментов (тап, начало свайпа)
        case medium      // средняя — для подтверждённых действий (свайп засчитан)
        case heavy       // сильная — для важных событий
        case success     // позитивная вибрация (завершение сессии)
        case warning     // предупреждение
        case error       // ошибка
        case selection   // лёгкий "клик" (переключение в селекторе)
    }
    
    // MARK: - Главный метод
    
    func play(_ type: FeedbackType) {
        // Если настройка выключена, ничего не делаем
        guard StorageService.shared.hapticsEnabled else { return }
        
        switch type {
        case .light:
            // UIImpactFeedbackGenerator — для "ударов"
            // Стиль .light — лёгкое касание
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.prepare()  // подготавливаем — это уменьшает задержку
            generator.impactOccurred()
            
        case .medium:
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.prepare()
            generator.impactOccurred()
            
        case .heavy:
            let generator = UIImpactFeedbackGenerator(style: .heavy)
            generator.prepare()
            generator.impactOccurred()
            
        case .success:
            // UINotificationFeedbackGenerator — для "уведомлений"
            // .success — мягкая позитивная вибрация
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(.success)
            
        case .warning:
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(.warning)
            
        case .error:
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(.error)
            
        case .selection:
            // UISelectionFeedbackGenerator — для переключений
            // Используется в системных селекторах iOS
            let generator = UISelectionFeedbackGenerator()
            generator.prepare()
            generator.selectionChanged()
        }
    }
}
