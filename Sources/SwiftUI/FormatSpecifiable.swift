import Foundation

public protocol _FormatSpecifiable: Equatable {
    associatedtype _Arg: CVarArg
    var _arg: _Arg { get }
    var _specifier: String { get }
}

extension Int: _FormatSpecifiable {
    public var _arg: Int64 { Int64(self) }
    public var _specifier: String { "%lld" }
}

extension Int8: _FormatSpecifiable {
    public var _arg: Int32 { Int32(self) }
    public var _specifier: String { "%d" }
}

extension Int16: _FormatSpecifiable {
    public var _arg: Int32 { Int32(self) }
    public var _specifier: String { "%d" }
}

extension Int32: _FormatSpecifiable {
    public var _arg: Int32 { self }
    public var _specifier: String { "%d" }
}

extension Int64: _FormatSpecifiable {
    public var _arg: Int64 { self }
    public var _specifier: String { "%lld" }
}

extension UInt: _FormatSpecifiable {
    public var _arg: UInt64 { UInt64(self) }
    public var _specifier: String { "%llu" }
}

extension UInt8: _FormatSpecifiable {
    public var _arg: UInt32 { UInt32(self) }
    public var _specifier: String { "%u" }
}

extension UInt16: _FormatSpecifiable {
    public var _arg: UInt32 { UInt32(self) }
    public var _specifier: String { "%u" }
}

extension UInt32: _FormatSpecifiable {
    public var _arg: UInt32 { self }
    public var _specifier: String { "%u" }
}

extension UInt64: _FormatSpecifiable {
    public var _arg: UInt64 { self }
    public var _specifier: String { "%llu" }
}

extension Float: _FormatSpecifiable {
    public var _arg: Float { self }
    public var _specifier: String { "%f" }
}

extension Double: _FormatSpecifiable {
    public var _arg: Double { self }
    public var _specifier: String { "%lf" }
}

extension CGFloat: _FormatSpecifiable {
    public var _arg: CGFloat { self }
    public var _specifier: String { "%lf" }
}
