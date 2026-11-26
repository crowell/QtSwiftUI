#pragma once

#include "QtBridge.h"
#include <QWidget>
#include <functional>

class NativePopover final : public QWidget {
public:
    NativePopover(QWidget *owner, std::function<void()> dismiss);
    QRect present(const QRectF &anchor, QSizeF content, QSPopoverEdge edge, bool dark);
    void disconnectDismissal() { dismissed = {}; }

protected:
    void hideEvent(QHideEvent *) override;
    void keyPressEvent(QKeyEvent *) override;
    void mousePressEvent(QMouseEvent *) override;
    void paintEvent(QPaintEvent *) override;

private:
    std::function<void()> dismissed;
    QSPopoverEdge edge = QSPopoverAbove;
    QPointF tip;
    bool dark = false;
};
