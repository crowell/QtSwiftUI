#pragma once
#include "QtBridge.h"
#include <QImage>
#include <QMarginsF>
#include <QWidget>

struct RasterContent {
    explicit RasterContent(QSRasterImage);
    RasterContent() = default;
    void draw(QPainter &painter, QSizeF size) const;
    QImage image;
    QMarginsF caps;
    double scale = 1;
    bool tile = false;
    bool smooth = true;
};

class RasterWidget final : public QWidget {
public:
    using QWidget::QWidget;
    RasterContent content;
    void draw(QPainter &painter) const;
protected:
    void paintEvent(QPaintEvent *) override;
};
