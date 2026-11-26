#pragma once
#include <QAbstractScrollArea>
#include <QKeyEvent>
#include <QScrollArea>
#include <QScrollBar>
#include <QScroller>

class ScrollInput final : public QObject {
public:
    explicit ScrollInput(QAbstractScrollArea *area) : QObject(area), area(area) {
        for (QWidget *target : {static_cast<QWidget *>(area), area->viewport(),
                                 static_cast<QWidget *>(area->horizontalScrollBar()),
                                 static_cast<QWidget *>(area->verticalScrollBar())}) target->installEventFilter(this);
        QScroller::grabGesture(area->viewport(), QScroller::TouchGesture);
    }

    void setEnabled(bool value) {
        if (enabled == value) return;
        enabled = value;
        if (enabled) QScroller::grabGesture(area->viewport(), QScroller::TouchGesture);
        else {
            QScroller::scroller(area->viewport())->stop();
            QScroller::ungrabGesture(area->viewport());
        }
    }

protected:
    bool eventFilter(QObject *target, QEvent *event) override {
        if (enabled) return false;
        switch (event->type()) {
        case QEvent::Wheel:
        case QEvent::ScrollPrepare:
        case QEvent::Scroll:
            event->ignore();
            return true;
        case QEvent::MouseButtonPress:
        case QEvent::MouseButtonDblClick:
        case QEvent::MouseButtonRelease:
        case QEvent::MouseMove:
            return qobject_cast<QScrollBar *>(target) != nullptr;
        case QEvent::KeyPress:
            if (qobject_cast<QScrollBar *>(target)) return true;
            if (target == area && qobject_cast<QScrollArea *>(area)) {
                switch (static_cast<QKeyEvent *>(event)->key()) {
                case Qt::Key_Left: case Qt::Key_Right: case Qt::Key_Up: case Qt::Key_Down:
                case Qt::Key_PageUp: case Qt::Key_PageDown: case Qt::Key_Home: case Qt::Key_End:
                    event->ignore();
                    return true;
                }
            }
            break;
        default: break;
        }
        return false;
    }
private:
    QAbstractScrollArea *area;
    bool enabled = true;
};
