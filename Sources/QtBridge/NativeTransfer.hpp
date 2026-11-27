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
    QSDropAction externalEvent(QWidget *window, QSTransferPhase phase, QPoint point, const QMimeData *mime);
    bool transferBetween(QWidget *window, QPoint from, QPoint to, void *context);

private:
    QPointer<QWidget> pressed, targeted;
    QPoint pressPoint;
    QPointer<const QMimeData> targetMime;
    QPointF targetPosition;
    Qt::DropAction proposal = Qt::CopyAction;
    static QWidget *scopeAt(QWidget *widget, QPoint global, const char *property);
    static QWidget *enclosing(QWidget *widget, const char *property);
    int send(QWidget *group, QSTransferPhase phase, const QMimeData *mime, QPointF global, void *context);
    void leave(void *context, bool finished = false);
    void enter(QWidget *group, const QMimeData *mime, QPointF global, void *context);
};
