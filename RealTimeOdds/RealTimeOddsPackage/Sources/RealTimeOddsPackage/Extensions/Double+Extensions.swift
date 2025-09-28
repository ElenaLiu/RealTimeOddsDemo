import Foundation

// MARK: - Double Extensions
public extension Double {
    /// 1. 四捨五入到指定小數位。 2. 限制結果在特定區間內（最低 1.05，最高 6.50）。
    func clampedOdds(decimals: Int = 2) -> Double {
        let precision = pow(10.0, Double(decimals))
        let rounded = (self * precision).rounded() / precision
        return Swift.min(Swift.max(rounded, 1.05), 6.50)
    }
}


