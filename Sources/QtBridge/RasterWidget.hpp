#pragma once
#include <QImage>
#include <QMarginsF>
#include <QWidget>

class RasterWidget final : public QWidget {
public:
    using QWidget::QWidget;
    QImage image;
    QMarginsF caps;
    double scale = 1;
    bool tile = false;
    bool smooth = true;
    void draw(QPainter &painter) const;
protected:
    void paintEvent(QPaintEvent *) override;
};
