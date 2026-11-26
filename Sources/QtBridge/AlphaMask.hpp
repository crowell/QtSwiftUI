#pragma once
#include <QGraphicsEffect>
#include <QPainter>
#include <QPointer>
#include <QWidget>

// QWidget::render also paints an explicitly hidden widget and its visible children.
class AlphaMaskEffect final : public QGraphicsEffect {
public:
    explicit AlphaMaskEffect(QWidget *stencil) : stencil(stencil) {}

protected:
    void draw(QPainter *painter) override {
        if (!stencil || stencil->size().isEmpty()) return;
        QPoint offset;
        const QPixmap source = sourcePixmap(Qt::LogicalCoordinates, &offset, NoPad);
        if (source.isNull()) return;
        QImage image = source.toImage().convertToFormat(QImage::Format_ARGB32_Premultiplied);
        QImage alpha(image.size(), QImage::Format_ARGB32_Premultiplied);
        alpha.setDevicePixelRatio(image.devicePixelRatio());
        alpha.fill(Qt::transparent);
        stencil->render(&alpha, -offset, {}, QWidget::DrawChildren);
        QPainter blend(&image);
        blend.setCompositionMode(QPainter::CompositionMode_DestinationIn);
        blend.drawImage(QPointF(), alpha);
        blend.end();
        painter->drawImage(offset, image);
    }

private:
    QPointer<QWidget> stencil;
};
