import Foundation

extension Int {
    
    func photoWord() -> String {
        let lastDigit = self % 10
        let lastTwo = self % 100
        
        // Особый случай: 11, 12, 13, 14 — всегда "фотографий"
        if lastTwo >= 11 && lastTwo <= 14 {
            return "фотографий"
        }
        
        switch lastDigit {
        case 1: return "фотография"
        case 2, 3, 4: return "фотографии"
        default: return "фотографий"
        }
    }
}
