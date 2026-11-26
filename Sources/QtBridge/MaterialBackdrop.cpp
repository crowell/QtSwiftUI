#include "MaterialBackdrop.hpp"
#include "CanvasBlur.hpp"
#include <QPainter>
#include <cmath>

MaterialBackdrop MaterialBackdrop::read(QWidget *surface, double radius, QColor tint, const std::function<void(QPainter &)> &paintBelow) {
    auto *window = surface->window();
    const QPoint origin = surface->mapTo(window, QPoint());
    QRect visible(origin, surface->size());
    QList<QWidget *> ancestors;
    for (auto *parent = surface->parentWidget(); parent; parent = parent->parentWidget()) {
        ancestors.prepend(parent);
        visible &= QRect(parent->mapTo(window, QPoint()), parent->size());
        if (parent == window) break;
    }
    if (visible.isEmpty() || ancestors.isEmpty()) return {};
    const int padding = qCeil(3.5 * radius);
    const QRect sample = visible.adjusted(-padding, -padding, padding, padding).intersected(window->rect());
    // These broad kernels discard fine detail. Sample at half resolution before
    // convolution so even a full-window sheet has bounded intermediate storage.
    const double scale = 0.5;
    QImage image(qCeil(sample.width() * scale), qCeil(sample.height() * scale), QImage::Format_ARGB32_Premultiplied);
    if (image.isNull()) return {};
    image.fill(window->palette().color(QPalette::Window));
    {
        QPainter painter(&image);
        painter.scale(scale, scale);
        painter.translate(-sample.topLeft());
        for (int level = 0; level < ancestors.size(); ++level) {
            auto *parent = ancestors[level];
            auto *branch = level + 1 == ancestors.size() ? surface : ancestors[level + 1];
            const auto at = parent->mapTo(window, QPoint());
            painter.setClipRect(QRect(at, parent->size()), Qt::IntersectClip);
            if (!parent->mask().isEmpty()) painter.setClipRegion(parent->mask().translated(at), Qt::IntersectClip);
            // QWidget children are in paint order, including changes from raise().
            // Render only the parent's own paint and siblings below our branch.
            parent->render(&painter, at, {}, parent == window ? QWidget::DrawWindowBackground : QWidget::RenderFlags{});
            for (auto *object : parent->children()) {
                if (object == branch) break;
                auto *sibling = qobject_cast<QWidget *>(object);
                if (!sibling || sibling->isWindow() || sibling->isHidden()) continue;
                const QRect bounds(sibling->mapTo(window, QPoint()), sibling->size());
                if (bounds.intersects(sample))
                    sibling->render(&painter, bounds.topLeft(), {}, QWidget::DrawChildren);
            }
        }
        if (paintBelow) {
            painter.translate(origin);
            paintBelow(painter);
        }
    }
    image = gaussianBlur(std::move(image), {radius, 1, 0}, scale);
    if (image.isNull()) return {};
    {
        QPainter painter(&image);
        painter.fillRect(image.rect(), tint);
    }
    return {std::move(image), sample.translated(-origin)};
}
