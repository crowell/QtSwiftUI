import QtBridge
import CoreGraphics

public struct StrokeStyle: Equatable, Sendable {
    public var lineWidth: CGFloat
    public var lineCap: CGLineCap
    public var lineJoin: CGLineJoin
    public var miterLimit: CGFloat
    public var dash: [CGFloat]
    public var dashPhase: CGFloat

    public init(lineWidth: CGFloat = 1, lineCap: CGLineCap = .butt, lineJoin: CGLineJoin = .miter,
                miterLimit: CGFloat = 10, dash: [CGFloat] = [], dashPhase: CGFloat = 0) {
        self.lineWidth = lineWidth
        self.lineCap = lineCap
        self.lineJoin = lineJoin
        self.miterLimit = miterLimit
        self.dash = dash
        self.dashPhase = dashPhase
    }

    func appendOutline(of source: OpaquePointer, to target: OpaquePointer) {
        let lengths = dash.map(Double.init)
        lengths.withUnsafeBufferPointer {
            qs_path_stroke(target, source, lineWidth, lineCap.rawValue, lineJoin.rawValue, miterLimit,
                           $0.baseAddress, $0.count, dashPhase)
        }
    }
}

extension Path {
    public func trimmedPath(from start: CGFloat, to end: CGFloat) -> Path {
        let from = start.isNaN ? 0 : start
        let to = end.isNaN ? 1 : end
        if from >= to || isEmpty { return Path() }
        if from <= 0 && to >= 1 { return self }
        var result = Path()
        result.commands = [.trimmed(self, from, to)]
        return result
    }
    public func strokedPath(_ style: StrokeStyle) -> Path {
        var result = Path()
        if !isEmpty && style.lineWidth > 0 { result.commands = [.stroked(self, style)] }
        return result
    }
}

private struct StrokedShape<Base: Shape>: AnimatedShape {
    let base: Base
    let style: StrokeStyle
    nonisolated func path(in rect: CGRect) -> Path { base.path(in: rect).strokedPath(style) }
    func renderedPath(in rect: CGRect, context: Context) -> Path {
        base.path(in: rect, context: context.descending(.position(0))).strokedPath(style)
    }
}

private struct TrimmedShape<Base: Shape>: AnimatedShape {
    let base: Base
    let from: CGFloat
    let to: CGFloat
    nonisolated func path(in rect: CGRect) -> Path { base.path(in: rect).trimmedPath(from: from, to: to) }
    func renderedPath(in rect: CGRect, context: Context) -> Path {
        base.path(in: rect, context: context.descending(.position(0)))
            .trimmedPath(from: context.interpolated(from, key: "trim start"), to: context.interpolated(to, key: "trim end"))
    }
}

extension Shape {
    public nonisolated func trim(from startFraction: CGFloat = 0, to endFraction: CGFloat = 1) -> some Shape {
        TrimmedShape(base: self, from: startFraction, to: endFraction)
    }
    public nonisolated func stroke(style: StrokeStyle) -> some Shape { StrokedShape(base: self, style: style) }
    public nonisolated func stroke(lineWidth: CGFloat = 1) -> some Shape { stroke(style: StrokeStyle(lineWidth: lineWidth)) }
    public func stroke<S: ShapeStyle>(_ content: S, style: StrokeStyle, antialiased: Bool = true) -> some View {
        stroke(style: style).fill(content, style: FillStyle(antialiased: antialiased))
    }
}

extension InsettableShape {
    public func strokeBorder<S: ShapeStyle>(_ content: S, style: StrokeStyle, antialiased: Bool = true) -> some View {
        inset(by: style.lineWidth / 2).stroke(content, style: style, antialiased: antialiased)
    }
    public func strokeBorder(style: StrokeStyle, antialiased: Bool = true) -> some View {
        Canvas { context, size in
            let outline = inset(by: style.lineWidth / 2).path(in: CGRect(origin: .zero, size: size)).strokedPath(style)
            context.fill(outline, with: .color(context.environment.foreground), style: FillStyle(antialiased: antialiased))
        }
    }
}
