#include "CanvasBlur.hpp"
#include <QColorSpace>
#include <array>
#include <cmath>
#include <vector>

namespace {
// The input and the intermediate image are premultiplied. Transparent pixels
// outside the image contribute zero, including at the edge of a Canvas.
QImage convolve(const QImage &input, const std::vector<double> &weights, bool horizontal, bool dither) {
    QImage result(input.size(), QImage::Format_RGBA64_Premultiplied);
    if (result.isNull()) return {};
    const int radius = int(weights.size()) - 1;
    const int extent = horizontal ? input.width() : input.height();
    static constexpr int bayer[4][4] = {{0,8,2,10},{12,4,14,6},{3,11,1,9},{15,7,13,5}};
    for (int y = 0; y < input.height(); ++y) {
        auto *row = reinterpret_cast<QRgba64 *>(result.scanLine(y));
        for (int x = 0; x < input.width(); ++x) {
            std::array<double, 4> sum{};
            const int pos = horizontal ? x : y;
            for (int k = qMax(-radius, -pos); k <= qMin(radius, extent - pos - 1); ++k) {
                const auto *line = reinterpret_cast<const QRgba64 *>(input.constScanLine(horizontal ? y : y + k));
                const auto pixel = line[horizontal ? x + k : x];
                const double weight = weights[std::abs(k)];
                sum[0] += weight * pixel.red();
                sum[1] += weight * pixel.green();
                sum[2] += weight * pixel.blue();
                sum[3] += weight * pixel.alpha();
            }
            const int alpha = qBound(0, qRound(sum[3]), 65535);
            const double noise = dither ? (bayer[y % 4][x % 4] / 16.0 - 0.46875) * 257.0 : 0.0;
            auto channel = [&](double v) { return qBound(0, qRound(v + noise * alpha / 65535.0), alpha); };
            row[x] = QRgba64::fromRgba64(channel(sum[0]), channel(sum[1]), channel(sum[2]), alpha);
        }
    }
    result.setColorSpace(input.colorSpace());
    return result;
}
}

QImage gaussianBlur(QImage source, const CanvasBlur &filter, double scale) {
    double sigma = filter.radius * scale;
    if (!std::isfinite(sigma) || sigma <= 0 || source.isNull()) return source;
    const QSize full = source.size();
    // Evaluate broad kernels at a lower resolution. This bounds the taps per
    // output pixel for window-sized effects.
    const double reduction = qBound(1.0, sigma / 8.0, double(qMax(full.width(), full.height())));
    if (reduction > 1) {
        source = source.scaled(qMax(1, qRound(full.width() / reduction)), qMax(1, qRound(full.height() / reduction)),
                               Qt::IgnoreAspectRatio, Qt::SmoothTransformation);
        sigma /= reduction;
    }
    source.setColorSpace(QColorSpace::SRgb);
    source = source.convertToFormat(QImage::Format_RGBA64_Premultiplied);
    if (filter.filterOptions & 1) source.convertToColorSpace(QColorSpace::SRgbLinear);
    const double support = std::ceil(3.5 * sigma);
    const int radius = int(qMin(support, double(qMax(source.width(), source.height()))));
    std::vector<double> weights(size_t(radius) + 1);
    double total = 0;
    for (int k = 0; k <= radius; ++k) {
        const double z = k / sigma;
        weights[k] = std::exp(-0.5 * z * z);
        total += (k == 0 ? 1 : 2) * weights[k];
    }
    if (radius < support) total = std::sqrt(2.0 * std::acos(-1.0)) * sigma;
    for (auto &weight : weights) weight /= total;
    QImage result = convolve(convolve(source, weights, true, false), weights, false, filter.blurOptions & 2);
    if (filter.filterOptions & 1) result.convertToColorSpace(QColorSpace::SRgb);
    if (filter.blurOptions & 1) {
        for (int y = 0; y < result.height(); ++y) {
            auto *row = reinterpret_cast<QRgba64 *>(result.scanLine(y));
            for (int x = 0; x < result.width(); ++x) {
                if (row[x].alpha() > 0) {
                    row[x] = row[x].unpremultiplied();
                    row[x].setAlpha(65535);
                }
            }
        }
    }
    if (result.size() != full) result = result.scaled(full, Qt::IgnoreAspectRatio, Qt::SmoothTransformation);
    return result;
}
