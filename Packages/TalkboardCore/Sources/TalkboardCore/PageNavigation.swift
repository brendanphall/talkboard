/// Bounded navigation; moving between pages never changes their content or order.
public struct PageNavigation: Equatable, Sendable {
    public let count: Int
    public private(set) var index = 0
    public init(count: Int) {
        precondition(count > 0, "Navigation requires at least one page")
        self.count = count
    }
    public var canGoBack: Bool { index > 0 }
    public var canGoForward: Bool { index < count - 1 }
    public mutating func previous() { if canGoBack { index -= 1 } }
    public mutating func next() { if canGoForward { index += 1 } }
    public mutating func home() { index = 0 }
}
