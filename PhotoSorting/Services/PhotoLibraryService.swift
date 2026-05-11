




import Photos
import Foundation
import UIKit

// Описываем одно фото — только то, что нам нужно
struct PhotoItem: Identifiable {
    let id: String          // ID
    let asset: PHAsset      // Фото
    let creationDate: Date  // Дата
}

@MainActor
final class PhotoLibraryService {
    
    static let shared = PhotoLibraryService()
    
    private init() {}
    
    private let yearsBack = 40
    
    // MARK: - Запрос разрешения
    
    func requestAuthorization() async -> Bool {
        // Проверяем текущий статус разрешения
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        
        switch status {
        case .authorized, .limited: // конкретные фото
            return true
            
        case .notDetermined: // еще не спрашивали
            let newStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            return newStatus == .authorized || newStatus == .limited
            
        case .denied, .restricted: // запретил
            return false
            
        @unknown default:
            return false
        }
    }
    
    // Примерный размер освобожденного места в байтах
    static func estimateSize(for asset: PHAsset) -> Int64 {
        let pixels = asset.pixelWidth * asset.pixelHeight
        
        if asset.mediaType == .video {
            let duration = asset.duration
            // Приблизительный битрейт
            let bytesPerSecond: Double
            if pixels >= 8_000_000 {       // 4K и выше
                bytesPerSecond = 830_000
            } else if pixels >= 2_000_000 {  // 1080p
                bytesPerSecond = 250_000
            } else {                        // ниже HD
                bytesPerSecond = 100_000
            }
            
            return Int64(duration * bytesPerSecond)
        } else {
            let bytesPerPixel = 0.3
            return Int64(Double(pixels) * bytesPerPixel)
        }
    }
    
    // MARK: - Поиск фото за "этот день прошлых лет"
    
    func fetchPhotosForToday() async -> [PhotoItem] {
        let calendar = Calendar.current
        let today = Date()
        
        let month = calendar.component(.month, from: today)
        let day = calendar.component(.day, from: today)
        let currentYear = calendar.component(.year, from: today)
        
        // Вычисляем диапазоны дат для каждого года
        var dateRanges: [NSPredicate] = []
        
        for year in (currentYear - yearsBack)...currentYear {
            // Полночь нужного дня в нужном году
            var components = DateComponents()
            components.year = year
            components.month = month
            components.day = day
            components.hour = 0
            components.minute = 0
            components.second = 0
            
            guard let startDate = calendar.date(from: components) else { continue }
            // 24 часа спустя — конец дня
            guard let endDate = calendar.date(byAdding: .day, value: 1, to: startDate) else { continue }
            
            // фото создано в этом интервале
            let predicate = NSPredicate(
                format: "creationDate >= %@ AND creationDate < %@",
                startDate as NSDate,
                endDate as NSDate
            )
            dateRanges.append(predicate)
        }
        
        // Объединяем все интервалы
        let compoundPredicate = NSCompoundPredicate(orPredicateWithSubpredicates: dateRanges)
        
        // Настраиваем запрос с фильтром по дате
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = compoundPredicate
        fetchOptions.sortDescriptors = [
            NSSortDescriptor(key: "creationDate", ascending: false)
        ]

        let assets = PHAsset.fetchAssets(with: fetchOptions)
        
        // Список отсортированных фото
        let alreadySorted = StorageService.shared.sortedPhotoIDs
        
        var result: [PhotoItem] = []
        
        assets.enumerateObjects { asset, _, _ in
            guard let date = asset.creationDate else { return }
            
            // Пропускаем уже обработанные
            guard !alreadySorted.contains(asset.localIdentifier) else { return }
            
            let item = PhotoItem(
                id: asset.localIdentifier,
                asset: asset,
                creationDate: date
            )
            result.append(item)
        }
        
        return result
    }
    
    // MARK: - Загрузка изображения (async с кэшем)

    // Async-версия loadImage с интеграцией кэша.
    // Возвращает финальное (не degraded) изображение или nil.
    // nil означает либо ошибку, либо таймаут (15 секунд).
    //
    // onICloudProgress срабатывает только если фото грузится из iCloud.
    // Для локальных фото этот колбэк никогда не вызовется.
    func loadImage(
        for asset: PHAsset,
        targetSize: CGSize,
        deliveryMode: PHImageRequestOptionsDeliveryMode,
        onICloudProgress: (@Sendable (Double) -> Void)? = nil
    ) async -> UIImage? {
        let id = asset.localIdentifier

        // 1. Проверяем кэш
        if let cached = PhotoCacheService.shared.cachedImage(for: id) {
            return cached
        }

        // 2. Готовим параметры запроса
        let options = PHImageRequestOptions()
        options.deliveryMode = deliveryMode
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true

        if let onICloudProgress {
            options.progressHandler = { progress, _, _, _ in
                Task { @MainActor in
                    onICloudProgress(progress)
                }
            }
        }

        // 3. Оборачиваем callback в async.
        // didResume защищает от двойного resume (opportunistic даёт 2+ колбэка).
        // Таймаут защищает от утечки если PHImageManager никогда не ответит.
        let image: UIImage? = await withCheckedContinuation { continuation in
            var didResume = false

            // Таймаут — через 15 секунд форсируем resume с nil
            let timeoutTask = Task {
                try? await Task.sleep(for: .seconds(15))
                guard !didResume else { return }
                didResume = true
                continuation.resume(returning: nil)
            }

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { img, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if isDegraded { return }

                guard !didResume else { return }
                didResume = true
                timeoutTask.cancel()
                continuation.resume(returning: img)
            }
        }

        // 4. Кэшируем только если получили реальное изображение
        if let image {
            PhotoCacheService.shared.cacheImage(image, for: id)
        }

        return image
    }
    
    // MARK: - Удаление фото
    
    // Удаляет несколько фото за раз — один диалог для всех
    func deletePhotos(_ assets: [PHAsset]) async -> Bool {
        guard !assets.isEmpty else { return true }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets as NSArray)
            }
            return true
        } catch {
            print("Ошибка удаления: \(error)")
            return false
        }
    }
}
