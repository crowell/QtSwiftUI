#include "NativeTransfer.hpp"
#include <QAbstractButton>
#include <QApplication>
#include <QDrag>
#include <QDragEnterEvent>
#include <QMouseEvent>
#include <limits>

namespace {
class LocalDragData final : public QMimeData {};
}

void qs_mime_write(void *value, const char *format, const unsigned char *bytes, size_t length) {
    if (!value || !format || length > size_t(std::numeric_limits<qsizetype>::max()) || (!bytes && length)) return;
    static_cast<QMimeData *>(value)->setData(QString::fromUtf8(format), QByteArray(reinterpret_cast<const char *>(bytes), qsizetype(length)));
}
void qs_mime_read(void *value, int representations, void *context, QSMimeEntry entry) {
    if (!value || !entry) return;
    const auto *mime = static_cast<const QMimeData *>(value);
    for (const auto &format : mime->formats()) {
        // A URI list can offer web links, files, or both. Its schemes are
        // needed when checking a public.file-url destination before a drop.
        const auto bytes = (representations || format == QStringLiteral("text/uri-list"))
            ? mime->data(format) : QByteArray();
        entry(context, format.toUtf8().constData(), reinterpret_cast<const unsigned char *>(bytes.constData()), size_t(bytes.size()));
    }
    // Qt's native text clipboard is Unicode even when its MIME offer omits a charset.
    if (mime->hasText() && !mime->hasFormat(QStringLiteral("text/plain;charset=utf-8"))) {
        const auto utf8 = representations ? mime->text().toUtf8() : QByteArray();
        entry(context, "text/plain;charset=utf-8", reinterpret_cast<const unsigned char *>(utf8.constData()), size_t(utf8.size()));
    }
}

QWidget *NativeTransfer::enclosing(QWidget *widget, const char *property) {
    for (auto *w = widget; w && !w->isWindow(); w = w->parentWidget())
        if (w->isEnabled() && w->property(property).toBool()) return w;
    return nullptr;
}

QWidget *NativeTransfer::scopeAt(QWidget *widget, QPoint global, const char *property) {
    // A native button receives input on behalf of its label. Its SwiftUI label
    // can itself be a drag source or target, as in Serein's folder list.
    if (qobject_cast<QAbstractButton *>(widget)) {
        const auto children = widget->findChildren<QWidget *>();
        for (auto it = children.crbegin(); it != children.crend(); ++it) {
            auto *child = *it;
            if (child->isEnabled() && child->isVisible() && child->property(property).toBool() &&
                child->rect().contains(child->mapFromGlobal(global))) return child;
        }
    }
    return enclosing(widget, property);
}

int NativeTransfer::send(QWidget *group, QSTransferPhase phase, const QMimeData *mime, QPointF global, void *context) {
    if (!group || !handler) return 0;
    auto *window = group->window();
    const auto at = window->mapFromGlobal(global);
    const auto origin = qs_origin(group);
    return handler(context, group->property("swiftId").toInt(), phase, const_cast<QMimeData *>(mime), at.x() - origin.width, at.y() - origin.height);
}
void NativeTransfer::leave(void *context, bool finished) {
    const auto previous = targeted;
    const auto mime = targetMime;
    const auto position = targetPosition;
    targeted.clear();
    targetMime.clear();
    proposal = Qt::CopyAction;
    if (previous) send(previous, finished ? QSTargetFinish : QSTargetLeave, mime, position, context);
}

void NativeTransfer::enter(QWidget *group, const QMimeData *mime, QPointF global, void *context) {
    if (group != targeted || mime != targetMime) {
        const QPointer<QWidget> next = group;
        leave(context);
        targeted = next;
        targetMime = mime;
        if (targeted) send(targeted, QSTargetEnter, mime, global, context);
    }
    targetPosition = global;
}

bool NativeTransfer::filter(QWidget *receiver, QEvent *event, void *context) {
    if (!handler || !receiver) return false;
    switch (event->type()) {
    case QEvent::MouseButtonPress: {
        auto *mouse = static_cast<QMouseEvent *>(event);
        if (mouse->button() == Qt::LeftButton && !pressed) {
            pressPoint = mouse->globalPosition().toPoint();
            pressed = scopeAt(receiver, pressPoint, "qsDragSource");
        }
        break;
    }
    case QEvent::MouseButtonRelease:
        pressed = nullptr;
        break;
    case QEvent::MouseMove: {
        auto *mouse = static_cast<QMouseEvent *>(event);
        if (!pressed || !(mouse->buttons() & Qt::LeftButton)) break;
        if ((mouse->globalPosition().toPoint() - pressPoint).manhattanLength() < QApplication::startDragDistance()) break;
        QPointer<QWidget> source = pressed;
        pressed = nullptr;
        if (!source->isEnabled() || !source->isVisible()) break;
        auto mime = std::make_unique<LocalDragData>();
        if (!send(source, QSWriteTransfer, mime.get(), pressPoint, context) || !source) break;
        QPointer<QDrag> drag = new QDrag(source);
        drag->setMimeData(mime.release());
        const auto pixmap = source->grab();
        drag->setPixmap(pixmap);
        drag->setHotSpot(source->mapFromGlobal(pressPoint));
        if (auto *button = qobject_cast<QAbstractButton *>(receiver)) button->setDown(false);
        drag->exec(Qt::CopyAction | Qt::MoveAction | Qt::LinkAction, Qt::CopyAction);
        if (drag) drag->deleteLater();
        return true;
    }
    case QEvent::DragLeave:
        if (targeted) { leave(context); event->accept(); return true; }
        break;
    case QEvent::DragEnter:
    case QEvent::DragMove:
    case QEvent::Drop: {
        auto *drop = static_cast<QDropEvent *>(event);
        const auto global = receiver->mapToGlobal(drop->position());
        auto *group = scopeAt(receiver, global.toPoint(), "qsDropTarget");
        while (group && (group != targeted || targetMime != drop->mimeData()) &&
               !send(group, QSValidateTransfer, drop->mimeData(), global, context))
            group = enclosing(group->parentWidget(), "qsDropTarget");
        const bool changedTarget = group != targeted || targetMime != drop->mimeData();
        enter(group, drop->mimeData(), global, context);
        if (!targeted) break;

        if (event->type() != QEvent::Drop || changedTarget) {
            const bool local = drop->source() || dynamic_cast<const LocalDragData *>(drop->mimeData());
            const auto phase = local ? QSUpdateTransfer : QSUpdateExternalTransfer;
            switch (send(targeted, phase, drop->mimeData(), global, context)) {
            case QSDropCopy: proposal = Qt::CopyAction; break;
            case QSDropMove: proposal = Qt::MoveAction; break;
            case QSDropLink: proposal = Qt::LinkAction; break;
            case QSDropReject: proposal = Qt::IgnoreAction; break;
            default: proposal = drop->proposedAction(); break;
            }
        }
        const auto action = drop->possibleActions().testFlag(proposal) ? proposal : Qt::IgnoreAction;
        if (event->type() == QEvent::Drop) {
            const bool accepted = action != Qt::IgnoreAction &&
                send(targeted, QSPerformDrop, drop->mimeData(), global, context);
            leave(context, accepted);
            if (!accepted) { drop->ignore(); return true; }
        }
        drop->setDropAction(action);
        drop->accept();
        return true;
    }
    default: break;
    }
    return false;
}

QSDropAction NativeTransfer::externalEvent(QWidget *window, QSTransferPhase phase, QPoint point, const QMimeData *mime) {
    const auto global = window->mapToGlobal(point);
    auto *receiver = scopeAt(window->childAt(point), global, "qsDropTarget");
    if (!receiver || !mime) return QSDropReject;
    if (phase == QSTargetLeave) {
        QDragLeaveEvent leaveEvent;
        QApplication::sendEvent(receiver, &leaveEvent);
        return QSDropUnchanged;
    }
    const auto local = receiver->mapFromGlobal(global);
    const auto actions = Qt::CopyAction | Qt::MoveAction | Qt::LinkAction;
    std::unique_ptr<QDropEvent> event;
    switch (phase) {
    case QSTargetEnter: event = std::make_unique<QDragEnterEvent>(local, actions, mime, Qt::LeftButton, Qt::NoModifier); break;
    case QSUpdateTransfer: event = std::make_unique<QDragMoveEvent>(local, actions, mime, Qt::LeftButton, Qt::NoModifier); break;
    case QSPerformDrop: event = std::make_unique<QDropEvent>(local, actions, mime, Qt::LeftButton, Qt::NoModifier); break;
    default: return QSDropReject;
    }
    QApplication::sendEvent(receiver, event.get());
    if (!event->isAccepted()) return QSDropReject;
    switch (event->dropAction()) {
    case Qt::CopyAction: return QSDropCopy;
    case Qt::MoveAction: return QSDropMove;
    case Qt::LinkAction: return QSDropLink;
    default: return QSDropReject;
    }
}

bool NativeTransfer::transferBetween(QWidget *window, QPoint from, QPoint to, void *context) {
    const QPoint origin = window->mapToGlobal(from), destination = window->mapToGlobal(to);
    auto *source = scopeAt(window->childAt(from), origin, "qsDragSource");
    auto *group = scopeAt(window->childAt(to), destination, "qsDropTarget");
    LocalDragData mime;
    if (!source || !group || !send(source, QSWriteTransfer, &mime, origin, context)) return false;
    const auto local = group->mapFromGlobal(destination);
    const auto actions = Qt::CopyAction | Qt::MoveAction | Qt::LinkAction;
    QDragEnterEvent enter(local, actions, &mime, Qt::LeftButton, Qt::NoModifier);
    QApplication::sendEvent(group, &enter);
    if (!enter.isAccepted()) return false;
    QDropEvent drop(local, actions, &mime, Qt::LeftButton, Qt::NoModifier);
    QApplication::sendEvent(group, &drop);
    return drop.isAccepted();
}
