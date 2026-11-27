#pragma once
#include <QApplication>
#include <QMouseEvent>
#include <QPointer>
#include <QTimer>
#include <QWidget>
#include <vector>

// A higher-priority recognizer can fail after a child control's press. Keep
// the input needed to deliver that same sequence, with its original timing.
struct DeferredPointer {
    struct Sample {
        QEvent::Type type;
        QPointF global;
        Qt::MouseButton button;
        Qt::MouseButtons buttons;
        Qt::KeyboardModifiers modifiers;
        QPointer<const QPointingDevice> device;
        quint64 timestamp;

        void send(QWidget *target) const {
            QMouseEvent copy(type, target->mapFromGlobal(global), global, button, buttons, modifiers,
                             device ? device.data() : QPointingDevice::primaryPointingDevice());
            copy.setTimestamp(timestamp);
            QApplication::sendEvent(target, &copy);
        }
    };

    using Scopes = QList<QPointer<QWidget>>;
    // Gesture callbacks may close the window during a nested dispatch.
    struct Dispatch {
        QPointer<QObject> owner;
        Scopes &current;
        Scopes previous;
        Dispatch(QObject *owner, Scopes &current) : owner(owner), current(current), previous(current) {}
        ~Dispatch() { if (owner) current = std::move(previous); }
    };
    Scopes skipped;
    QPointer<QWidget> target;
    std::vector<Sample> samples;
    QTimer timeout;
    bool claimed = false;

    void remember(QWidget *recipient, const QMouseEvent &event) {
        if (samples.empty()) target = recipient;
        samples.push_back({event.type(), event.globalPosition(), event.button(), event.buttons(),
                           event.modifiers(), event.pointingDevice(), event.timestamp()});
    }
    void clear() {
        timeout.stop();
        samples.clear();
        target.clear();
        skipped.clear();
        claimed = false;
    }
};
