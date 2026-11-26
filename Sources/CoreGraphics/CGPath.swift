import Foundation
import QtBridge

public class CGPath {
    @_spi(Qt) public enum Segment: Equatable, Sendable {
        case move(CGPoint), line(CGPoint), quadratic(CGPoint, CGPoint), cubic(CGPoint, CGPoint, CGPoint), close
    }
    @_spi(Qt) public fileprivate(set) var segments: [Segment]
    fileprivate init(_ segments: [Segment]) { self.segments = segments }
    public var isEmpty: Bool { segments.isEmpty }
    public func copy() -> CGPath? { CGPath(segments) }
    public func mutableCopy() -> CGMutablePath? { CGMutablePath(segments) }

    private func withNativePath<T>(_ body: (OpaquePointer) -> T) -> T {
        let path = qs_path_new()!
        defer { qs_path_delete(path) }
        for segment in segments {
            switch segment {
            case .move(let p): qs_path_step(path, 0, p.x, p.y, 0, 0, 0, 0)
            case .line(let p): qs_path_step(path, 1, p.x, p.y, 0, 0, 0, 0)
            case .quadratic(let p, let a): qs_path_step(path, 2, a.x, a.y, p.x, p.y, 0, 0)
            case .cubic(let p, let a, let b): qs_path_step(path, 3, a.x, a.y, b.x, b.y, p.x, p.y)
            case .close: qs_path_step(path, 4, 0, 0, 0, 0, 0, 0)
            }
        }
        return body(path)
    }

    public var boundingBoxOfPath: CGRect {
        let box = withNativePath(qs_path_bounds)
        return box.width < 0 ? .null : CGRect(x: box.x, y: box.y, width: box.width, height: box.height)
    }
    public var boundingBox: CGRect {
        // Qt converts quadratic segments to cubic curves, changing their control points.
        var bounds = CGRect.null
        func include(_ p: CGPoint) { bounds = bounds.union(CGRect(origin: p, size: .zero)) }
        for segment in segments {
            switch segment {
            case .move(let p), .line(let p): include(p)
            case .quadratic(let p, let c): include(p); include(c)
            case .cubic(let p, let a, let b): include(p); include(a); include(b)
            case .close: break
            }
        }
        return bounds
    }
    public var currentPoint: CGPoint {
        guard !isEmpty else { return .zero }
        let position = withNativePath(qs_path_position)
        return CGPoint(x: position.width, y: position.height)
    }
}

public final class CGMutablePath: CGPath {
    public init() { super.init([]) }
    fileprivate override init(_ segments: [Segment]) { super.init(segments) }

    public func move(to end: CGPoint, transform: CGAffineTransform = .identity) {
        if case .move? = segments.last { segments.removeLast() }
        segments.append(.move(end.applying(transform)))
    }
    public func addLine(to end: CGPoint, transform: CGAffineTransform = .identity) {
        guard !segments.isEmpty else { return }
        segments.append(.line(end.applying(transform)))
    }
    public func addQuadCurve(to end: CGPoint, control: CGPoint, transform: CGAffineTransform = .identity) {
        guard !segments.isEmpty else { return }
        segments.append(.quadratic(end.applying(transform), control.applying(transform)))
    }
    public func addCurve(to end: CGPoint, control1: CGPoint, control2: CGPoint, transform: CGAffineTransform = .identity) {
        guard !segments.isEmpty else { return }
        segments.append(.cubic(end.applying(transform), control1.applying(transform), control2.applying(transform)))
    }
    public func closeSubpath() {
        guard !segments.isEmpty, segments.last != .close else { return }
        segments.append(.close)
    }
    public func addRect(_ rect: CGRect, transform: CGAffineTransform = .identity) {
        move(to: CGPoint(x: rect.minX, y: rect.minY), transform: transform)
        addLine(to: CGPoint(x: rect.maxX, y: rect.minY), transform: transform)
        addLine(to: CGPoint(x: rect.maxX, y: rect.maxY), transform: transform)
        addLine(to: CGPoint(x: rect.minX, y: rect.maxY), transform: transform)
        closeSubpath()
    }
    public func addEllipse(in rect: CGRect, transform: CGAffineTransform = .identity) {
        let cx = rect.midX, cy = rect.midY, rx = rect.width / 2, ry = rect.height / 2
        let k = 4 * (sqrt(2.0) - 1) / 3
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: cx + rx * x, y: cy + ry * y).applying(transform) }
        move(to: point(1, 0))
        addCurve(to: point(0, 1), control1: point(1, k), control2: point(k, 1))
        addCurve(to: point(-1, 0), control1: point(-k, 1), control2: point(-1, k))
        addCurve(to: point(0, -1), control1: point(-1, -k), control2: point(-k, -1))
        addCurve(to: point(1, 0), control1: point(k, -1), control2: point(1, -k))
        closeSubpath()
    }
    public func addPath(_ path: CGPath, transform: CGAffineTransform = .identity) {
        for segment in path.segments {
            switch segment {
            case .move(let p): move(to: p, transform: transform)
            case .line(let p): addLine(to: p, transform: transform)
            case .quadratic(let p, let c): addQuadCurve(to: p, control: c, transform: transform)
            case .cubic(let p, let a, let b): addCurve(to: p, control1: a, control2: b, transform: transform)
            case .close: closeSubpath()
            }
        }
    }
}
