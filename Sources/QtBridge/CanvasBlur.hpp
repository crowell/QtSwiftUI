#pragma once
#include <QImage>

struct CanvasBlur {
    double radius;
    unsigned blurOptions;
    unsigned filterOptions;
};

QImage gaussianBlur(QImage source, const CanvasBlur &filter, double scale);
