import Foundation

// MARK: - Array Extensions
public extension Array {
    /// 將陣列轉換為字典
    func toDictionary<Key: Hashable>(by keyPath: KeyPath<Element, Key>) -> [Key: Element] {
        return Dictionary(uniqueKeysWithValues: map { ($0[keyPath: keyPath], $0) })
    }
    
}

