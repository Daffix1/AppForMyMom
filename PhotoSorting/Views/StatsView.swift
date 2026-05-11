import SwiftUI

struct StatsView: View {
    // Storage не привязан к @State — мы просто читаем из него один раз
    private let storage = StorageService.shared
    
    // Закрывает экран статистики
    // dismiss — встроенная функция SwiftUI для закрытия sheet
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Большая цифра удалённых
                    deletedHero
                    
                    // Освобождённое место
                    freedSpaceCard
                    
                    // Streak
                    streakCard
                    
                    Spacer().frame(height: 20)
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Статистика")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    // MARK: - Большая цифра удалённых
    
    private var deletedHero: some View {
        VStack(spacing: 8) {
            Text("Удалено всего")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            
            Text("\(storage.totalDeleted)")
                .font(.system(size: 72, weight: .bold))
                .foregroundColor(.blue)
                // contentTransition даёт плавную анимацию числа
                // Если будем потом обновлять в реальном времени — оно будет красиво "перекатываться"
                .contentTransition(.numericText())
            
            Text(photoWord(storage.totalDeleted))
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
    
    // MARK: - Карточка освобождённого места

    private var freedSpaceCard: some View {
        HStack(spacing: 16) {
            Text("💾")
                .font(.system(size: 48))
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Освобождено места")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                
                Text(formattedFreedSpace)
                    .font(.system(size: 32, weight: .bold))
                
                Text("примерно")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    // Форматирует байты в красивую строку: "2.4 ГБ", "350 МБ", "0 КБ"
    private var formattedFreedSpace: String {
        let bytes = storage.totalFreedBytes
        
        // ByteCountFormatter — встроенный в iOS форматтер
        // Сам выбирает подходящие единицы (КБ/МБ/ГБ)
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.includesCount = true
        
        return formatter.string(fromByteCount: bytes)
    }
    
    // MARK: - Streak
    
    private var streakCard: some View {
        HStack(spacing: 16) {
            // Большой огонёк слева
            Text("🔥")
                .font(.system(size: 48))
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Серия дней")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                
                Text("\(storage.currentStreak)")
                    .font(.system(size: 32, weight: .bold))
                
                Text(streakSubtitle())
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    
    
    
    
    // MARK: - Текстовые помощники
    
    // "1 фото", "2 фотографии", "5 фотографий"
    private func photoWord(_ count: Int) -> String {
        let lastDigit = count % 10
        let lastTwo = count % 100
        
        if lastTwo >= 11 && lastTwo <= 14 {
            return "фотографий"
        }
        switch lastDigit {
        case 1: return "фотография"
        case 2, 3, 4: return "фотографии"
        default: return "фотографий"
        }
    }
    
    // Подпись под streak в зависимости от значения
    private func streakSubtitle() -> String {
        let count = storage.currentStreak
        if count == 0 {
            return "Начните прямо сейчас!"
        } else if count == 1 {
            return "Отличное начало"
        } else if count < 7 {
            return "Так держать!"
        } else if count < 30 {
            return "Великолепно"
        } else {
            return "Невероятно!"
        }
    }
}

#Preview {
    StatsView()
}
