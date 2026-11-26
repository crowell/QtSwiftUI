#pragma once
#include <functional>
#include <QImage>
#include <QWidget>

// A window-relative sample converted to the material widget's local coordinates.
struct MaterialBackdrop {
    QImage pixels;
    QRect region;
    static MaterialBackdrop read(QWidget *surface, double radius, QColor tint,
                                 const std::function<void(QPainter &)> &paintBelow = {});
};
