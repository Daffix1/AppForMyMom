




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

        // Возвращает ВСЕ фото за указанный (месяц, день) по всем годам в пределах
        // yearsBack. Никакой фильтрации по «уже обработанным» — глобального пула
        // больше нет. Единственный фильтр «фото исчезло» обеспечивает сама iOS:
        // удалённый asset не вернётся из fetchAssets.
        //
        // Почему month/day компонентами, а не Date: сортируемый день у нас живёт
        // как selectedMonth/selectedDay (без года). Передавать Date пришлось бы
        // с искусственным годом, а 29 февраля в невисокосный год из Date не
        // собирается. Компоненты снимают эту проблему на входе.
        func fetchPhotos(month: Int, day: Int) async -> [PhotoItem] {
            let calendar = Calendar.current
            let currentYear = calendar.component(.year, from: Date())

            var dateRanges: [NSPredicate] = []

            for year in (currentYear - yearsBack)...currentYear {
                var components = DateComponents()
                components.year = year
                components.month = month
                components.day = day
                components.hour = 0
                components.minute = 0
                components.second = 0

                guard let startDate = calendar.date(from: components) else { continue }

                // GUARD 29 февраля: для невисокосного года Calendar.date(from:)
                // НЕ вернёт nil, а молча нормализует "29 февраля" в "1 марта".
                // Без этой проверки выбор 29 февраля подтянул бы мартовские фото.
                // Убеждаемся, что собранная дата реально имеет нужные месяц и день;
                // если Calendar их "поправил" — пропускаем этот год.
                let check = calendar.dateComponents([.month, .day], from: startDate)
                guard check.month == month, check.day == day else { continue }

                guard let endDate = calendar.date(byAdding: .day, value: 1, to: startDate) else { continue }

                let predicate = NSPredicate(
                    format: "creationDate >= %@ AND creationDate < %@",
                    startDate as NSDate,
                    endDate as NSDate
                )
                dateRanges.append(predicate)
            }

            let compoundPredicate = NSCompoundPredicate(orPredicateWithSubpredicates: dateRanges)

            let fetchOptions = PHFetchOptions()
            fetchOptions.predicate = compoundPredicate
            fetchOptions.sortDescriptors = [
                NSSortDescriptor(key: "creationDate", ascending: false)
            ]

            let assets = PHAsset.fetchAssets(with: fetchOptions)

            var result: [PhotoItem] = []

            assets.enumerateObjects { asset, _, _ in
                guard let creationDate = asset.creationDate else { return }
                let item = PhotoItem(
                    id: asset.localIdentifier,
                    asset: asset,
                    creationDate: creationDate
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
        onICloudProgress: (@Sendable (Double) -> Void)? = nil,
        onPreview: (@Sendable (UIImage) -> Void)? = nil  // NEW
    ) async -> UIImage? {
        let id = asset.localIdentifier

        // 1. Check cache
        if let cached = PhotoCacheService.shared.cachedImage(for: id) {
            return cached
        }

        // 2. Set up options
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

        // 3. Async wrapper
        let image: UIImage? = await withCheckedContinuation { continuation in
            var didResume = false

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
                
                if isDegraded {
                    // Deliver the preview to the caller immediately
                    // but don't resume the continuation — wait for the full image
                    if let img, let onPreview {
                        Task { @MainActor in
                            onPreview(img)
                        }
                    }
                    return
                }

                guard !didResume else { return }
                didResume = true
                timeoutTask.cancel()
                continuation.resume(returning: img)
            }
        }

        // 4. Cache the final result
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
