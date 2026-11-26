#pragma once
#include "CanvasBlur.hpp"
#include <QGraphicsEffect>
#include <QPainter>
#include <cmath>

class ViewShadow final : public QGraphicsEffect {
public:
    void configure(QColor tint, double blur, QPointF delta) {
        if (tint == color && radius == blur && delta == displacement) return;
        color = tint;
        radius = blur;
        displacement = delta;
        updateBoundingRect();
        update();
    }
protected:
    QRectF boundingRectFor(const QRectF &rect) const override {
        const auto pad = std::ceil(3.5 * radius);
        return rect.united(rect.adjusted(-pad, -pad, pad, pad).translated(displacement));
    }
    void draw(QPainter *painter) override {
        QPoint origin;
        const auto source = sourcePixmap(Qt::LogicalCoordinates, &origin, NoPad);
        if (source.isNull()) return;
        const qreal scale = source.devicePixelRatio();
        const int pad = qCeil(3.5 * radius * scale);
        QImage silhouette(source.size() + QSize(2 * pad, 2 * pad), QImage::Format_ARGB32_Premultiplied);
        silhouette.setDevicePixelRatio(scale);
        silhouette.fill(Qt::transparent);
        const QPointF inset(pad / scale, pad / scale);
        {
            QPainter mask(&silhouette);
            mask.drawPixmap(inset, source);
            mask.setCompositionMode(QPainter::CompositionMode_SourceIn);
            mask.fillRect(QRectF(QPointF(), silhouette.deviceIndependentSize()), color);
        }
        if (radius > 0) silhouette = gaussianBlur(silhouette, {radius, 0, 0}, scale);
        silhouette.setDevicePixelRatio(scale);
        painter->drawImage(QPointF(origin) + displacement - inset, silhouette);
        painter->drawPixmap(origin, source);
    }
private:
    QColor color;
    double radius = 0;
    QPointF displacement;
};
