#include "QtBridge.h"
#include "AlphaMask.hpp"
#include "BusyIndicator.hpp"
#include "ViewBlur.hpp"
#include "ScrollInput.hpp"
#include "AttributedLabel.hpp"
#include "CanvasBlur.hpp"
#include "PointerDrag.hpp"
#include "PlainTextEditor.hpp"
#include "WindowShortcuts.hpp"
#include "PathTrim.hpp"
#include "RasterWidget.hpp"
#include <QApplication>
#include <QAccessibleWidget>
#include <QCheckBox>
#include <QDir>
#include <QDesktopServices>
#include <QUrl>
#include <QWindow>
#include <QWheelEvent>
#include <QVariantAnimation>
#include <algorithm>
#include <QLabel>
#include <QFontInfo>
#include <QRawFont>
#include <QFontDatabase>
#include <QGraphicsOpacityEffect>
#include <QEnterEvent>
#include <QElapsedTimer>
#include <QLineEdit>
#include <QInputMethodEvent>
#include <QKeyEvent>
#include <QMouseEvent>
#include <QPainter>
#include <QPainterPath>
#include <QProgressBar>
#include <QPointingDevice>
#include <QProxyStyle>
#include <QStyleOptionFocusRect>
#include <QPushButton>
#include <QResizeEvent>
#include <QScrollArea>
#include <QScrollBar>
#include <QScroller>
#include <QSignalBlocker>
#include <QSlider>
#include <QTimer>
#include <cmath>
#include <optional>
#include <vector>

struct QSPath : QPainterPath {};

namespace {
QTransform transform(QSAffine t) { return QTransform(t.a, t.b, t.c, t.d, t.tx, t.ty); }
class SwiftWidgetStyle final : public QProxyStyle {
public:
    int pixelMetric(PixelMetric metric, const QStyleOption *option, const QWidget *item) const override {
        const int base = QProxyStyle::pixelMetric(metric, option, item);
        const qreal scale = item ? item->property("qsControlScale").toDouble() : 0;
        if (scale == 0 || scale == 1) return base;
        switch (metric) {
        case PM_ButtonMargin: case PM_IndicatorWidth: case PM_IndicatorHeight:
        case PM_SliderThickness: case PM_SliderLength: case PM_ProgressBarChunkWidth:
            return qMax(1, qRound(base * scale));
        default: return base;
        }
    }
    void drawPrimitive(PrimitiveElement element, const QStyleOption *option, QPainter *painter,
                       const QWidget *widget = nullptr) const override {
        if (element == PE_FrameFocusRect && widget && widget->property("qsNoFocusEffect").toBool()) return;
        QProxyStyle::drawPrimitive(element, option, painter, widget);
    }
};
QApplication *ownedApplication = nullptr;
int liveWindows = 0;
QApplication &application() {
    static int argc = 1;
    static char name[] = "QtSwiftUI";
    static char *argv[] = {name, nullptr};
    if (!qApp) {
        ownedApplication = new QApplication(argc, argv);
        ownedApplication->setStyle(new SwiftWidgetStyle());
    }
    return *qApp;
}
class GroupWidget final : public QWidget {
public:
    using QWidget::QWidget;
    QRect layoutRect;
    bool sizedToContent = false;
    QRect hitBounds() const { return sizedToContent ? rect() : layoutRect; }
    bool exposeChildren = true, combineChildren = false;
    bool windowDrag = false, trackingDrag = false, simultaneous = false;
    QPointF dragOrigin;
    PointerDrag pointerDrag;
    int gestureInputs = 127;
    qint64 gestureDevice = -1;
    bool isImage = false;
    bool heading = false, adjustable = false;
    bool modal = false;
    bool updatesFrequently = false;
    QString accessibleValue;
    std::optional<QPainterPath> contentShape;
    int tapCount = 0, consecutiveTaps = 0;
    bool trackingTap = false;
    QPointF pressPosition, tapLocation;
    QElapsedTimer lastTap;
    bool accessibilityHidden = false;
    void cancelPointer() {
        trackingTap = trackingDrag = pointerDrag.tracking = false;
        consecutiveTaps = 0;
        gestureDevice = -1;
    }
    void paintEvent(QPaintEvent *event) override {
        QWidget::paintEvent(event);
        if (!hasFocus() || focusProxy() || !property("qsFocusable").toBool()) return;
        QStyleOptionFocusRect focus;
        focus.initFrom(this);
        QPainter painter(this);
        style()->drawPrimitive(QStyle::PE_FrameFocusRect, &focus, &painter, this);
    }
};
class SwiftButton final : public QPushButton {
public:
    using QPushButton::QPushButton;
protected:
    bool hitButton(const QPoint &point) const override {
        if (!QPushButton::hitButton(point)) return false;
        for (auto *parent = parentWidget(); parent; parent = parent->parentWidget()) {
            auto *group = dynamic_cast<GroupWidget *>(parent);
            if (group && group->contentShape && !group->contentShape->contains(mapTo(group, point))) return false;
        }
        // A custom ButtonStyle may place contentShape on the label inside the
        // native button. Evaluate those shapes in their own coordinate spaces.
        bool restricted = false;
        for (auto *child : findChildren<QWidget *>()) {
            auto *group = dynamic_cast<GroupWidget *>(child);
            if (!group || !group->contentShape) continue;
            restricted = true;
            if (group->contentShape->contains(group->mapFrom(this, point))) return true;
        }
        return !restricted;
    }
};
static void sendAccessibleEvent(GroupWidget *target, QSEventKind kind);
static void activateAccessibleButton(QAbstractButton *button);

class AccessibleGroup final : public QAccessibleWidget {
public:
    explicit AccessibleGroup(GroupWidget *group) : QAccessibleWidget(group), group(group) {}
    QRect rect() const override {
        const QRect bounds = group->hitBounds();
        return QRect(group->mapToGlobal(bounds.topLeft()), bounds.size());
    }
    QAccessible::Role role() const override {
        if (group->adjustable) return QAccessible::Slider;
        if (group->property("qsAXToggle").toBool()) return QAccessible::CheckBox;
        if (group->property("qsAXButton").toBool()) return QAccessible::Button;
        if (group->modal) return QAccessible::Dialog;
        if (group->heading) return QAccessible::Heading;
        return group->isImage ? QAccessible::Graphic : QAccessible::Grouping;
    }
    QString text(QAccessible::Text kind) const override {
        if (kind == QAccessible::Value && !group->accessibleValue.isEmpty()) return group->accessibleValue;
        auto value = QAccessibleWidget::text(kind);
        if (kind == QAccessible::Name && value.isEmpty() && group->heading) {
            if (auto *label = group->findChild<QLabel *>()) return label->text();
        }
        if (group->combineChildren && value.isEmpty() && (kind == QAccessible::Name || kind == QAccessible::Value)) {
            QStringList parts;
            for (int i = 0; i < QAccessibleWidget::childCount(); ++i)
                collectText(QAccessibleWidget::child(i), kind, parts);
            return parts.join(QStringLiteral(", "));
        }
        return value;
    }
    QStringList actionNames() const override {
        auto names = QAccessibleWidget::actionNames();
        if (!group->isEnabled() || group->accessibilityHidden) return {};
        if (group->adjustable) names << QAccessibleActionInterface::increaseAction() << QAccessibleActionInterface::decreaseAction();
        if (group->tapCount == 1) names.append(QAccessibleActionInterface::pressAction());
        for (const auto &entry : combinedActions()) names.append(entry.name);
        names.removeDuplicates();
        return names;
    }
    void doAction(const QString &action) override {
        if (!group->isEnabled() || group->accessibilityHidden) return;
        if (group->adjustable && (action == increaseAction() || action == decreaseAction())) {
            sendAccessibleEvent(group, action == increaseAction() ? QSIncrement : QSDecrement);
            return;
        }
        if (group->tapCount == 1 && action == QAccessibleActionInterface::pressAction()) {
            sendAccessibleEvent(group, QSActivate);
            return;
        }
        for (const auto &entry : combinedActions()) {
            if (entry.name == action) {
                entry.target->actionInterface()->doAction(entry.action);
                return;
            }
        }
        QAccessibleWidget::doAction(action);
    }
    QAccessible::State state() const override {
        auto result = QAccessibleWidget::state();
        if (group->accessibilityHidden) result.invisible = true;
        result.animated = group->updatesFrequently;
        result.modal = group->modal;
        result.selected = group->property("qsSelected").toBool();
        if (group->property("qsAXToggle").toBool()) { result.checkable = true; result.checked = result.selected; }
        return result;
    }
    int childCount() const override { return group->exposeChildren && !group->accessibilityHidden ? QAccessibleWidget::childCount() : 0; }
    QAccessibleInterface *child(int index) const override { return group->exposeChildren && !group->accessibilityHidden ? QAccessibleWidget::child(index) : nullptr; }
private:
    static void collectText(QAccessibleInterface *child, QAccessible::Text kind, QStringList &parts) {
        if (!child || child->state().invisible) return;
        const auto text = child->text(kind);
        if (!text.isEmpty()) parts.append(text);
        else for (int i = 0; i < child->childCount(); ++i) collectText(child->child(i), kind, parts);
    }
    struct Action { QString name; QAccessibleInterface *target; QString action; };
    using Actions = QList<Action>;
    static void collectActions(QAccessibleInterface *child, Actions &actions) {
        if (!child || child->state().invisible || child->state().disabled) return;
        if (auto *interface = child->actionInterface()) {
            const auto supported = interface->actionNames();
            for (const auto &action : {QAccessibleActionInterface::pressAction(), QAccessibleActionInterface::toggleAction()}) {
                if (supported.contains(action)) {
                    actions.append({child->text(QAccessible::Name), child, action});
                    return;
                }
            }
        }
        for (int i = 0; i < child->childCount(); ++i) collectActions(child->child(i), actions);
    }
    Actions combinedActions() const {
        Actions actions;
        if (group->combineChildren) {
            for (int i = 0; i < QAccessibleWidget::childCount(); ++i)
                collectActions(QAccessibleWidget::child(i), actions);
        }
        if (actions.size() == 1) actions.first().name = group->property("qsAXToggle").toBool()
            ? QAccessibleActionInterface::toggleAction() : QAccessibleActionInterface::pressAction();
        return actions;
    }
    GroupWidget *group;
};
class ShapeClipEffect final : public QGraphicsEffect {
public:
    using QGraphicsEffect::QGraphicsEffect;
    QPainterPath path;
    bool antialias = true;
protected:
    void draw(QPainter *painter) override {
        QPoint offset;
        const auto source = sourcePixmap(Qt::LogicalCoordinates, &offset, NoPad);
        if (source.isNull()) return;
        QImage mask(source.size(), QImage::Format_ARGB32_Premultiplied);
        mask.setDevicePixelRatio(source.devicePixelRatio());
        mask.fill(Qt::transparent);
        QPainter fill(&mask);
        fill.setRenderHint(QPainter::Antialiasing, antialias);
        fill.translate(-offset);
        fill.fillPath(path, Qt::white);
        fill.end();

        auto image = source.toImage().convertToFormat(QImage::Format_ARGB32_Premultiplied);
        QPainter compose(&image);
        compose.setCompositionMode(QPainter::CompositionMode_DestinationIn);
        compose.drawImage(QPoint(), mask);
        compose.end();
        painter->drawImage(offset, image);
    }
};
class RotationEffect final : public QGraphicsEffect {
public:
    explicit RotationEffect(QObject *parent) : QGraphicsEffect(parent) {}
    void setRotation(double value, QPointF anchorValue) {
        if (degrees == value && anchor == anchorValue) return;
        degrees = value;
        anchor = anchorValue;
        updateBoundingRect();
        update();
    }
    QRectF boundingRectFor(const QRectF &source) const override { return matrix(source).mapRect(source); }
protected:
    void draw(QPainter *painter) override {
        QPoint offset;
        const auto source = sourcePixmap(Qt::LogicalCoordinates, &offset, NoPad);
        painter->save();
        painter->setRenderHint(QPainter::SmoothPixmapTransform);
        painter->setTransform(matrix(sourceBoundingRect(Qt::LogicalCoordinates)), true);
        painter->drawPixmap(offset, source);
        painter->restore();
    }
private:
    double degrees = 0;
    QPointF anchor;
    QTransform matrix(const QRectF &source) const {
        const QPointF center(source.x() + anchor.x() * source.width(), source.y() + anchor.y() * source.height());
        QTransform t;
        t.translate(center.x(), center.y());
        t.rotate(degrees);
        t.translate(-center.x(), -center.y());
        return t;
    }
};
class AccessibleButton final : public QAccessibleWidget {
public:
    AccessibleButton(QPushButton *button, bool link)
        : QAccessibleWidget(button, link ? QAccessible::Link : QAccessible::Button), button(button) {}
    QString text(QAccessible::Text kind) const override {
        const QString value = QAccessibleWidget::text(kind);
        if (kind != QAccessible::Name || !value.isEmpty()) return value;
        if (!button->text().isEmpty()) return button->text();
        QStringList parts;
        for (const auto *label : button->findChildren<QLabel *>()) parts.append(label->text());
        return parts.join(' ');
    }
    QStringList actionNames() const override { return {QAccessibleActionInterface::pressAction()}; }
    void doAction(const QString &action) override {
        if (action == QAccessibleActionInterface::pressAction() && button->isEnabled()) activateAccessibleButton(button);
    }
    QAccessible::State state() const override {
        auto state = QAccessibleWidget::state();
        state.linked = role() == QAccessible::Link;
        state.selected = button->property("qsSelected").toBool();
        state.pressed = button->isDown();
        state.defaultButton = button->isDefault();
        return state;
    }
private:
    QPushButton *button;
};
class Surface final : public QWidget {
public:
    using QWidget::QWidget;
    QColor fill;
    QPainterPath path;
    bool customPath = false, antialias = true;
    double radius = 0;
    void paintEvent(QPaintEvent *) override {
        QPainter painter(this);
        painter.translate(property("qsFraction").toPointF());
        painter.setRenderHint(QPainter::Antialiasing, antialias);
        painter.setPen(Qt::NoPen);
        painter.setBrush(fill);
        const auto logical = property("qsSize").toSizeF();
        const double r = std::min(radius, std::min(logical.width(), logical.height()) / 2.0);
        if (customPath) painter.drawPath(path);
        else painter.drawRoundedRect(QRectF(QPointF(), logical), r, r);
    }
};
struct Drawing {
    QPainterPath path;
    QTransform matrix;
    double opacity;
    double lineWidth;
    bool antialias;
    QColor color;
    std::optional<QLinearGradient> gradient;
    std::optional<QPainterPath> clip;
    std::vector<CanvasBlur> filters;
};
class CanvasWidget final : public QWidget {
public:
    using QWidget::QWidget;
    std::vector<Drawing> drawings;
    void paintEvent(QPaintEvent *) override {
        QPainter painter(this);
        painter.translate(property("qsFraction").toPointF());
        for (const auto &drawing : drawings) {
            painter.save();
            if (drawing.clip) painter.setClipPath(*drawing.clip);
            painter.setOpacity(drawing.opacity);
            if (drawing.filters.empty()) paintSource(painter, drawing);
            else paintFiltered(painter, drawing);
            painter.restore();
        }
    }
private:
    static void paintSource(QPainter &painter, const Drawing &drawing) {
        painter.setRenderHint(QPainter::Antialiasing, drawing.antialias);
        painter.setTransform(drawing.matrix, true);
        const QBrush brush = drawing.gradient ? QBrush(*drawing.gradient) : QBrush(drawing.color);
        if (drawing.lineWidth >= 0) {
            painter.strokePath(drawing.path, QPen(brush, drawing.lineWidth, Qt::SolidLine, Qt::FlatCap, Qt::MiterJoin));
        } else {
            painter.fillPath(drawing.path, brush);
        }
    }
    void paintFiltered(QPainter &painter, const Drawing &drawing) {
        // Keep enough offscreen source pixels for edges that blur into the window.
        double pad = 1;
        for (const auto &filter : drawing.filters) pad += 3.5 * filter.radius;
        const double stroke = qMax(0.0, drawing.lineWidth) / 2;
        QRectF bounds = drawing.matrix.mapRect(drawing.path.controlPointRect().adjusted(-stroke, -stroke, stroke, stroke));
        const QRectF area = bounds.adjusted(-pad, -pad, pad, pad).intersected(QRectF(rect()).adjusted(-pad, -pad, pad, pad));
        if (area.isEmpty() || !std::isfinite(area.width()) || !std::isfinite(area.height())) return;
        // Large filters have low spatial frequency. Sample on a coarser grid
        // before allocating backing storage when the spread exceeds the window.
        const double scale = qMin(devicePixelRatioF(), 2.0 * qMax(width(), height()) / qMax(area.width(), area.height()));
        const int w = qCeil(area.width() * scale), h = qCeil(area.height() * scale);
        QImage layer(w, h, QImage::Format_ARGB32_Premultiplied);
        if (layer.isNull()) return;
        layer.fill(Qt::transparent);
        {
            QPainter source(&layer);
            source.scale(scale, scale);
            source.translate(-area.topLeft());
            paintSource(source, drawing);
        }
        for (const auto &filter : drawing.filters) layer = gaussianBlur(layer, filter, scale);
        painter.setRenderHint(QPainter::SmoothPixmapTransform);
        painter.drawImage(QRectF(area.topLeft(), QSizeF(w / scale, h / scale)), layer);
    }
};
QWidget *widget(QSWidget w) { return static_cast<QWidget *>(w); }
}

struct QSWindow final : QWidget {
    void *context;
    QSRender render;
    QSEvent event;
    QSDragHandler dragHandler = nullptr;
    QSKeyHandler keyHandler = nullptr;
    bool pending = false, framePending = false;
    WindowShortcuts shortcuts;

    void schedule() {
        if (pending) return;
        pending = true;
        QTimer::singleShot(0, this, [this] {
            pending = false;
            render(context, width(), height());
        });
    }
    bool eventFilter(QObject *source, QEvent *input) override {
        if (keyHandler && source == focusWidget() && (input->type() == QEvent::KeyPress || input->type() == QEvent::KeyRelease)) {
            const auto *key = static_cast<QKeyEvent *>(input);
            const bool release = input->type() == QEvent::KeyRelease;
            if (!(release && key->isAutoRepeat())) {
                const auto chars = WindowShortcuts::characters(key->key(), key->text()).toUtf8();
                auto modifiers = key->modifiers();
                const int flags = (modifiers & Qt::ShiftModifier ? 2 : 0) | (modifiers & Qt::ControlModifier ? 4 : 0)
                                | (modifiers & Qt::AltModifier ? 8 : 0) | (modifiers & Qt::MetaModifier ? 16 : 0)
                                | (modifiers & Qt::KeypadModifier ? 32 : 0);
                if (!chars.isEmpty() && keyHandler(context, source->property("swiftId").toInt(),
                                                    release ? 4 : key->isAutoRepeat() ? 2 : 1, chars.constData(), flags)) {
                    input->accept();
                    return true;
                }
            }
        }
        if ((input->type() == QEvent::Enter || input->type() == QEvent::Leave) && source->property("qsHover").toBool()) {
            event(context, source->property("swiftId").toInt(), QSHoverChanged, input->type() == QEvent::Enter ? "1" : "0");
        }
        auto *group = dynamic_cast<GroupWidget *>(source);
        if (input->type() == QEvent::UngrabMouse || input->type() == QEvent::Hide ||
            (input->type() == QEvent::EnabledChange && group && !group->isEnabled())) {
            for (auto *parent = qobject_cast<QWidget *>(source); parent && parent != this; parent = parent->parentWidget()) {
                auto *scope = dynamic_cast<GroupWidget *>(parent);
                if (!scope) continue;
                const bool tracking = scope->trackingTap || scope->trackingDrag || scope->pointerDrag.tracking;
                if (input->type() == QEvent::UngrabMouse && !tracking) continue;
                if (parent == source || (scope->simultaneous && tracking)) cancelGesture(scope);
            }
        }
        if (group && group->hitBounds() != group->rect() &&
            (input->type() == QEvent::MouseButtonPress || input->type() == QEvent::MouseButtonRelease ||
             input->type() == QEvent::MouseButtonDblClick || input->type() == QEvent::MouseMove)) {
            auto *mouse = static_cast<QMouseEvent *>(input);
            if (!group->pointerDrag.tracking && !group->hitBounds().contains(mouse->position().toPoint())) {
                const auto at = mapFromGlobal(mouse->globalPosition().toPoint());
                // Paint overflow is transparent to input. Find the sibling underneath.
                group->setAttribute(Qt::WA_TransparentForMouseEvents);
                auto *under = childAt(at);
                if (under) {
                    QMouseEvent forwarded(mouse->type(), under->mapFrom(this, at), mouse->globalPosition(),
                                          mouse->button(), mouse->buttons(), mouse->modifiers());
                    QApplication::sendEvent(under, &forwarded);
                }
                group->setAttribute(Qt::WA_TransparentForMouseEvents, false);
                return true;
            }
        }
        if (input->type() == QEvent::MouseButtonPress || input->type() == QEvent::MouseButtonDblClick ||
            input->type() == QEvent::MouseButtonRelease || input->type() == QEvent::MouseMove) {
            auto *target = qobject_cast<QWidget *>(source);
            auto *mouse = static_cast<QMouseEvent *>(input);
            // A native control can consume the event before it propagates to its parent.
            for (QWidget *ancestor = target; ancestor && ancestor != this; ancestor = ancestor->parentWidget()) {
                auto *observer = dynamic_cast<GroupWidget *>(ancestor);
                if (observer && observer->simultaneous && observer->isEnabled())
                    recognize(observer, mouse);
            }
            if (group && !group->simultaneous && recognize(group, mouse)) {
                input->accept();
                return true;
            }
        }
        if (input->type() == QEvent::FocusIn || input->type() == QEvent::FocusOut) {
            event(context, source->property("swiftId").toInt(), QSFocusChanged,
                  input->type() == QEvent::FocusIn ? "1" : "0");
        }
        return false;
    }
    bool recognize(GroupWidget *group, QMouseEvent *mouse) {
        if (!group->tapCount && !group->windowDrag && group->pointerDrag.threshold < 0) return false;
        const auto device = mouse->pointingDevice();
        const auto typeOfDevice = device ? device->type() : QInputDevice::DeviceType::Mouse;
        const int kind = typeOfDevice == QInputDevice::DeviceType::TouchScreen ? 1 : typeOfDevice == QInputDevice::DeviceType::TouchPad ? 2 :
                         typeOfDevice == QInputDevice::DeviceType::Stylus || typeOfDevice == QInputDevice::DeviceType::Airbrush ? 4 : 8;
        if (!(group->gestureInputs & kind)) return false;
        const auto type = mouse->type();
        const auto point = group->mapFromGlobal(mouse->globalPosition());
        const bool press = type == QEvent::MouseButtonPress || type == QEvent::MouseButtonDblClick;
        const auto deviceId = device ? device->systemId() : 0;
        if (group->gestureDevice != deviceId) {
            if (!press) return false;
            cancelGesture(group);
            group->gestureDevice = deviceId;
        }
        if (group->pointerDrag.threshold >= 0) {
            const bool inside = group->hitBounds().contains(point.toPoint());
            const bool tracking = group->pointerDrag.tracking;
            const auto sample = group->pointerDrag.update(*mouse, mapFromGlobal(mouse->globalPosition()), inside);
            if (sample && dragHandler) dragHandler(context, group->property("swiftId").toInt(), *sample);
            // A press below the drag threshold can still complete an enclosing tap.
            // Once the drag wins, discard that tap for the remainder of the sequence.
            if (tracking || group->pointerDrag.tracking) {
                for (auto *parent = group->parentWidget(); parent && parent != this; parent = parent->parentWidget()) {
                    auto *tap = dynamic_cast<GroupWidget *>(parent);
                    if (!tap || !tap->tapCount || tap->simultaneous) continue;
                    if (group->pointerDrag.recognized) tap->trackingTap = false;
                    else recognize(tap, mouse);
                    break;
                }
            }
            if (mouse->button() == Qt::LeftButton || mouse->type() == QEvent::MouseMove)
                return tracking || group->pointerDrag.tracking;
        }
        if (group->windowDrag && mouse->button() == Qt::LeftButton) {
            if (press && !group->trackingDrag) {
                group->dragOrigin = mouse->globalPosition();
                group->trackingDrag = windowHandle() && windowHandle()->startSystemMove();
            } else if (type == QEvent::MouseButtonRelease) {
                const bool dragged = (mouse->globalPosition() - group->dragOrigin).manhattanLength() >= QApplication::startDragDistance();
                if (group->trackingDrag && dragged) event(context, group->property("swiftId").toInt(), QSActivate, "");
                group->trackingDrag = false;
            }
            return true;
        }
        if (group->tapCount <= 0) return false;
        const bool moved = (point - group->pressPosition).manhattanLength() > QApplication::startDragDistance();
        if (type == QEvent::MouseMove && moved) group->trackingTap = false;
        if (mouse->button() != Qt::LeftButton) return false;
        const bool inside = group->hitBounds().contains(point.toPoint());
        if (press) {
            if (!group->lastTap.isValid() || group->lastTap.elapsed() > QApplication::doubleClickInterval() || moved)
                group->consecutiveTaps = 0;
            group->trackingTap = inside;
            group->pressPosition = point;
        } else if (type == QEvent::MouseButtonRelease) {
            const bool tapped = group->trackingTap && !moved && inside;
            group->trackingTap = false;
            if (tapped) {
                group->lastTap.start();
                if (++group->consecutiveTaps == group->tapCount) {
                    group->consecutiveTaps = 0;
                    group->tapLocation = mapFromGlobal(mouse->globalPosition());
                    event(context, group->property("swiftId").toInt(), QSActivate, "");
                }
            }
        }
        return true;
    }
    void cancelGesture(GroupWidget *group) {
        const bool active = group->pointerDrag.tracking && group->pointerDrag.recognized;
        group->cancelPointer();
        if (active) event(context, group->property("swiftId").toInt(), QSGestureCancelled, "");
    }
    void observeFocus(QWidget *item, int id) {
        item->setProperty("swiftId", id);
        item->installEventFilter(this);
    }
    void keyPressEvent(QKeyEvent *key) override {
        if (key->key() == Qt::Key_Escape && key->modifiers() == Qt::NoModifier) {
            QWidget *scope = focusWidget();
            while (scope && !scope->property("qsExit").toBool()) scope = scope->parentWidget();
            if (!scope && !focusWidget()) {
                // A window with no first responder can still provide a scene-wide command.
                for (auto *item : findChildren<QWidget *>()) {
                    if (item->isVisible() && item->isEnabled() && item->property("qsExit").toBool()) {
                        if (scope) { scope = nullptr; break; }
                        scope = item;
                    }
                }
            }
            if (scope) {
                key->accept();
                event(context, scope->property("swiftId").toInt(), QSExitCommand, "");
                return;
            }
        }
        QWidget::keyPressEvent(key);
    }
    void resizeEvent(QResizeEvent *) override { schedule(); }
    void changeEvent(QEvent *change) override {
        QWidget::changeEvent(change);
        if (change->type() == QEvent::WindowStateChange || change->type() == QEvent::ActivationChange) schedule();
    }
};

namespace {
static void sendAccessibleEvent(GroupWidget *target, QSEventKind kind) {
    auto *window = dynamic_cast<QSWindow *>(target->window());
    if (!window || !target->isEnabled()) return;
    if (kind == QSActivate) target->tapLocation = target->mapTo(window, QRectF(target->layoutRect).center());
    window->event(window->context, target->property("swiftId").toInt(), kind, "");
}
static void activateAccessibleButton(QAbstractButton *button) {
    for (auto *parent = button->parentWidget(); parent; parent = parent->parentWidget()) {
        auto *group = dynamic_cast<GroupWidget *>(parent);
        if (group && group->simultaneous && group->tapCount == 1) sendAccessibleEvent(group, QSActivate);
    }
    button->click();
}
} // namespace
QSWindow *qs_window(const char *title, void *context, QSRender render, QSEvent event) {
    application();
    ++liveWindows;
    auto *window = new QSWindow();
    window->context = context;
    window->render = render;
    window->event = event;
    window->setWindowTitle(QString::fromUtf8(title));
    QObject::connect(qApp, &QGuiApplication::applicationStateChanged, window, [window] { window->schedule(); });
    return window;
}
void qs_open(QSWindow *window, int width, int height) {
    window->resize(width, height);
    window->show();
    qs_flush();
}
void qs_shortcut_begin(QSWindow *window) { window->shortcuts.begin(); }
void qs_shortcut_finish(QSWindow *window) { window->shortcuts.finish(); }
void qs_button_shortcut(QSWindow *window, QSWidget item, const char *key, int flags, int automatic) {
    window->shortcuts.add(window, static_cast<QAbstractButton *>(item), QString::fromUtf8(key), flags, automatic);
}
void qs_request_close(QSWindow *window) { window->close(); }
int qs_open_url(const char *url) {
    const QUrl destination = QUrl::fromEncoded(QByteArray(url), QUrl::StrictMode);
    return destination.isValid() && !destination.isRelative() && QDesktopServices::openUrl(destination);
}
void qs_update(QSWindow *window) { window->schedule(); }
void qs_animation_frame(QSWindow *window) {
    if (window->framePending) return;
    window->framePending = true;
    QTimer::singleShot(16, window, [window] {
        window->framePending = false;
        window->schedule();
    });
}
void qs_flush() { application().processEvents(); }
int qs_dark_ink(QSWindow *window, int x, int y, int width, int height) {
    const auto image = window->grab(QRect(x, y, width, height)).toImage();
    for (int row = 0; row < image.height(); ++row)
        for (int col = 0; col < image.width(); ++col)
            if (qBlue(image.pixel(col, row)) < 125) return 1;
    return 0;
}
int qs_capture(QSWindow *window, const char *path) {
    return window->grab().save(QString::fromUtf8(path), "PNG");
}
int qs_run(QSWindow *window, const char *screenshot, QSPump pump) {
    // Swift's main actor and Foundation timers share the GUI thread with Qt.
    QTimer swiftEvents;
    QObject::connect(&swiftEvents, &QTimer::timeout, window, [pump] { pump(); });
    swiftEvents.start(16);
    if (screenshot) {
        auto capture = [window, path = QByteArray(screenshot)] {
            application().exit(qs_capture(window, path.constData()) ? 0 : 1);
        };
        QTimer::singleShot(qMax(0, qEnvironmentVariableIntValue("QTSWIFTUI_CAPTURE_DELAY_MS")), window, capture);
    }
    return application().exec();
}
int qs_scene_phase(QSWindow *window) {
    const auto app = QGuiApplication::applicationState();
    if (!window->isVisible() || window->isMinimized() || app == Qt::ApplicationHidden || app == Qt::ApplicationSuspended) return 0;
    return app == Qt::ApplicationActive && window->isActiveWindow() ? 2 : 1;
}
void qs_minimize(QSWindow *window, int minimized) {
    if (minimized) window->showMinimized();
    else { window->showNormal(); window->activateWindow(); }
    qs_flush();
}
double qs_window_scale(QSWindow *window) { return window->devicePixelRatioF(); }
void qs_set_key_handler(QSWindow *window, QSKeyHandler handler) { window->keyHandler = handler; }
void qs_set_drag_handler(QSWindow *window, QSDragHandler handler) { window->dragHandler = handler; }
void qs_group_gesture(QSWidget w, int taps, int drag, int simultaneous, double dragDistance, int inputs) {
    auto *group = static_cast<GroupWidget *>(w);
    group->tapCount = taps;
    group->windowDrag = drag;
    group->simultaneous = simultaneous;
    group->gestureInputs = inputs;
    group->pointerDrag.threshold = dragDistance;
    if (dragDistance < 0) group->pointerDrag.tracking = false;
}
void qs_close(QSWindow *window) {
    delete window;
    if (--liveWindows == 0) {
        // Tear Qt down while the platform plugin and its font database are still alive.
        delete ownedApplication;
        ownedApplication = nullptr;
    }
}

QSWidget qs_create(QSWindow *window, QSWidget parent, QSKind kind, int id) {
    QWidget *container = parent ? widget(parent) : window;
    switch (kind) {
    case QSLabel: {
        auto *label = new QLabel(container);
        label->setTextFormat(Qt::PlainText);
        label->setMargin(0);
        return label;
    }
    case QSAttributedLabel: {
        auto *label = new AttributedLabel(container);
        QObject::connect(label, &QLabel::linkActivated, window, [=](const QString &url) {
            window->event(window->context, id, QSActivate, url.toUtf8().constData());
        });
        return label;
    }
    case QSLink: case QSButton: {
        auto *button = new SwiftButton(container);
        if (kind == QSLink) {
            button->setCursor(Qt::PointingHandCursor);
        }
        QAccessible::registerAccessibleInterface(new AccessibleButton(button, kind == QSLink));
        window->observeFocus(button, id);
        QObject::connect(button, &QPushButton::clicked, window, [=] { window->event(window->context, id, QSActivate, ""); });
        QObject::connect(button, &QPushButton::pressed, window, [=] { window->event(window->context, id, QSPressedChanged, "1"); });
        QObject::connect(button, &QPushButton::released, window, [=] { window->event(window->context, id, QSPressedChanged, "0"); });
        return button;
    }
    case QSToggle: {
        auto *toggle = new QCheckBox(container);
        window->observeFocus(toggle, id);
        QObject::connect(toggle, &QCheckBox::toggled, window, [=](bool on) { window->event(window->context, id, QSActivate, on ? "1" : "0"); });
        return toggle;
    }
    case QSTextEditor: {
        auto *edit = new PlainTextEditor(container);
        edit->setProperty("qsScrollInput", QVariant::fromValue<QObject *>(new ScrollInput(edit)));
        window->observeFocus(edit, id);
        QObject::connect(edit, &QPlainTextEdit::textChanged, window, [=] {
            window->event(window->context, id, QSActivate, "");
        });
        return edit;
    }
    case QSEdit: case QSSecureEdit: {
        auto *edit = new QLineEdit(container);
        if (kind == QSSecureEdit) edit->setEchoMode(QLineEdit::Password);
        window->observeFocus(edit, id);
        QObject::connect(edit, &QLineEdit::textEdited, window, [=](const QString &s) { window->event(window->context, id, QSActivate, s.toUtf8().constData()); });
        QObject::connect(edit, &QLineEdit::returnPressed, window, [=] { window->event(window->context, id, QSSubmit, ""); });
        return edit;
    }
    case QSRaster: {
        auto *raster = new RasterWidget(container);
        raster->setAttribute(Qt::WA_TransparentForMouseEvents);
        return raster;
    }
    case QSCanvas: {
        auto *canvas = new CanvasWidget(container);
        canvas->setAttribute(Qt::WA_TransparentForMouseEvents);
        return canvas;
    }
    case QSGroup: {
        auto *group = new GroupWidget(container);
        window->observeFocus(group, id);
        QAccessible::registerAccessibleInterface(new AccessibleGroup(group));
        return group;
    }
    case QSSurface: {
        auto *surface = new Surface(container);
        surface->setAttribute(Qt::WA_TransparentForMouseEvents);
        return surface;
    }
    case QSScroll: {
        auto *scroll = new QScrollArea(container);
        scroll->setFrameShape(QFrame::NoFrame);
        scroll->setProperty("qsScrollInput", QVariant::fromValue<QObject *>(new ScrollInput(scroll)));
        for (auto *bar : {scroll->horizontalScrollBar(), scroll->verticalScrollBar()}) {
            QObject::connect(bar, &QScrollBar::valueChanged, window, [window] { window->schedule(); });
        }
        auto *content = new QWidget();
        scroll->setWidget(content);
        scroll->viewport()->setAutoFillBackground(false);
        content->setAutoFillBackground(false);
        return scroll;
    }
    case QSSlider: {
        auto *slider = new QSlider(Qt::Horizontal, container);
        slider->setRange(0, 10000);
        window->observeFocus(slider, id);
        QObject::connect(slider, &QSlider::valueChanged, window, [=](int n) { window->event(window->context, id, QSActivate, QByteArray::number(n / 10000.0).constData()); });
        return slider;
    }
    case QSBusyIndicator: return new BusyIndicator(container);
    case QSProgress: {
        auto *bar = new QProgressBar(container);
        bar->setTextVisible(false);
        return bar;
    }
    }
    return nullptr;
}
QSWidget qs_scroll_content(QSWidget w) { return static_cast<QScrollArea *>(w)->widget(); }
void qs_scroll_refining(QSWidget w) { widget(w)->setProperty("qsEstimatedExtent", true); }
void qs_scroll_size(QSWidget w, int width, int height) {
    auto *area = static_cast<QScrollArea *>(w);
    auto *bar = area->verticalScrollBar();
    const bool keepBottom = area->property("qsEstimatedExtent").toBool() &&
                            bar->maximum() > bar->minimum() && bar->value() == bar->maximum();
    area->setProperty("qsEstimatedExtent", false);
    area->widget()->resize(width, height);
    if (keepBottom) bar->setValue(bar->maximum());
}
QSRect qs_scroll_viewport(QSWidget w) {
    auto *area = static_cast<QScrollArea *>(w);
    return {double(area->horizontalScrollBar()->value()), double(area->verticalScrollBar()->value()),
            double(area->viewport()->width()), double(area->viewport()->height())};
}
void qs_scroll_input(QSWidget w, int enabled) {
    auto *input = static_cast<ScrollInput *>(widget(w)->property("qsScrollInput").value<QObject *>());
    input->setEnabled(enabled);
}
void qs_scroll_bounce(QSWidget w, int horizontal, int vertical) {
    using P = QScrollerProperties;
    auto *scroller = QScroller::scroller(static_cast<QAbstractScrollArea *>(w)->viewport());
    auto properties = scroller->scrollerProperties();
    const P defaults;
    auto policy = [&](int value, P::ScrollMetric metric) -> QVariant {
        switch (value) {
        case -1: return QVariant::fromValue(P::OvershootAlwaysOff);
        case 1: return QVariant::fromValue(P::OvershootAlwaysOn);
        case 2: return QVariant::fromValue(P::OvershootWhenScrollable);
        default: return defaults.scrollMetric(metric);
        }
    };
    properties.setScrollMetric(P::HorizontalOvershootPolicy, policy(horizontal, P::HorizontalOvershootPolicy));
    properties.setScrollMetric(P::VerticalOvershootPolicy, policy(vertical, P::VerticalOvershootPolicy));
    if (properties != scroller->scrollerProperties()) scroller->setScrollerProperties(properties);
}
void qs_scroll_axes(QSWidget w, int h, int v) {
    auto *scroll = static_cast<QScrollArea *>(w);
    scroll->setHorizontalScrollBarPolicy(h ? Qt::ScrollBarAsNeeded : Qt::ScrollBarAlwaysOff);
    scroll->setVerticalScrollBarPolicy(v ? Qt::ScrollBarAsNeeded : Qt::ScrollBarAlwaysOff);
}
void qs_destroy(QSWidget w) { delete widget(w); }
void qs_text(QSWidget w, const char *s) {
    auto text = QString::fromUtf8(s);
    if (auto *label = qobject_cast<QLabel *>(widget(w))) {
        if (label->text() != text) label->setText(text);
    }
    else if (auto *button = qobject_cast<QAbstractButton *>(widget(w))) button->setText(QString(text).replace('&', "&&"));
    else if (auto *edit = qobject_cast<QLineEdit *>(widget(w)); edit && edit->text() != text) edit->setText(text);
}
void qs_attributed_begin(QSWidget w) { static_cast<AttributedLabel *>(w)->begin(); }
void qs_attributed_append(QSWidget w, const char *text, size_t count, const char *link, const char *foreground, const char *background,
                          const char *family, double size, int weight, int italic) {
    static_cast<AttributedLabel *>(w)->append(QString::fromUtf8(text, qsizetype(count)), link, foreground, background, family, size, weight, italic);
}
void qs_attributed_finish(QSWidget w, int selectable) { static_cast<AttributedLabel *>(w)->finish(selectable); }
void qs_control_scale(QSWidget w, double scale) {
    auto *item = widget(w);
    if (item->property("qsControlScale").toDouble() == scale) return;
    item->setProperty("qsControlScale", scale);
    item->updateGeometry();
    item->update();
}
void qs_field_style(QSWidget w, int plain) {
    auto *edit = static_cast<QLineEdit *>(w);
    edit->setFrame(!plain);
    auto palette = edit->palette();
    palette.setColor(QPalette::Base, plain ? QColor(Qt::transparent) : application().palette().color(QPalette::Base));
    edit->setPalette(palette);
}
void qs_editor_text(QSWidget w, const char *utf8, size_t count) {
    static_cast<PlainTextEditor *>(w)->applyText(QString::fromUtf8(utf8, qsizetype(count)));
}
const unsigned char *qs_editor_value(QSWidget w, size_t *count) {
    auto *editor = static_cast<PlainTextEditor *>(w);
    editor->utf8 = editor->value().toUtf8();
    *count = size_t(editor->utf8.size());
    return reinterpret_cast<const unsigned char *>(editor->utf8.constData());
}
void qs_scroll_background(QSWidget w, int visible, int dark) {
    auto *area = static_cast<QAbstractScrollArea *>(w);
    auto *viewport = area->viewport();
    QPalette palette = area->palette();
    palette.setColor(QPalette::Base, dark ? QColor(30, 30, 30) : QColor(Qt::white));
    viewport->setPalette(palette);
    viewport->setBackgroundRole(QPalette::Base);
    viewport->setAutoFillBackground(visible);
    viewport->setAttribute(Qt::WA_OpaquePaintEvent, false);
}
void qs_editor_indicators(QSWidget w, int vertical) {
    static_cast<PlainTextEditor *>(w)->setVerticalScrollBarPolicy(vertical ? Qt::ScrollBarAsNeeded : Qt::ScrollBarAlwaysOff);
}
void qs_hint(QSWidget w, const char *s) { static_cast<QLineEdit *>(w)->setPlaceholderText(QString::fromUtf8(s)); }
void qs_checked(QSWidget w, int on) {
    const QSignalBlocker block(widget(w));
    static_cast<QCheckBox *>(w)->setChecked(on);
}
void qs_value(QSWidget w, double fraction) {
    const QSignalBlocker block(widget(w));
    if (auto *slider = qobject_cast<QSlider *>(widget(w))) slider->setValue(qRound(fraction * 10000));
    if (auto *bar = qobject_cast<QProgressBar *>(widget(w))) {
        bar->setRange(0, fraction < 0 ? 0 : 10000);
        if (fraction >= 0) bar->setValue(qRound(fraction * 10000));
    }
}
void qs_exit_scope(QSWidget w, int enabled) { widget(w)->setProperty("qsExit", bool(enabled)); }
void qs_selectable(QSWidget w, int enabled) {
    auto *label = static_cast<QLabel *>(w);
    Qt::TextInteractionFlags flags = enabled ? Qt::TextSelectableByMouse | Qt::TextSelectableByKeyboard : Qt::NoTextInteraction;
    if (label->textInteractionFlags() != flags) label->setTextInteractionFlags(flags);
}
int qs_register_font(const char *path) {
    auto &app = application();
    const QString font = QString::fromUtf8(path);
    auto loaded = app.property("qsFonts").toStringList();
    if (loaded.contains(font)) return 1;
    if (QFontDatabase::addApplicationFont(font) < 0) return 0;
    loaded.append(font);
    app.setProperty("qsFonts", loaded);
    return 1;
}
QSFontMetrics qs_font_metrics(const char *family, double size) {
    auto font = application().font();
    font.setFamily(QString::fromUtf8(family));
    auto raw = QRawFont::fromFont(font);
    raw.setPixelSize(size);
    return {raw.ascent(), raw.descent(), raw.xHeight()};
}
void qs_style(QSWidget w, const char *family, double points, int weight, int italic, double tracking,
              const char *color, int alignment, int wrap) {
    auto *item = widget(w);
    QFont font = application().font();
    if (*family) font.setFamily(QString::fromUtf8(family));
    font.setLetterSpacing(QFont::AbsoluteSpacing, tracking);
    font.setPixelSize(qMax(1, qRound(points)));
    font.setWeight(static_cast<QFont::Weight>(weight));
    font.setItalic(italic);
    item->setFont(font);
    QPalette palette = application().palette();
    QColor ink(QString::fromUtf8(color));
    if (ink.isValid()) {
        for (auto role : {QPalette::WindowText, QPalette::ButtonText, QPalette::Text}) {
            palette.setColor(QPalette::Active, role, ink);
            palette.setColor(QPalette::Inactive, role, ink);
        }
    }
    item->setPalette(palette);
    if (auto *editor = qobject_cast<QPlainTextEdit *>(item)) {
        auto option = editor->document()->defaultTextOption();
        const auto desired = Qt::AlignAbsolute | (alignment < 0 ? Qt::AlignLeft : alignment > 0 ? Qt::AlignRight : Qt::AlignHCenter);
        if (option.alignment() != desired) {
            option.setAlignment(desired);
            editor->document()->setDefaultTextOption(option);
        }
    }
    if (auto *label = qobject_cast<QLabel *>(item)) {
        label->setWordWrap(wrap);
        label->setAlignment(Qt::AlignAbsolute | Qt::AlignVCenter | (alignment < 0 ? Qt::AlignLeft : alignment > 0 ? Qt::AlignRight : Qt::AlignHCenter));
    }
}
void qs_surface(QSWidget w, const char *color, double radius) {
    auto *surface = static_cast<Surface *>(w);
    surface->fill = QColor(QString::fromUtf8(color));
    surface->radius = radius;
    surface->update();
}
QSPath *qs_path_new() { return new QSPath(); }
void qs_path_delete(QSPath *path) { delete path; }
QSRect qs_path_bounds(const QSPath *path) {
    if (path->elementCount() == 0) return {0, 0, -1, -1};
    const auto rect = path->boundingRect();
    return {rect.x(), rect.y(), rect.width(), rect.height()};
}
QSSize qs_path_position(const QSPath *path) {
    if (path->elementCount() == 0) return {NAN, NAN};
    auto point = path->currentPosition();
    return {point.x(), point.y()};
}
int qs_path_contains(const QSPath *path, double x, double y, int evenOdd) {
    auto copy = *path;
    copy.setFillRule(evenOdd ? Qt::OddEvenFill : Qt::WindingFill);
    return copy.contains(QPointF(x, y));
}
void qs_path_append(QSPath *path, const QSPath *other, QSAffine t) { path->addPath(transform(t).map(*other)); }
void qs_path_stroke(QSPath *target, const QSPath *source, double width, int cap, int join, double miterLimit,
                    const double *dash, size_t count, double phase) {
    if (!(width > 0)) return;
    QPainterPathStroker stroke;
    stroke.setWidth(width);
    stroke.setCapStyle(cap == 1 ? Qt::RoundCap : cap == 2 ? Qt::SquareCap : Qt::FlatCap);
    stroke.setJoinStyle(join == 1 ? Qt::RoundJoin : join == 2 ? Qt::BevelJoin : Qt::SvgMiterJoin);
    stroke.setMiterLimit(miterLimit);
    if (count) {
        QList<qreal> pattern;
        double total = 0;
        for (size_t i = 0; i < count; ++i) {
            if (!std::isfinite(dash[i]) || dash[i] < 0) return;
            pattern.append(dash[i] / width);
            total += dash[i];
        }
        if (total > 0) {
            if (count % 2) pattern += QList<qreal>(pattern);
            stroke.setDashPattern(pattern);
            stroke.setDashOffset(phase / width);
        }
    }
    target->addPath(stroke.createStroke(*source));
}
void qs_path_trim(QSPath *target, const QSPath *source, double from, double to) {
    target->addPath(trimmed(*source, from, to));
}
void qs_path_clip(QSPath *target, const QSPath *source, int evenOdd, int inverse) {
    QPainterPath shape = *source;
    shape.setFillRule(evenOdd ? Qt::OddEvenFill : Qt::WindingFill);
    static_cast<QPainterPath &>(*target) = inverse ? target->subtracted(shape) : target->intersected(shape);
}
void qs_canvas_clip(QSWidget w, const QSPath *path) {
    static_cast<CanvasWidget *>(w)->drawings.back().clip = *path;
}
void qs_group_clip(QSWidget w, const QSPath *path, int evenOdd, int antialias) {
    auto *group = static_cast<GroupWidget *>(w);
    auto *effect = dynamic_cast<ShapeClipEffect *>(group->graphicsEffect());
    if (!effect) {
        effect = new ShapeClipEffect(group);
        group->setGraphicsEffect(effect);
    }
    effect->path = *path;
    effect->path.setFillRule(evenOdd ? Qt::OddEvenFill : Qt::WindingFill);
    effect->antialias = antialias;
    effect->update();
}
void qs_group_semantics(QSWidget w, int heading, int modal) {
    auto *group = static_cast<GroupWidget *>(w);
    group->heading = heading;
    group->modal = modal;
    group->exposeChildren = !heading || modal;
}
void qs_surface_path(QSWidget w, const QSPath *path, int evenOdd, int antialias) {
    auto *surface = static_cast<Surface *>(w);
    surface->customPath = true;
    surface->path = *path;
    surface->path.setFillRule(evenOdd ? Qt::OddEvenFill : Qt::WindingFill);
    surface->antialias = antialias;
    surface->update();
}
void qs_canvas_clear(QSWidget w) {
    auto *canvas = static_cast<CanvasWidget *>(w);
    canvas->drawings.clear();
    canvas->update();
}
void qs_canvas_path(QSWidget w, const QSPath *path, QSAffine t, double opacity, double lineWidth, int evenOdd, int antialias) {
    auto *canvas = static_cast<CanvasWidget *>(w);
    auto &drawing = canvas->drawings.emplace_back(Drawing{*path, transform(t), opacity, lineWidth, bool(antialias), Qt::black, {}});
    drawing.path.setFillRule(evenOdd ? Qt::OddEvenFill : Qt::WindingFill);
}
void qs_canvas_blur(QSWidget w, double radius, unsigned blurOptions, unsigned filterOptions) {
    if (std::isfinite(radius) && radius > 0)
        static_cast<CanvasWidget *>(w)->drawings.back().filters.push_back({radius, blurOptions, filterOptions});
}
void qs_canvas_color(QSWidget w, const char *color) {
    static_cast<CanvasWidget *>(w)->drawings.back().color = QColor(QString::fromUtf8(color));
}
void qs_canvas_gradient(QSWidget w, double x1, double y1, double x2, double y2, unsigned options,
                        const QSGradientStop *stops, size_t count) {
    auto &gradient = static_cast<CanvasWidget *>(w)->drawings.back().gradient.emplace(x1, y1, x2, y2);
    gradient.setSpread((options & 2) ? QGradient::ReflectSpread : (options & 1) ? QGradient::RepeatSpread : QGradient::PadSpread);
    QGradientStops colors;
    colors.reserve(count);
    for (size_t i = 0; i < count; ++i) colors.append({stops[i].location, QColor::fromRgba(stops[i].argb)});
    gradient.setStops(colors);
}
void qs_direction(QSWidget w, int rtl) { widget(w)->setLayoutDirection(rtl ? Qt::RightToLeft : Qt::LeftToRight); }
void qs_hit_testing(QSWidget w, int enabled) { widget(w)->setAttribute(Qt::WA_TransparentForMouseEvents, !enabled); }
void qs_path_step(QSPath *target, int op, double x, double y, double a, double b, double c, double d) {
    auto &path = *target;
    switch (op) {
    case 0: path.moveTo(x, y); break;
    case 1: path.lineTo(x, y); break;
    case 2: path.quadTo(x, y, a, b); break;
    case 3: path.cubicTo(x, y, a, b, c, d); break;
    case 4: path.closeSubpath(); break;
    case 5: path.addRect(x, y, a, b); break;
    case 6: path.addEllipse(x, y, a, b); break;
    }
}
void qs_group(QSWidget w, int behavior, int isImage, int updatesFrequently, const char *value) {
    auto *group = static_cast<GroupWidget *>(w);
    group->exposeChildren = behavior == 1;
    group->combineChildren = behavior == 2;
    group->isImage = isImage;
    group->updatesFrequently = updatesFrequently;
    const QString next = QString::fromUtf8(value);
    if (group->accessibleValue != next) {
        group->accessibleValue = next;
        QAccessibleValueChangeEvent changed(group, next);
        QAccessible::updateAccessibility(&changed);
    }
}
void qs_adjustable(QSWidget w, int adjustable) { static_cast<GroupWidget *>(w)->adjustable = adjustable; }
void qs_group_hidden(QSWidget w, int hidden) { static_cast<GroupWidget *>(w)->accessibilityHidden = hidden; }
void qs_group_shape(QSWidget w, const QSPath *path, int evenOdd) {
    auto *group = static_cast<GroupWidget *>(w);
    group->contentShape = *path;
    group->contentShape->setFillRule(evenOdd ? Qt::OddEvenFill : Qt::WindingFill);
}
void qs_focus_effect(QSWidget w, int enabled) { widget(w)->setProperty("qsNoFocusEffect", !enabled); }
void qs_group_focus(QSWidget w, int enabled, int interactions) {
    auto *group = widget(w);
    QWidget *proxy = group->focusProxy();
    if (!proxy || !group->isAncestorOf(proxy)) {
        proxy = nullptr;
        for (auto *child : group->findChildren<QWidget *>()) {
            if (child->focusPolicy() == Qt::NoFocus) continue;
            proxy = child;
            break;
        }
        group->setFocusProxy(proxy);
    }
    group->setProperty("qsFocusable", bool(enabled && interactions));
    const auto policy = !enabled || !interactions ? Qt::NoFocus : Qt::StrongFocus;
    if (group->focusPolicy() != policy) group->setFocusPolicy(policy);
    if (proxy && proxy->focusPolicy() != policy) proxy->setFocusPolicy(policy);
}
void qs_group_hover(QSWidget w, int enabled) { widget(w)->setProperty("qsHover", bool(enabled)); }
void qs_help(QSWidget w, const char *text) { widget(w)->setToolTip(QString::fromUtf8(text)); }
void qs_group_rotation(QSWidget w, double degrees, double anchorX, double anchorY) {
    auto *item = widget(w);
    if (std::remainder(degrees, 360.0) == 0) {
        if (item->graphicsEffect()) item->setGraphicsEffect(nullptr);
        return;
    }
    auto *effect = dynamic_cast<RotationEffect *>(item->graphicsEffect());
    if (!effect) {
        effect = new RotationEffect(item);
        item->setGraphicsEffect(effect);
    }
    effect->setRotation(degrees, QPointF(anchorX, anchorY));
}
void qs_group_spin(QSWidget w, int milliseconds) {
    auto *item = widget(w);
    if (milliseconds <= 0) { item->setGraphicsEffect(nullptr); return; }
    auto *effect = dynamic_cast<RotationEffect *>(item->graphicsEffect());
    if (!effect) {
        effect = new RotationEffect(item);
        item->setGraphicsEffect(effect);
    }
    auto *animation = effect->findChild<QVariantAnimation *>();
    if (!animation) {
        animation = new QVariantAnimation(effect);
        animation->setStartValue(0.0);
        animation->setEndValue(360.0);
        animation->setLoopCount(-1);
        QObject::connect(animation, &QVariantAnimation::valueChanged, effect, [effect](const QVariant &value) {
            effect->setRotation(value.toDouble(), QPointF(0.5, 0.5));
        });
    }
    animation->setDuration(milliseconds);
    if (animation->state() != QAbstractAnimation::Running) animation->start();
}
void qs_drawing_only(QSWidget w) {
    auto *item = widget(w);
    item->setProperty("qsDrawingOnly", true);
    item->hide();
}
void qs_view_blur(QSWidget w, double radius, int opaque) {
    auto *item = widget(w);
    if (!(radius > 0) || !std::isfinite(radius)) {
        if (item->graphicsEffect()) item->setGraphicsEffect(nullptr);
        return;
    }
    auto *effect = dynamic_cast<ViewBlur *>(item->graphicsEffect());
    if (!effect) { effect = new ViewBlur; item->setGraphicsEffect(effect); }
    effect->configure(radius, opaque);
}
void qs_alpha_mask(QSWidget w, QSWidget stencil) {
    auto *item = widget(w);
    if (auto *effect = dynamic_cast<AlphaMaskEffect *>(item->graphicsEffect())) effect->update();
    else item->setGraphicsEffect(new AlphaMaskEffect(widget(stencil)));
}
void qs_group_opacity(QSWidget w, double value) {
    auto *item = widget(w);
    value = qBound(0.0, value, 1.0);
    if (value == 1.0) {
        if (item->graphicsEffect()) item->setGraphicsEffect(nullptr);
        return;
    }
    auto *effect = qobject_cast<QGraphicsOpacityEffect *>(item->graphicsEffect());
    if (!effect) {
        effect = new QGraphicsOpacityEffect(item);
        item->setGraphicsEffect(effect);
    }
    effect->setOpacity(value);
}
unsigned qs_pixel(QSWindow *window, int x, int y) {
    return window->grab().toImage().pixelColor(x, y).rgba();
}
void qs_plain_button(QSWidget w, int plain) {
    auto *button = static_cast<QPushButton *>(w);
    button->setFlat(plain);
}
int qs_button_down(QSWidget w) { return static_cast<QPushButton *>(w)->isDown(); }
void qs_focus(QSWidget w, int active) {
    auto *item = widget(w);
    if (!item->isEnabled() || item->focusPolicy() == Qt::NoFocus) return;
    if (active && !item->hasFocus()) item->setFocus(Qt::OtherFocusReason);
    else if (!active && item->hasFocus()) item->clearFocus();
}
void qs_enabled(QSWidget w, int enabled) { widget(w)->setEnabled(enabled); }
void qs_accessible_control(QSWidget w, int selected, int button, int toggle) {
    auto *item = widget(w);
    const bool changed = item->property("qsSelected").toBool() != bool(selected);
    item->setProperty("qsSelected", bool(selected));
    item->setProperty("qsAXButton", bool(button));
    item->setProperty("qsAXToggle", bool(toggle));
    if (changed) {
        QAccessible::State state;
        state.selected = true;
        state.checked = bool(toggle);
        QAccessibleStateChangeEvent event(item, state);
        QAccessible::updateAccessibility(&event);
    }
}
void qs_accessibility(QSWidget w, const char *label, const char *identifier) {
    widget(w)->setAccessibleName(QString::fromUtf8(label));
    widget(w)->setObjectName(QString::fromUtf8(identifier));
}
QSSize qs_measure(QSWidget w, double width) {
    auto *item = widget(w);
    item->ensurePolished();
    if (auto *rich = dynamic_cast<AttributedLabel *>(item)) {
        const auto hint = rich->measure(width);
        return {hint.width(), hint.height()};
    }
    if (auto *label = qobject_cast<QLabel *>(item)) {
        auto metrics = label->fontMetrics();
        auto flags = Qt::TextExpandTabs | Qt::TextDontClip;
        auto natural = metrics.boundingRect(QRect(0, 0, 1000000, 1000000), flags, label->text());
        int ideal = qMax(0, natural.width());
        int available = width < 0 || !std::isfinite(width) ? ideal : qMin(ideal, qMax(1, qRound(width)));
        if (label->wordWrap() && available < ideal) flags |= Qt::TextWordWrap;
        auto box = metrics.boundingRect(QRect(0, 0, available, 1000000), flags, label->text());
        return {double(available), double(qMax(metrics.height(), box.height()))};
    }
    if (auto *editor = qobject_cast<QPlainTextEdit *>(item)) {
        return {0, double(editor->fontMetrics().height() * editor->blockCount())};
    }
    auto size = item->sizeHint();
    return {double(size.width()), double(size.height())};
}
QSSize qs_tap_location(QSWidget w) {
    const auto point = static_cast<GroupWidget *>(w)->tapLocation;
    return {point.x(), point.y()};
}
QSSize qs_origin(QSWidget w) {
    auto *item = widget(w);
    const auto *group = dynamic_cast<GroupWidget *>(item);
    const QPoint origin = group ? group->layoutRect.topLeft() : QPoint();
    const auto point = QPointF(item->mapTo(item->window(), origin)) + item->property("qsFraction").toPointF();
    return {point.x(), point.y()};
}
void qs_place(QSWidget w, double x, double y, double width, double height) {
    auto *item = widget(w);
    const auto parentFraction = item->parentWidget()->property("qsFraction").toPointF();
    const QPointF origin(x + parentFraction.x(), y + parentFraction.y());
    // Keep fractional placement through grouping widgets. QPainter can retain it
    // when a SwiftUI drawing falls between Qt's integer widget coordinates.
    const bool painted = dynamic_cast<Surface *>(item) || dynamic_cast<CanvasWidget *>(item) || dynamic_cast<RasterWidget *>(item);
    const bool enclose = painted || dynamic_cast<GroupWidget *>(item);
    const int left = enclose ? qFloor(origin.x()) : qRound(origin.x());
    const int top = enclose ? qFloor(origin.y()) : qRound(origin.y());
    const int right = enclose ? qCeil(origin.x() + width) : qRound(origin.x() + width);
    const int bottom = enclose ? qCeil(origin.y() + height) : qRound(origin.y() + height);
    item->setProperty("qsFraction", origin - QPointF(left, top));
    if (painted) item->setProperty("qsSize", QSizeF(width, height));
    QRect geometry(left, top, width > 0 ? qMax(0, right - left) : 0, height > 0 ? qMax(0, bottom - top) : 0);
    if (auto *surface = dynamic_cast<Surface *>(item); surface && surface->customPath && !geometry.isEmpty()) {
        // A negative inset or a centered stroke can draw outside a shape's layout frame.
        const auto bounds = surface->path.boundingRect().translated(origin).toAlignedRect();
        const QRect viewport(item->parentWidget()->mapFrom(item->window(), QPoint()), item->window()->size());
        geometry = geometry.united(bounds.intersected(viewport));
        item->setProperty("qsFraction", origin - QPointF(geometry.topLeft()));
    }
    item->setGeometry(geometry);
    if (auto *group = dynamic_cast<GroupWidget *>(item)) group->layoutRect = group->rect();
    if (!item->property("qsDrawingOnly").toBool()) {
        item->raise();
        item->show();
    }
}

void qs_match_place(QSWidget drawing, QSWidget marker, double x, double y, double width, double height) {
    auto *layer = widget(drawing);
    auto *parent = widget(marker);
    auto *window = parent->window();
    QWidget *branch = nullptr;
    const QRectF target(x, y, width, height);
    while (parent != window) {
        const auto origin = qs_origin(parent);
        if (QRectF(origin.width, origin.height, parent->width(), parent->height()).contains(target)) break;
        // Structural wrappers and flat button labels permit overflow. Retain explicit
        // clipping and scrolling boundaries even while the two views exchange places.
        const auto *button = dynamic_cast<SwiftButton *>(parent);
        if (parent->graphicsEffect() || (!dynamic_cast<GroupWidget *>(parent) && !(button && button->isFlat()))) break;
        branch = parent;
        parent = parent->parentWidget();
    }
    if (layer->parentWidget() != parent) layer->setParent(parent);
    const auto origin = parent == window ? QSSize{0, 0} : qs_origin(parent);
    qs_place(layer, x - origin.width, y - origin.height, width, height);
    if (branch) {
        // A background moving between sibling controls still paints behind their labels.
        for (auto *sibling : parent->findChildren<QWidget *>(QString(), Qt::FindDirectChildrenOnly)) {
            if (sibling == branch || dynamic_cast<SwiftButton *>(sibling)) {
                layer->stackUnder(sibling);
                break;
            }
        }
    }
}
void qs_group_finish_layout(QSWidget w, int sizeToPositionedContent) {
    auto *group = static_cast<GroupWidget *>(w);
    group->sizedToContent = sizeToPositionedContent && !group->graphicsEffect() && !group->contentShape;
    // A frame around paint-only descendants must leave the controls underneath reachable.
    const auto children = group->findChildren<QWidget *>(QString(), Qt::FindDirectChildrenOnly);
    if (!group->tapCount && !group->windowDrag && group->pointerDrag.threshold < 0 && !group->property("qsHover").toBool() &&
        std::all_of(children.begin(), children.end(), [](QWidget *child) {
            return child->isHidden() || child->testAttribute(Qt::WA_TransparentForMouseEvents);
        })) group->setAttribute(Qt::WA_TransparentForMouseEvents);
    // A clip or transform has its own drawing coordinate space. Structural
    // groups (focus, accessibility, hover) must allow child paint to overflow.
    if (group->graphicsEffect() || group->contentShape) return;
    const QRect viewport(group->mapFrom(group->window(), QPoint()), group->window()->size());
    // A positioned child can claim the complete layout proposal while occupying a
    // small part of it. Keep its logical origin for gesture coordinates but bound
    // the native event and accessibility target to the positioned content.
    QRect paint = group->sizedToContent ? QRect() : group->rect();
    for (auto *child : children) {
        if (child->isHidden()) continue;
        QRect footprint = child->geometry();
        if (group->sizedToContent && child->graphicsEffect())
            footprint = child->graphicsEffect()->boundingRectFor(child->rect()).translated(child->pos()).toAlignedRect();
        paint = paint.united(footprint.intersected(viewport));
    }
    if (paint == group->rect()) return;
    const QPoint offset = -paint.topLeft();
    group->layoutRect.translate(offset);
    group->setGeometry(QRect(group->pos() - offset, paint.size()));
    for (auto *child : children) child->move(child->pos() + offset);
}

int qs_accessible_value_is(QSWindow *window, const char *name, const char *value) {
    for (auto *widget : window->findChildren<QWidget *>()) {
        auto *object = QAccessible::queryAccessibleInterface(widget);
        if (object && !object->state().invisible && object->text(QAccessible::Name) == QString::fromUtf8(name)
            && object->text(QAccessible::Value) == QString::fromUtf8(value)) return 1;
    }
    return 0;
}
int qs_accessible_checked(QSWindow *window, const char *name) {
    for (auto *widget : window->findChildren<QWidget *>()) {
        auto *object = QAccessible::queryAccessibleInterface(widget);
        if (!object || object->state().invisible || !object->state().checkable) continue;
        if (object->text(QAccessible::Name) == QString::fromUtf8(name)) return object->state().checked ? 1 : 0;
    }
    return -1;
}
int qs_accessible_element(QSWindow *window, const char *name, int childCount, const char *action) {
    for (auto *widget : window->findChildren<QWidget *>()) {
        auto *object = QAccessible::queryAccessibleInterface(widget);
        if (!object || object->state().invisible || object->text(QAccessible::Name) != QString::fromUtf8(name)) continue;
        if (childCount >= 0 && object->childCount() != childCount) continue;
        if (action) {
            auto *actions = object->actionInterface();
            if (!actions || !actions->actionNames().contains(QString::fromUtf8(action))) continue;
            actions->doAction(QString::fromUtf8(action));
            qs_flush();
        }
        return 1;
    }
    return 0;
}
int qs_click(QSWindow *window, const char *id) {
    auto *button = window->findChild<QAbstractButton *>(QString::fromUtf8(id));
    if (!button || !button->isEnabled()) return 0;
    button->click();
    qs_flush();
    return 1;
}
int qs_enter(QSWindow *window, const char *id, const char *value) {
    auto *edit = window->findChild<QLineEdit *>(QString::fromUtf8(id));
    if (!edit || !edit->isEnabled()) return 0;
    edit->selectAll();
    edit->insert(QString::fromUtf8(value));
    qs_flush();
    return 1;
}
int qs_commit_text(QSWindow *window, const char *utf8, size_t count) {
    auto *target = window->focusWidget();
    if (!target || !target->isEnabled() || !target->testAttribute(Qt::WA_InputMethodEnabled)) return 0;
    QInputMethodEvent input;
    input.setCommitString(QString::fromUtf8(utf8, qsizetype(count)));
    QApplication::sendEvent(target, &input);
    qs_flush();
    return input.isAccepted();
}
int qs_send_key_sequence(QSWindow *window, const char *keys) { return qs_send_repeated_key(window, keys, 0); }
int qs_send_repeated_key(QSWindow *window, const char *keys, int repeats) {
    const auto sequence = QKeySequence::fromString(QString::fromUtf8(keys), QKeySequence::PortableText);
    if (sequence.count() != 1 || !window->windowHandle()) return 0;
    auto combination = sequence[0];
    QKeyEvent press(QEvent::KeyPress, combination.key(), combination.keyboardModifiers());
    QKeyEvent release(QEvent::KeyRelease, combination.key(), combination.keyboardModifiers());
    QApplication::sendEvent(window->windowHandle(), &press);
    for (int i = 0; i < repeats; ++i) {
        QKeyEvent repeated(QEvent::KeyPress, combination.key(), combination.keyboardModifiers(), QString(), true);
        QApplication::sendEvent(window->windowHandle(), &repeated);
    }
    QApplication::sendEvent(window->windowHandle(), &release);
    qs_flush();
    return 1;
}
int qs_key_escape(QSWindow *window) {
    QKeyEvent key(QEvent::KeyPress, Qt::Key_Escape, Qt::NoModifier);
    QApplication::sendEvent(window->focusWidget() ? window->focusWidget() : window, &key);
    qs_flush();
    return key.isAccepted();
}
int qs_select_text(QSWindow *window, const char *id, int start, int length, const char *expected) {
    auto *label = window->findChild<QLabel *>(QString::fromUtf8(id));
    if (!label || !(label->textInteractionFlags() & Qt::TextSelectableByMouse)) return 0;
    label->setSelection(start, length);
    return label->selectedText() == QString::fromUtf8(expected);
}
int qs_uses_family(QSWindow *window, const char *text, const char *family) {
    for (auto *label : window->findChildren<QLabel *>()) {
        if (label->text() == QString::fromUtf8(text))
            return QFontInfo(label->font()).family() == QString::fromUtf8(family);
    }
    return 0;
}
int qs_fixed_font(QSWindow *window, const char *id) {
    auto *label = window->findChild<QLabel *>(QString::fromUtf8(id));
    return label && QFontInfo(label->font()).fixedPitch();
}
int qs_key_return(QSWindow *window, const char *id) {
    auto *edit = window->findChild<QLineEdit *>(QString::fromUtf8(id));
    if (!edit || !edit->isEnabled()) return 0;
    QKeyEvent press(QEvent::KeyPress, Qt::Key_Return, Qt::NoModifier);
    QApplication::sendEvent(edit, &press);
    QKeyEvent release(QEvent::KeyRelease, Qt::Key_Return, Qt::NoModifier);
    QApplication::sendEvent(edit, &release);
    qs_flush();
    return 1;
}
int qs_tab(QSWindow *window) {
    QKeyEvent tab(QEvent::KeyPress, Qt::Key_Tab, Qt::NoModifier);
    QApplication::sendEvent(window->focusWidget() ? window->focusWidget() : window, &tab);
    qs_flush();
    return tab.isAccepted();
}
int qs_drag_pointer(QSWindow *window, int x1, int y1, int x2, int y2, int steps) {
    const QPointF start(x1, y1), end(x2, y2);
    QPointer<QWidget> target = window->childAt(start.toPoint());
    if (!target || steps < 1) return 0;
    auto send = [&](QEvent::Type type, QPointF position, int tick) {
        if (!target) return;
        const auto global = window->mapToGlobal(position);
        QMouseEvent mouse(type, target->mapFromGlobal(global), global,
                          type == QEvent::MouseMove ? Qt::NoButton : Qt::LeftButton,
                          type == QEvent::MouseButtonRelease ? Qt::NoButton : Qt::LeftButton, Qt::NoModifier);
        mouse.setTimestamp(1000 + 16 * tick);
        QApplication::sendEvent(target, &mouse);
        qs_flush();
    };
    send(QEvent::MouseButtonPress, start, 0);
    for (int i = 1; i <= steps; ++i) send(QEvent::MouseMove, start + (end - start) * i / steps, i);
    send(QEvent::MouseButtonRelease, end, steps + 1);
    return 1;
}
static int clickPoint(QSWindow *window, int x, int y, const QPointingDevice *device) {
    const QPoint point(x, y);
    QWidget *target = window->childAt(point);
    if (!target) return 0;
    const auto global = window->mapToGlobal(point);
    // Route through the platform window so Qt updates mouse focus and the implicit grab.
    QMouseEvent press(QEvent::MouseButtonPress, point, global, Qt::LeftButton, Qt::LeftButton, Qt::NoModifier, device);
    QApplication::sendEvent(window->windowHandle(), &press);
    QMouseEvent release(QEvent::MouseButtonRelease, point, global, Qt::LeftButton, Qt::NoButton, Qt::NoModifier, device);
    QApplication::sendEvent(window->windowHandle(), &release);
    qs_flush();
    return 1;
}
int qs_click_point(QSWindow *window, int x, int y) {
    return clickPoint(window, x, y, QPointingDevice::primaryPointingDevice());
}
int qs_click_device(QSWindow *window, int x, int y, int kind) {
    using Type = QInputDevice::DeviceType;
    using Pointer = QPointingDevice::PointerType;
    const Type type = kind == 1 ? Type::TouchScreen : kind == 2 ? Type::TouchPad : kind == 4 ? Type::Stylus : Type::Mouse;
    const Pointer pointer = kind == 1 || kind == 2 ? Pointer::Finger : kind == 4 ? Pointer::Pen : Pointer::Generic;
    QPointingDevice device("Test input", 40 + kind, type, pointer, QInputDevice::Capability::Position, 1, 1);
    return clickPoint(window, x, y, &device);
}
int qs_click_named_button(QSWindow *window, const char *name) {
    for (auto *button : window->findChildren<QAbstractButton *>()) {
        auto *accessible = QAccessible::queryAccessibleInterface(button);
        if (!accessible || accessible->text(QAccessible::Name) != QString::fromUtf8(name)) continue;
        const auto center = button->mapTo(window, button->rect().center());
        return qs_click_point(window, center.x(), center.y());
    }
    return 0;
}
int qs_has_focus(QSWindow *window, const char *id) {
    auto *item = window->findChild<QWidget *>(QString::fromUtf8(id));
    return item && item->hasFocus();
}
int qs_pointer_button(QSWindow *window, int x, int y, int down) {
    const QPoint location(x, y);
    QWidget *target = window->childAt(location);
    if (!target) return 0;
    const auto local = target->mapFrom(window, location);
    const auto global = window->mapToGlobal(location);
    QMouseEvent input(down ? QEvent::MouseButtonPress : QEvent::MouseButtonRelease, local, global,
                      Qt::LeftButton, down ? Qt::LeftButton : Qt::NoButton, Qt::NoModifier);
    QApplication::sendEvent(target, &input);
    qs_flush();
    return 1;
}
int qs_mouse_button(QSWindow *window, const char *id, int down) {
    auto *button = window->findChild<QAbstractButton *>(QString::fromUtf8(id));
    if (!button || !button->isEnabled()) return 0;
    const auto location = button->mapTo(window, button->rect().center());
    return qs_pointer_button(window, location.x(), location.y(), down);
}
int qs_mouse_click(QSWindow *window, const char *id) {
    return qs_mouse_button(window, id, 1) && qs_mouse_button(window, id, 0);
}
int qs_hover(QSWindow *window, const char *id, int inside) {
    for (auto *item : window->findChildren<QWidget *>(QString::fromUtf8(id))) {
        if (!item->property("qsHover").toBool()) continue;
        if (inside) {
            const QPointF position = item->rect().center();
            QEnterEvent enter(position, item->mapTo(window, position), item->mapToGlobal(position));
            QApplication::sendEvent(item, &enter);
        } else {
            QEvent leave(QEvent::Leave);
            QApplication::sendEvent(item, &leave);
        }
        qs_flush();
        return 1;
    }
    return 0;
}
int qs_is_named_link(QSWindow *window, const char *id, const char *name) {
    auto *item = window->findChild<QAbstractButton *>(QString::fromUtf8(id));
    if (!item) return 0;
    auto *accessible = QAccessible::queryAccessibleInterface(item);
    return accessible && accessible->role() == QAccessible::Link && accessible->text(QAccessible::Name) == QString::fromUtf8(name);
}
int qs_has_help(QSWindow *window, const char *id, const char *expected) {
    auto *item = window->findChild<QWidget *>(QString::fromUtf8(id));
    return item && item->toolTip() == QString::fromUtf8(expected);
}
int qs_can_overshoot(QSWindow *window, int horizontal) {
    auto *area = window->findChild<QAbstractScrollArea *>();
    if (!area) return -1;
    using P = QScrollerProperties;
    auto properties = QScroller::scroller(area->viewport())->scrollerProperties();
    auto policy = properties.scrollMetric(horizontal ? P::HorizontalOvershootPolicy : P::VerticalOvershootPolicy).toInt();
    auto *bar = horizontal ? area->horizontalScrollBar() : area->verticalScrollBar();
    return policy == P::OvershootAlwaysOn || (policy == P::OvershootWhenScrollable && bar->maximum() > bar->minimum());
}
int qs_scroll_wheel(QSWindow *window, int x, int y, int steps) {
    const QPoint point(x, y);
    QAbstractScrollArea *area = nullptr;
    for (auto *target = window->childAt(point); target && !area; target = target->parentWidget())
        area = qobject_cast<QAbstractScrollArea *>(target);
    if (!area) return 0;
    auto *viewport = area->viewport();
    QWheelEvent event(viewport->mapFrom(window, point), window->mapToGlobal(point), {}, QPoint(0, 120 * steps),
                      Qt::NoButton, Qt::NoModifier, Qt::NoScrollPhase, false);
    QApplication::sendEvent(viewport, &event);
    qs_flush();
    return event.isAccepted();
}
int qs_scroll_to_start(QSWindow *window) {
    auto *area = window->findChild<QScrollArea *>();
    if (!area) return 0;
    area->verticalScrollBar()->setValue(area->verticalScrollBar()->minimum());
    qs_flush();
    return 1;
}
int qs_scroll_to_end(QSWindow *window) {
    auto *area = window->findChild<QScrollArea *>();
    if (!area) return 0;
    auto *bar = area->verticalScrollBar();
    bar->setValue(bar->maximum());
    qs_flush();
    return bar->value() > 0 && bar->value() == bar->maximum();
}
int qs_read_text(QSWindow *window, const char *id, const char *expected) {
    if (!id) {
        for (const auto *label : window->findChildren<QLabel *>()) {
            if (label->text() == QString::fromUtf8(expected)) return 1;
        }
        return 0;
    }
    auto *label = window->findChild<QLabel *>(QString::fromUtf8(id));
    return label && label->text() == QString::fromUtf8(expected);
}
