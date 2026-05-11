import UIKit

// Кэш для предзагрузки изображений
class PhotoCacheService {
    static let shared = PhotoCacheService()
    
    private let cache = NSCache<NSString, UIImage>()
    
    private init() {
        cache.countLimit = 50
        // Лимит по памяти
        cache.totalCostLimit = 100 * 1024 * 1024  // 100 МБ
    }
    
    func cachedImage(for id: String) -> UIImage? {
        return cache.object(forKey: id as NSString)
    }
    
    func cacheImage(_ image: UIImage, for id: String) {
        let cost = (image.cgImage?.bytesPerRow ?? 0) * (image.cgImage?.height ?? 0)
        cache.setObject(image, forKey: id as NSString, cost: cost)
    }
    
    func clear() {
        cache.removeAllObjects()
    }
}

// Расчёт размера UIImage в байтах для NSCache
private extension UIImage {
    var byteSize: Int {
        (cgImage?.bytesPerRow ?? 0) * (cgImage?.height ?? 0)
    }
}
