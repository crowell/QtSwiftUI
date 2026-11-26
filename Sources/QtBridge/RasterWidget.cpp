#include "QtBridge.h"
#include "RasterWidget.hpp"
#include <QPainter>
#include <QVariant>
#include <algorithm>
#include <array>

namespace {
// Cap insets are measured in points. Preserve their proportions if the destination
// is smaller than the two caps together.
std::array<double, 4> cuts(double length, double before, double after) {
    const double total = before + after;
    const double factor = total > length ? length / total : 1;
    return {0, before * factor, length - after * factor, length};
}

QImage readPixels(const unsigned char *bytes, int width, int height, qsizetype stride, int alpha, bool little) {
    // CGImageAlphaInfo's first/last component is in word order for a 32-bit pixel.
    if (!little && (alpha == 0 || alpha == 1 || alpha == 3)) {
        const auto format = alpha == 0 ? QImage::Format_RGB888 :
                            alpha == 1 ? QImage::Format_RGBA8888_Premultiplied : QImage::Format_RGBA8888;
        return QImage(bytes, width, height, stride, format).copy();
    }
    const bool first = alpha == 2 || alpha == 4 || alpha == 6;
    const bool padding = alpha == 5 || alpha == 6;
    QImage result(width, height, alpha == 1 || alpha == 2 ? QImage::Format_ARGB32_Premultiplied : QImage::Format_ARGB32);
    if (result.isNull()) return result;
    const int red = first ? 1 : 0;
    for (int y = 0; y < height; ++y) {
        const auto *pixel = bytes + y * stride;
        auto *row = reinterpret_cast<QRgb *>(result.scanLine(y));
        for (int x = 0; x < width; ++x, pixel += 4) {
            auto component = [&](int i) { return pixel[little ? 3 - i : i]; };
            row[x] = qRgba(component(red), component(red + 1), component(red + 2), padding ? 255 : component(first ? 0 : 3));
        }
    }
    return result;
}
}

void qs_raster_image(QSWidget w, const unsigned char *bytes, int width, int height, size_t stride,
                     int alpha, int little, int orientation, double scale, int smooth) {
    auto *view = static_cast<RasterWidget *>(w);
    auto image = readPixels(bytes, width, height, stride, alpha, little);
    // SwiftUI.Image.Orientation raw values, including the two transposed orientations.
    switch (orientation) {
    case 1: image = image.mirrored(true, false); break;
    case 2: image = image.mirrored(true, true); break;
    case 3: image = image.mirrored(false, true); break;
    case 4: image = image.transformed(QTransform().rotate(-90)); break;
    case 5: image = image.transformed(QTransform().rotate(90)).mirrored(true, false); break;
    case 6: image = image.transformed(QTransform().rotate(90)); break;
    case 7: image = image.transformed(QTransform().rotate(-90)).mirrored(true, false); break;
    }
    view->image = std::move(image);
    view->scale = scale;
    view->smooth = smooth;
    view->update();
}
void qs_raster_resize(QSWidget w, double left, double top, double right, double bottom, int tile) {
    auto *view = static_cast<RasterWidget *>(w);
    view->caps = QMarginsF(left, top, right, bottom);
    view->tile = tile;
}

void RasterWidget::paintEvent(QPaintEvent *) {
    if (image.isNull()) return;
    QPainter painter(this);
    painter.translate(property("qsFraction").toPointF());
    painter.setRenderHint(QPainter::SmoothPixmapTransform, smooth);
    const auto size = property("qsSize").toSizeF();
    if (caps.isNull() && !tile) {
        painter.drawImage(QRectF(QPointF(), size), image);
        return;
    }
    const auto sx = cuts(image.width(), caps.left() * scale, caps.right() * scale);
    const auto sy = cuts(image.height(), caps.top() * scale, caps.bottom() * scale);
    const auto dx = cuts(size.width(), sx[1] / scale, (sx[3] - sx[2]) / scale);
    const auto dy = cuts(size.height(), sy[1] / scale, (sy[3] - sy[2]) / scale);
    for (int y = 0; y < 3; ++y) {
        for (int x = 0; x < 3; ++x) {
            const QRectF src(sx[x], sy[y], sx[x+1] - sx[x], sy[y+1] - sy[y]);
            const QRectF dst(dx[x], dy[y], dx[x+1] - dx[x], dy[y+1] - dy[y]);
            if (src.isEmpty() || dst.isEmpty()) continue;
            if (!tile || (x != 1 && y != 1)) {
                painter.drawImage(dst, image, src);
            } else {
                const QImage patch = image.copy(src.toRect());
                if (patch.isNull()) continue;
                QBrush brush(patch);
                QTransform transform;
                transform.translate(dst.x(), dst.y());
                transform.scale((x == 1 ? src.width() / scale : dst.width()) / patch.width(),
                                (y == 1 ? src.height() / scale : dst.height()) / patch.height());
                brush.setTransform(transform);
                painter.fillRect(dst, brush);
            }
        }
    }
}
