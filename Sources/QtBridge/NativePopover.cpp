#include "NativePopover.hpp"
#include <QApplication>
#include <QHideEvent>
#include <QKeyEvent>
#include <QMouseEvent>
#include <QPainter>
#include <QPainterPath>
#include <QScreen>
#include <QtMath>

namespace {
constexpr int margin = 13;
constexpr int arrow = 8;
constexpr int radius = 9;

QSPopoverEdge opposite(QSPopoverEdge edge) {
    switch (edge) {
    case QSPopoverAbove: return QSPopoverBelow;
    case QSPopoverBelow: return QSPopoverAbove;
    case QSPopoverLeft: return QSPopoverRight;
    case QSPopoverRight: return QSPopoverLeft;
    }
    return QSPopoverAbove;
}

QRect placed(QSPopoverEdge edge, const QRectF &anchor, QSize size) {
    const QPointF center = anchor.center();
    QPointF origin(center.x() - size.width() / 2.0, center.y() - size.height() / 2.0);
    switch (edge) {
    case QSPopoverAbove: origin.setY(anchor.top() - size.height()); break;
    case QSPopoverBelow: origin.setY(anchor.bottom()); break;
    case QSPopoverLeft: origin.setX(anchor.left() - size.width()); break;
    case QSPopoverRight: origin.setX(anchor.right()); break;
    }
    return QRect(origin.toPoint(), size);
}
}

NativePopover::NativePopover(QWidget *owner, std::function<void()> dismiss)
    : QWidget(owner, Qt::Popup | Qt::FramelessWindowHint), dismissed(std::move(dismiss)) {
    setAttribute(Qt::WA_TranslucentBackground);
    setFocusPolicy(Qt::StrongFocus);
    setAccessibleName(QStringLiteral("Popover"));
}

QRect NativePopover::present(const QRectF &anchor, QSizeF content, QSPopoverEdge requested, bool darkMode) {
    QScreen *screen = QApplication::screenAt(anchor.center().toPoint());
    if (!screen) screen = parentWidget()->screen();
    const QRect available = screen->availableGeometry();
    const auto extent = [](qreal requested, int limit) {
        return qMin(limit, qCeil(qBound(0.0, requested, qreal(limit))) + 2 * margin);
    };
    const QSize size(extent(content.width(), available.width()), extent(content.height(), available.height()));
    auto bounds = placed(requested, anchor, size);
    const auto alternative = placed(opposite(requested), anchor, size);
    const auto visibleArea = [&](QRect rect) {
        rect = rect.intersected(available);
        return qint64(rect.width()) * rect.height();
    };
    edge = requested;
    if (visibleArea(alternative) > visibleArea(bounds)) {
        edge = opposite(requested);
        bounds = alternative;
    }
    bounds.moveLeft(qBound(available.left(), bounds.left(), available.right() - size.width() + 1));
    bounds.moveTop(qBound(available.top(), bounds.top(), available.bottom() - size.height() + 1));
    dark = darkMode;
    tip = anchor.center() - bounds.topLeft();
    setGeometry(bounds);
    if (!isVisible()) show();
    update();
    return rect().adjusted(margin, margin, -margin, -margin);
}

void qs_popover_dismiss_disabled(QSWidget popup, int disabled) {
    static_cast<NativePopover *>(popup)->setProperty("qsDismissDisabled", bool(disabled));
}
void NativePopover::closeEvent(QCloseEvent *event) {
    if (property("qsDismissDisabled").toBool()) event->ignore();
    else QWidget::closeEvent(event);
}
void NativePopover::hideEvent(QHideEvent *event) {
    QWidget::hideEvent(event);
    if (dismissed) dismissed();
}
void NativePopover::keyPressEvent(QKeyEvent *event) {
    if (event->key() == Qt::Key_Escape) { close(); event->accept(); }
    else QWidget::keyPressEvent(event);
}
void NativePopover::mousePressEvent(QMouseEvent *event) {
    if (!rect().contains(event->position().toPoint())) { close(); event->accept(); }
    else QWidget::mousePressEvent(event);
}
void NativePopover::paintEvent(QPaintEvent *) {
    QRectF panel = QRectF(rect()).adjusted(1, 1, -1, -1);
    QPolygonF pointer;
    if (edge == QSPopoverAbove || edge == QSPopoverBelow) {
        const bool below = edge == QSPopoverBelow;
        if (below) panel.adjust(0, arrow, 0, 0); else panel.adjust(0, 0, 0, -arrow);
        const qreal x = qBound(qreal(margin), tip.x(), qreal(width() - margin));
        const qreal y = below ? panel.top() : panel.bottom();
        pointer << QPointF(x - arrow, y) << QPointF(x, below ? 1 : height() - 1) << QPointF(x + arrow, y);
    } else {
        const bool right = edge == QSPopoverRight;
        if (right) panel.adjust(arrow, 0, 0, 0); else panel.adjust(0, 0, -arrow, 0);
        const qreal y = qBound(qreal(margin), tip.y(), qreal(height() - margin));
        const qreal x = right ? panel.left() : panel.right();
        pointer << QPointF(x, y - arrow) << QPointF(right ? 1 : width() - 1, y) << QPointF(x, y + arrow);
    }
    QPainterPath outline, triangle;
    outline.addRoundedRect(panel, radius, radius);
    triangle.addPolygon(pointer);
    QPainter painter(this);
    painter.setRenderHint(QPainter::Antialiasing);
    painter.setBrush(dark ? QColor(52, 52, 52) : QColor(250, 250, 250));
    painter.setPen(dark ? QColor(100, 100, 100) : QColor(180, 180, 180));
    painter.drawPath(outline.united(triangle));
}
