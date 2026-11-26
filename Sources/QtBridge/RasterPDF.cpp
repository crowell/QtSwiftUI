#include "RasterWidget.hpp"
#include <QBuffer>
#include <QPageSize>
#include <QPainter>
#include <QPdfWriter>
#include <cmath>

int qs_raster_pdf(QSRasterImage source, double pageWidth, double pageHeight, void *context, QSDataBytes receive) {
    if (!std::isfinite(pageWidth) || !std::isfinite(pageHeight) || pageWidth <= 0 || pageHeight <= 0) return 0;
    RasterContent content(source);
    if (content.image.isNull()) return 0;
    QBuffer buffer;
    if (!buffer.open(QIODevice::WriteOnly)) return 0;
    {
        QPdfWriter writer(&buffer);
        writer.setResolution(72);
        const QPageSize page(QSizeF(pageWidth, pageHeight), QPageSize::Point, QString(), QPageSize::ExactMatch);
        if (!writer.setPageSize(page) || !writer.setPageMargins(QMarginsF(), QPageLayout::Point)) return 0;
        QPainter painter(&writer);
        if (!painter.isActive()) return 0;
        painter.setRenderHint(QPainter::LosslessImageRendering);
        painter.drawImage(QRectF(0, 0, pageWidth, pageHeight), content.image);
        if (!painter.end()) return 0;
    }
    const auto &bytes = buffer.data();
    if (bytes.isEmpty()) return 0;
    receive(context, reinterpret_cast<const unsigned char *>(bytes.constData()), size_t(bytes.size()));
    return 1;
}
