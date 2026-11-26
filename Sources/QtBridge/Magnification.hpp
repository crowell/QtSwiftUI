#pragma once
#include "QtBridge.h"
#include <QElapsedTimer>
#include <QPointF>
#include <QSizeF>
#include <cmath>

// Qt supplies incremental factors for native gestures and total factors for touch pinches.
struct Magnification {
    double minimum = -1;
    bool tracking = false, recognized = false;
    double factor = 1;
    quint64 lastTick = 0;
    QSMagnifySample sample{};
    static quint64 now() {
        QElapsedTimer timer;
        timer.start();
        return timer.msecsSinceReference();
    }
    void begin(quint64 tick) {
        tracking = true;
        recognized = false;
        factor = 1;
        lastTick = tick;
        sample = {};
    }
    bool update(double next, QPointF local, QSize size, quint64 tick, bool ended) {
        if (!tracking || !std::isfinite(next) || next <= 0) return false;
        const double previous = factor;
        factor = next;
        const double velocity = tick > lastTick && next != previous
            ? (next - previous) * 1000 / double(tick - lastTick) : sample.velocity;
        lastTick = tick;
        if (ended) tracking = false;
        if (!recognized && (ended || std::abs(next - 1) < minimum || next == 1)) return false;
        if (!ended && recognized && next == previous) return false;
        recognized = true;
        sample = {tick / 1000.0, factor, velocity, local.x(), local.y(),
                  size.width() > 0 ? local.x() / size.width() : 0.5,
                  size.height() > 0 ? local.y() / size.height() : 0.5, int(ended)};
        return true;
    }
};
