#pragma once
#include "QtBridge.h"
#include <QDateTime>
#include <QElapsedTimer>
#include <QMouseEvent>
#include <cmath>
#include <optional>

// Coordinates are window-relative so a view can move while it owns the pointer.
struct PointerDrag {
    double threshold = -1;
    bool tracking = false, recognized = false;
    QPointF start, last, velocity;
    quint64 startTick = 0, lastTick = 0;
    double startTime = 0;
    QElapsedTimer elapsed;

    std::optional<QSDragSample> update(const QMouseEvent &event, QPointF point, bool inside) {
        const bool press = event.type() == QEvent::MouseButtonPress || event.type() == QEvent::MouseButtonDblClick;
        const bool release = event.type() == QEvent::MouseButtonRelease;
        if (press) {
            if (tracking || !inside || event.button() != Qt::LeftButton) return {};
            tracking = true;
            recognized = false;
            start = last = point;
            velocity = {};
            startTick = lastTick = event.timestamp();
            startTime = QDateTime::currentMSecsSinceEpoch() / 1000.0;
            elapsed.start();
        } else if (!tracking || (release && event.button() != Qt::LeftButton)) {
            return {};
        }
        const quint64 tick = event.timestamp() ? event.timestamp() : startTick + elapsed.elapsed();
        const auto distance = point - start;
        const bool moved = point != last;
        if (moved && tick > lastTick) velocity = (point - last) * (1000.0 / (tick - lastTick));
        if (!moved && tick > lastTick + 100) velocity = {};
        if (moved) { lastTick = tick; last = point; }
        if (release) tracking = false;
        if (!recognized && std::hypot(distance.x(), distance.y()) < threshold) return {};
        if (!press && !release && !moved && recognized) return {};
        if (release && !recognized) return {};
        recognized = true;
        return QSDragSample{startTime + double(tick - startTick) / 1000.0, start.x(), start.y(),
                            point.x(), point.y(), velocity.x(), velocity.y(), int(release)};
    }
};
