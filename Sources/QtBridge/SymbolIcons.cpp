#include "SymbolIcons.hpp"
#include "QtBridge.h"
#include <QPainter>
#include <QPixmapCache>
#include <cmath>

QIcon systemSymbol(const QString &name, int extent, QColor ink) {
    if (extent <= 0 || extent > 1024) return {};
    const bool star = name == "star" || name == "star.fill" || name == "star.slash";
    const bool speaker = name == "speaker.wave.2.fill";
    if (!star && !speaker) return {};
    const auto key = QStringLiteral("qs.symbol.%1.%2.%3").arg(name).arg(extent).arg(ink.rgba());
    QPixmap pixmap;
    if (QPixmapCache::find(key, &pixmap)) return QIcon(pixmap);
    pixmap = QPixmap(extent, extent);
    pixmap.fill(Qt::transparent);
    QPainter painter(&pixmap);
    painter.setRenderHint(QPainter::Antialiasing);
    painter.scale(extent / 24.0, extent / 24.0);
    painter.setPen(QPen(ink, 1.8, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin));
    if (star) {
        QPolygonF points;
        for (int i = 0; i < 10; ++i) {
            const auto angle = (i / 5.0 - 0.5) * std::acos(-1.0);
            const auto radius = i % 2 ? 4.7 : 10.3;
            points << QPointF(12 + radius * std::cos(angle), 12.4 + radius * std::sin(angle));
        }
        if (name == "star.fill") painter.setBrush(ink);
        painter.drawPolygon(points);
        if (name == "star.slash") painter.drawLine(QPointF(2, 2), QPointF(22, 22));
    } else {
        painter.setBrush(ink);
        painter.drawPolygon(QPolygonF{{2,9},{6,9},{12,4},{12,20},{6,15},{2,15}});
        painter.setBrush(Qt::NoBrush);
        painter.drawArc(QRectF(4, 6, 13, 12), -42 * 16, 84 * 16);
        painter.drawArc(QRectF(0, 2, 22, 20), -42 * 16, 84 * 16);
    }
    painter.end();
    QPixmapCache::insert(key, pixmap);
    return QIcon(pixmap);
}

int qs_symbol_image(const char *name, int extent, unsigned foreground, void *context, QSImageBytes receive) {
    const auto icon = systemSymbol(QString::fromUtf8(name), extent, QColor::fromRgba(foreground));
    if (icon.isNull()) return 0;
    const auto image = icon.pixmap(extent, extent).toImage().convertToFormat(QImage::Format_RGBA8888);
    if (image.width() != extent || image.height() != extent) return 0;
    receive(context, image.constBits(), image.sizeInBytes(), image.bytesPerLine());
    return 1;
}
