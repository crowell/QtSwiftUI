@_spi(Qt) import CoreGraphics
import QtBridge

extension Path {
    @frozen public enum Element: Equatable, Sendable {
        case move(to: CGPoint)
        case line(to: CGPoint)
        case quadCurve(to: CGPoint, control: CGPoint)
        case curve(to: CGPoint, control1: CGPoint, control2: CGPoint)
        case closeSubpath
    }

    public init(_ path: CGMutablePath) { self.init(path as CGPath) }
    public init(_ path: CGPath) {
        self.init()
        for segment in path.segments {
            switch segment {
            case .move(let p): move(to: p)
            case .line(let p): addLine(to: p)
            case .quadratic(let p, let c): addQuadCurve(to: p, control: c)
            case .cubic(let p, let a, let b): addCurve(to: p, control1: a, control2: b)
            case .close: closeSubpath()
            }
        }
    }

    public var cgPath: CGPath {
        let result = CGMutablePath()
        append(to: result, transform: .identity)
        return result.copy()!
    }
    private func append(to result: CGMutablePath, transform: CGAffineTransform) {
        for command in commands {
            switch command {
            case .move(let p): result.move(to: p, transform: transform)
            case .line(let p): result.addLine(to: p, transform: transform)
            case .quad(let c, let p): result.addQuadCurve(to: p, control: c, transform: transform)
            case .cubic(let a, let b, let p): result.addCurve(to: p, control1: a, control2: b, transform: transform)
            case .close: result.closeSubpath()
            case .rect(let rect): result.addRect(rect, transform: transform)
            case .ellipse(let rect): result.addEllipse(in: rect, transform: transform)
            case .transformed(let path, let matrix): path.append(to: result, transform: matrix.concatenating(transform))
            case .stroked, .trimmed:
                let closed: Int32 = if case .stroked = command { 1 } else { 0 }
                let output = CGMutablePath()
                var shape = Path()
                shape.commands = [command]
                shape.withNativePath { native in
                    qs_path_visit(native, closed, Unmanaged.passUnretained(output).toOpaque()) { raw, op, x, y, a, b, c, d in
                        let output = Unmanaged<CGMutablePath>.fromOpaque(raw!).takeUnretainedValue()
                        let end = CGPoint(x: x, y: y)
                        switch op {
                        case 0: output.move(to: end)
                        case 1: output.addLine(to: end)
                        case 3: output.addCurve(to: end, control1: CGPoint(x: a, y: b), control2: CGPoint(x: c, y: d))
                        default: output.closeSubpath()
                        }
                    }
                }
                result.addPath(output, transform: transform)
            }
        }
    }

    public func forEach(_ body: (Element) -> Void) {
        for segment in cgPath.segments {
            switch segment {
            case .move(let p): body(.move(to: p))
            case .line(let p): body(.line(to: p))
            case .quadratic(let p, let c): body(.quadCurve(to: p, control: c))
            case .cubic(let p, let a, let b): body(.curve(to: p, control1: a, control2: b))
            case .close: body(.closeSubpath)
            }
        }
    }
}
