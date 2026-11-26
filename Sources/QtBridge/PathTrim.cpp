#include "PathTrim.hpp"
#include <QLineF>
#include <array>
#include <vector>

namespace {
struct Segment {
    QPainterPath curve;
    std::array<QPointF, 4> points;
    double length;
    bool cubic;
    bool beginsSubpath;

    // Evaluate the cubic derivative divided by three. Together with the end
    // points this gives the exact control points of any subinterval.
    QPointF tangent(double t) const {
        const double u = 1 - t;
        return u * u * (points[1] - points[0]) + 2 * u * t * (points[2] - points[1]) + t * t * (points[3] - points[2]);
    }
    void append(QPainterPath &result, double start, double end) const {
        const double t0 = start == 0 ? 0 : curve.percentAtLength(start);
        const double t1 = end == length ? 1 : curve.percentAtLength(end);
        const auto a = curve.pointAtPercent(t0), b = curve.pointAtPercent(t1);
        if (result.isEmpty() || beginsSubpath || result.currentPosition() != a) result.moveTo(a);
        if (cubic) result.cubicTo(a + (t1-t0) * tangent(t0), b - (t1-t0) * tangent(t1), b);
        else result.lineTo(b);
    }
};
}

QPainterPath trimmed(const QPainterPath &path, double start, double end) {
    if (end <= start || end <= 0 || start >= 1) return {};
    if (start <= 0 && end >= 1) return path;
    std::vector<Segment> segments;
    QPointF cursor;
    bool newSubpath = true;
    double length = 0;
    for (int index = 0; index < path.elementCount(); ++index) {
        const auto e = path.elementAt(index);
        if (e.isMoveTo()) {
            cursor = e;
            newSubpath = true;
            continue;
        }
        Segment segment{QPainterPath(cursor), {cursor, cursor, e, e}, 0, e.isCurveTo(), newSubpath};
        if (segment.cubic) {
            if (index + 2 >= path.elementCount()) break;
            segment.points[1] = e;
            segment.points[2] = path.elementAt(++index);
            segment.points[3] = path.elementAt(++index);
            segment.curve.cubicTo(segment.points[1], segment.points[2], segment.points[3]);
        } else {
            segment.curve.lineTo(e);
        }
        cursor = segment.points[3];
        segment.length = segment.curve.length();
        if (segment.length == 0) continue;
        length += segment.length;
        segments.push_back(segment);
        newSubpath = false;
    }
    const double from = qMax(0.0, start) * length, to = qMin(1.0, end) * length;
    QPainterPath result;
    double distance = 0;
    for (const auto &segment : segments) {
        const double a = qMax(0.0, from - distance), b = qMin(segment.length, to - distance);
        if (a < b) segment.append(result, a, b);
        distance += segment.length;
        if (distance >= to) break;
    }
    return result;
}
