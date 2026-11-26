#pragma once
#include "QtBridge.h"
#include <QEvent>
#include <QMimeData>
#include <QPointer>
#include <QWidget>

class NativeTransfer {
public:
    QSTransferHandler handler = nullptr;
    bool filter(QWidget *target, QEvent *event, void *context);
    bool transferBetween(QWidget *window, QPoint from, QPoint to, void *context);

private:
    QPointer<QWidget> pressed, targeted;
    QPoint pressPoint;
    static QWidget *scopeAt(QWidget *widget, QPoint global, const char *property);
    static QWidget *enclosing(QWidget *widget, const char *property);
    int send(QWidget *group, QSTransferPhase phase, const QMimeData *mime, QPointF global, void *context);
    void target(QWidget *group, void *context);
};
