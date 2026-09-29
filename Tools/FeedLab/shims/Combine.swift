// Minimal stand-in for Apple's Combine, just enough for Grindstone's stores
// and view model to compile and run on Linux. `@Published` emits before the
// value is written, like the real one.

public protocol ObservableObject: AnyObject {}

public final class PublishedSubject<Output> {
    var handlers: [(Output) -> Void] = []
    func send(_ value: Output) { handlers.forEach { $0(value) } }
}

public struct ShimPublisher<Output> {
    let subscribe: (@escaping (Output) -> Void) -> Void

    public func dropFirst(_ count: Int = 1) -> ShimPublisher<Output> {
        ShimPublisher { handler in
            var seen = 0
            self.subscribe { value in
                if seen < count { seen += 1 } else { handler(value) }
            }
        }
    }

    public func sink(receiveValue: @escaping (Output) -> Void) -> AnyCancellable {
        subscribe(receiveValue)
        return AnyCancellable()
    }
}

extension ShimPublisher where Output: Equatable {
    public func removeDuplicates() -> ShimPublisher<Output> {
        ShimPublisher { handler in
            var last: Output?
            self.subscribe { value in
                if value != last {
                    last = value
                    handler(value)
                }
            }
        }
    }
}

public final class AnyCancellable: Hashable {
    public init() {}
    public static func == (lhs: AnyCancellable, rhs: AnyCancellable) -> Bool { lhs === rhs }
    public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
    public func store(in set: inout Set<AnyCancellable>) { set.insert(self) }
}

@propertyWrapper
public struct Published<Value> {
    private var value: Value
    private let subject = PublishedSubject<Value>()

    public init(wrappedValue: Value) { value = wrappedValue }

    public var wrappedValue: Value {
        get { value }
        set {
            subject.send(newValue)
            value = newValue
        }
    }

    public var projectedValue: ShimPublisher<Value> {
        let subject = subject
        let current = value
        return ShimPublisher { handler in
            subject.handlers.append(handler)
            handler(current)
        }
    }
}
