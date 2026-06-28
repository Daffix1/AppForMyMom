import SwiftUI
import Charts   // Встроенный фреймворк Apple для графиков (iOS 16+)

struct StatsView: View {
    // Читаем из реактивного singleton'а напрямую
    private let storage = StorageService.shared
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    freedSpaceHero
                    deletedCard
                    Spacer().frame(height: 20)
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Статистика")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }
    
    // MARK: - Главный акцент: освобождённое место
    
    private var freedSpaceHero: some View {
        VStack(spacing: 2) {
            Text("Освобождено места")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.green)
                .textCase(.uppercase)
            Text(formattedFreedSpace)
                .font(.system(size: 40, weight: .bold))
                .foregroundColor(.green)
                .contentTransition(.numericText())
            Text("примерно")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(Color.green.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
    
    // MARK: - Блок «Удалено всего»
    
    private var deletedCard: some View {
        VStack(spacing: 16) {
            VStack(spacing: 2) {
                Text("Удалено всего")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                Text("\(storage.totalDeleted)")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.red)
                    .contentTransition(.numericText())
                Text(storage.totalDeleted.fileWord())
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            
            breakdownRow(
                photos: storage.totalDeletedPhotos,
                videos: storage.totalDeletedVideos,
                photoColor: .red,
                videoColor: .orange
            )
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
    
    // MARK: - Строка «диаграмма + легенда»
    
    @ViewBuilder
    private func breakdownRow(
        photos: Int,
        videos: Int,
        photoColor: Color,
        videoColor: Color
    ) -> some View {
        let total = photos + videos
        
        HStack(spacing: 20) {
            donut(photos: photos, videos: videos,
                  photoColor: photoColor, videoColor: videoColor)
                .frame(width: 96, height: 96)
            
            VStack(alignment: .leading, spacing: 10) {
                legendRow(color: photoColor, label: "Фото",
                          count: photos, percent: percent(photos, of: total))
                legendRow(color: videoColor, label: "Видео",
                          count: videos, percent: percent(videos, of: total))
            }
            
            Spacer()
        }
    }
    
    // MARK: - Кольцевая диаграмма (donut)
    
    @ViewBuilder
    private func donut(
        photos: Int,
        videos: Int,
        photoColor: Color,
        videoColor: Color
    ) -> some View {
        let total = photos + videos
        
        if total == 0 {
            // Пустое состояние — серое кольцо без данных
            Circle()
                .stroke(Color.gray.opacity(0.2), lineWidth: 18)
                .padding(9)
        } else {
            Chart {
                SectorMark(
                    angle: .value("Фото", photos),
                    innerRadius: .ratio(0.62),
                    angularInset: 1.5
                )
                .foregroundStyle(photoColor)
                
                SectorMark(
                    angle: .value("Видео", videos),
                    innerRadius: .ratio(0.62),
                    angularInset: 1.5
                )
                .foregroundStyle(videoColor)
            }
            .chartLegend(.hidden)
        }
    }
    
    // MARK: - Одна строка легенды
    
    private func legendRow(
        color: Color,
        label: String,
        count: Int,
        percent: Int
    ) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .frame(width: 11, height: 11)
            
            VStack(alignment: .leading, spacing: 0) {
                Text("\(count) \(label.lowercased())")
                    .font(.system(size: 14, weight: .medium))
                Text("\(percent)%")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Освобождённое место (форматирование байтов)
    
    private var formattedFreedSpace: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.includesCount = true
        return formatter.string(fromByteCount: storage.totalFreedBytes)
    }
    
    // MARK: - Процент с защитой от деления на ноль
    
    private func percent(_ part: Int, of total: Int) -> Int {
        guard total > 0 else { return 0 }
        return Int((Double(part) / Double(total) * 100).rounded())
    }
}

// MARK: - Склонение слова «файл»

private extension Int {
    func fileWord() -> String {
        let lastDigit = self % 10
        let lastTwo = self % 100
        
        if lastTwo >= 11 && lastTwo <= 14 {
            return "файлов"
        }
        switch lastDigit {
        case 1: return "файл"
        case 2, 3, 4: return "файла"
        default: return "файлов"
        }
    }
}

#Preview {
    StatsView()
}
