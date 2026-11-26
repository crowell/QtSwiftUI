#include "NativeTransfer.hpp"
#include <QAbstractButton>
#include <QApplication>
#include <QDrag>
#include <QDragEnterEvent>
#include <QMouseEvent>
#include <limits>

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
void NativeTransfer::target(QWidget *next, void *context) {
    if (targeted == next) return;
    auto previous = targeted;
    targeted = next;
    if (previous) send(previous, QSTargetLeave, nullptr, {}, context);
    if (targeted) send(targeted, QSTargetEnter, nullptr, {}, context);
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
        auto mime = std::make_unique<QMimeData>();
        if (!send(source, QSWriteTransfer, mime.get(), pressPoint, context) || !source) break;
        auto *drag = new QDrag(source);
        drag->setMimeData(mime.release());
        const auto pixmap = source->grab();
        drag->setPixmap(pixmap);
        drag->setHotSpot(source->mapFromGlobal(pressPoint));
        if (auto *button = qobject_cast<QAbstractButton *>(receiver)) button->setDown(false);
        drag->exec(Qt::CopyAction | Qt::MoveAction, Qt::CopyAction);
        return true;
    }
    case QEvent::DragLeave:
        if (targeted) { target(nullptr, context); event->accept(); return true; }
        break;
    case QEvent::DragEnter:
    case QEvent::DragMove:
    case QEvent::Drop: {
        auto *drop = static_cast<QDropEvent *>(event);
        const auto global = receiver->mapToGlobal(drop->position());
        auto *group = scopeAt(receiver, global.toPoint(), "qsDropTarget");
        while (group && !send(group, QSValidateTransfer, drop->mimeData(), global, context))
            group = enclosing(group->parentWidget(), "qsDropTarget");
        target(group, context);
        if (!group) break;
        if (event->type() == QEvent::Drop) {
            const bool accepted = send(group, QSPerformDrop, drop->mimeData(), global, context);
            target(nullptr, context);
            if (!accepted) { drop->ignore(); return true; }
        }
        drop->acceptProposedAction();
        return true;
    }
    default: break;
    }
    return false;
}

bool NativeTransfer::transferBetween(QWidget *window, QPoint from, QPoint to, void *context) {
    const QPoint origin = window->mapToGlobal(from), destination = window->mapToGlobal(to);
    auto *source = scopeAt(window->childAt(from), origin, "qsDragSource");
    auto *group = scopeAt(window->childAt(to), destination, "qsDropTarget");
    QMimeData mime;
    if (!source || !group || !send(source, QSWriteTransfer, &mime, origin, context)) return false;
    const auto local = group->mapFromGlobal(destination);
    QDragEnterEvent enter(local, Qt::CopyAction, &mime, Qt::LeftButton, Qt::NoModifier);
    QApplication::sendEvent(group, &enter);
    if (!enter.isAccepted()) return false;
    QDropEvent drop(local, Qt::CopyAction, &mime, Qt::LeftButton, Qt::NoModifier);
    QApplication::sendEvent(group, &drop);
    return drop.isAccepted();
}
