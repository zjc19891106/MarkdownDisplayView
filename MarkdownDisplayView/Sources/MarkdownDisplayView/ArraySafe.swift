//
//  ArraySafe.swift
//  MarkdownDisplayView
//
//  Created by 朱继超 on 12/15/25.
//

import Foundation

public extension Array {
    
    
    ///数组越界防护
    subscript(safe idx: Index) -> Element? {
        if idx < 0 { return nil }
        return idx < self.endIndex ? self[idx] : nil
    }
    
    subscript(safe range: Range<Int>) -> ArraySlice<Element>? {
        if range.startIndex < 0 { return nil }
        return range.endIndex <= self.endIndex ? self[range] : nil
    }
    
    func jsonString() -> String {
        if (!JSONSerialization.isValidJSONObject(self)) {
            print("无法解析出JSONString")
            return ""
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: self, options: [])
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            print("parser failed: \(error.localizedDescription)")
        }
        return ""
    }
    
    
    /// filterDuplicatesElements
    /// - Parameter filter: filter condition
    /// - Returns: result
    func filterDuplicates<E: Equatable>(_ filter: (Element) -> E) -> [Element] {
        var result = [Element]()
        for value in self {
            let key = filter(value)
            if !result.map({filter($0)}).contains(key) {
                result.append(value)
            }
        }
        return result
    }
    
}
