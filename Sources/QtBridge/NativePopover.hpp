#pragma once

#include "QtBridge.h"
#include <QPainterPath>
#include <QWidget>
#include <functional>

class NativePopover final : public QWidget {
public:
    NativePopover(QWidget *owner, std::function<void()> dismiss);
    QRect present(const QRectF &anchor, QSizeF content, QSPopoverEdge edge, bool dark);
    void disconnectDismissal() { dismissed = {}; }

protected:
    void closeEvent(QCloseEvent *) override;
    void hideEvent(QHideEvent *) override;
    void keyPressEvent(QKeyEvent *) override;
    void mousePressEvent(QMouseEvent *) override;
    void paintEvent(QPaintEvent *) override;

private:
    std::function<void()> dismissed;
    QSPopoverEdge edge = QSPopoverAbove;
    QPointF tip;
    QPainterPath outline;
    QPainterPath panelOutline() const;
    bool dark = false;
};
