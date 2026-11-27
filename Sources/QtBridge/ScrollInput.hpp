#pragma once
#include <QAbstractScrollArea>
#include <QKeyEvent>
#include <QScrollArea>
#include <QScrollBar>
#include <QScroller>
#include <QTimer>
#include <QWheelEvent>
#include <deque>
#include <functional>
#include "QtBridge.h"

class ScrollInput final : public QObject {
public:
    explicit ScrollInput(QAbstractScrollArea *area, std::function<void()> changed = {})
        : QObject(area), area(area), changed(std::move(changed)) {
        wheelEnd.setSingleShot(true);
        connect(&wheelEnd, &QTimer::timeout, this, [this] { transition(QSScrollIdle); });
        connect(QScroller::scroller(area->viewport()), &QScroller::stateChanged, this, [this](QScroller::State state) {
            if (!enabled) return;
            switch (state) {
            case QScroller::Pressed: ++revision; transition(QSScrollTracking); break;
            case QScroller::Dragging: transition(QSScrollInteracting); break;
            case QScroller::Scrolling: transition(QSScrollDecelerating); break;
            case QScroller::Inactive: transition(QSScrollIdle); break;
            }
        });
        for (QWidget *target : {static_cast<QWidget *>(area), area->viewport(),
                                 static_cast<QWidget *>(area->horizontalScrollBar()),
                                 static_cast<QWidget *>(area->verticalScrollBar())}) target->installEventFilter(this);
        QScroller::grabGesture(area->viewport(), QScroller::TouchGesture);
        for (auto *bar : {area->horizontalScrollBar(), area->verticalScrollBar()}) {
            connect(bar, &QScrollBar::sliderPressed, this, [this] {
                if (enabled) { ++revision; wheelEnd.stop(); transition(QSScrollInteracting); }
            });
            connect(bar, &QScrollBar::sliderReleased, this, [this] { transition(QSScrollIdle); });
            connect(bar, &QScrollBar::actionTriggered, this, [this, bar] {
                if (!enabled) return;
                ++revision;
                if (phase != QSScrollDecelerating && !phasedWheel && !bar->isSliderDown()) {
                    transition(QSScrollInteracting);
                    wheelEnd.start(150);
                }
            });
            connect(bar, &QScrollBar::sliderMoved, this, [this] { if (enabled) ++revision; });
        }
    }

    quint64 revision = 0;
    QSScrollPhase phase = QSScrollIdle;
    bool observing = false;
    std::deque<QSScrollPhaseEvent> events;

    void animate(bool active) {
        if (active) {
            wheelEnd.stop();
            transition(QSScrollAnimating);
        } else if (phase == QSScrollAnimating) {
            transition(QSScrollIdle);
        }
    }

    void setEnabled(bool value) {
        if (enabled == value) return;
        enabled = value;
        if (enabled) QScroller::grabGesture(area->viewport(), QScroller::TouchGesture);
        else {
            QScroller::scroller(area->viewport())->stop();
            QScroller::ungrabGesture(area->viewport());
            wheelEnd.stop();
            phasedWheel = false;
            if (phase != QSScrollAnimating) transition(QSScrollIdle);
        }
    }

protected:
    bool eventFilter(QObject *target, QEvent *event) override {
        if (enabled) {
            if (event->type() == QEvent::Wheel) {
                auto *wheel = static_cast<QWheelEvent *>(event);
                ++revision;
                wheelEnd.stop();
                phasedWheel = wheel->phase() != Qt::NoScrollPhase && wheel->phase() != Qt::ScrollEnd;
                if (wheel->phase() == Qt::ScrollEnd) {
                    transition(QSScrollIdle);
                } else if (wheel->phase() == Qt::ScrollMomentum) {
                    const auto elapsed = wheel->timestamp() - wheelTime;
                    const auto velocity = (wheelTime && elapsed > 0 && elapsed < 200)
                        ? -QPointF(wheel->pixelDelta()) * (1000.0 / elapsed) : QPointF();
                    transition(QSScrollDecelerating, velocity);
                } else {
                    transition(QSScrollInteracting);
                    if (!phasedWheel) wheelEnd.start(150);
                }
                wheelTime = wheel->timestamp();
            }
            if (event->type() == QEvent::Scroll) ++revision;
            return false;
        }
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
    void transition(QSScrollPhase next, QPointF velocity = {}) {
        if (phase == next) return;
        if (observing) {
            events.push_back({phase, next, double(area->horizontalScrollBar()->value()),
                              double(area->verticalScrollBar()->value()), velocity.x(), velocity.y()});
            if (changed) changed();
        }
        phase = next;
    }
    QAbstractScrollArea *area;
    std::function<void()> changed;
    QTimer wheelEnd;
    quint64 wheelTime = 0;
    bool phasedWheel = false;
    bool enabled = true;
};
