#pragma once
#include "CanvasBlur.hpp"
#include <QGraphicsEffect>
#include <QPainter>
#include <cmath>

class ViewBlur final : public QGraphicsEffect {
public:
    void configure(double value, bool isOpaque) {
        if (radius == value && opaque == isOpaque) return;
        radius = value;
        opaque = isOpaque;
        updateBoundingRect();
        update();
    }
protected:
    QRectF boundingRectFor(const QRectF &rect) const override {
        const qreal margin = std::ceil(3.5 * radius);
        return rect.adjusted(-margin, -margin, margin, margin);
    }
    void draw(QPainter *painter) override {
        QPoint offset;
        const auto source = sourcePixmap(Qt::LogicalCoordinates, &offset, PadToEffectiveBoundingRect);
        if (source.isNull()) return;
        auto result = gaussianBlur(source.toImage(), {radius, opaque ? 1u : 0u, 0}, source.devicePixelRatio());
        result.setDevicePixelRatio(source.devicePixelRatio());
        painter->drawImage(offset, result);
    }
private:
    double radius = 0;
    bool opaque = false;
};
