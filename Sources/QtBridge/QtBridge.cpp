#include "QtBridge.h"
#include <QMenuBar>
#include <QMessageBox>
#include "AlphaMask.hpp"
#include "BusyIndicator.hpp"
#include "ViewBlur.hpp"
#include "ViewShadow.hpp"
#include "ScrollInput.hpp"
#include "AttributedLabel.hpp"
#include "PlainLabel.hpp"
#include "CanvasBlur.hpp"
#include "MaterialBackdrop.hpp"
#include "PointerDrag.hpp"
#include "Magnification.hpp"
#include "NativeMenu.hpp"
#include "NativeTransfer.hpp"
#include "ClipboardCommands.hpp"
#include "NativePopover.hpp"
#include <QGestureEvent>
#include <QNativeGestureEvent>
#include <QPixmapCache>
#include "RichTextEditor.hpp"
#include "TextParagraph.hpp"
#include <QClipboard>
#include <QContextMenuEvent>
#include "WindowShortcuts.hpp"
#include "PathTrim.hpp"
#include "RasterWidget.hpp"
#include <QApplication>
#include "FileImporter.hpp"
#include <string.h>
#include <QAccessibleWidget>
#include <QCheckBox>
#include <QDir>
#include <QDesktopServices>
#include <QUrl>
#include <QWindow>
#include <QScreen>
#include <QScopeGuard>
#include <QWheelEvent>
#include <QVariantAnimation>
#include <algorithm>
#include <QLabel>
#include <QFontInfo>
#include <QRawFont>
#include <QFontDatabase>
#include <QGraphicsOpacityEffect>
#include <QEnterEvent>
#include <QHoverEvent>
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
#include <QComboBox>
#include "SymbolIcons.hpp"
#include "PickerButtons.hpp"
#include <QStandardItemModel>
#include <QResizeEvent>
#include <QWindowStateChangeEvent>
#include <QScrollArea>
#include <QScrollBar>
#include <QScroller>
#include <QSignalBlocker>
#include <QSlider>
#include <QTimer>
#include <cmath>
#include <QFile>
#include <optional>
#include <vector>

struct QSPath : QPainterPath {};

namespace {
QTransform transform(QSAffine t) { return QTransform(t.a, t.b, t.c, t.d, t.tx, t.ty); }
int eventModifierFlags(Qt::KeyboardModifiers modifiers) {
    return (modifiers & Qt::ShiftModifier ? 2 : 0) | (modifiers & Qt::ControlModifier ? 4 : 0)
         | (modifiers & Qt::AltModifier ? 8 : 0) | (modifiers & Qt::MetaModifier ? 16 : 0)
         | (modifiers & Qt::KeypadModifier ? 32 : 0);
}
class SwiftWidgetStyle final : public QProxyStyle {
public:
    int styleHint(StyleHint hint, const QStyleOption *option, const QWidget *item, QStyleHintReturn *data) const override {
        if (hint == SH_ScrollBar_Transient && item && item->property("qsTransientBar").toBool()) return 1;
        return QProxyStyle::styleHint(hint, option, item, data);
    }
    int pixelMetric(PixelMetric metric, const QStyleOption *option, const QWidget *item) const override {
        const int base = QProxyStyle::pixelMetric(metric, option, item);
        if (metric == PM_ScrollView_ScrollBarOverlap && item && item->property("qsTransientBar").toBool())
            return QProxyStyle::pixelMetric(PM_ScrollBarExtent, option, item);
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
bool runningEventLoop = false;
void releaseIdleApplication() {
    if (liveWindows == 0 && !runningEventLoop) {
        delete ownedApplication;
        ownedApplication = nullptr;
    }
}

// Registration lasts for the Swift process. The Qt font database is recreated
// when an offscreen renderer releases the last window and another one opens.
struct RegisteredFont { QString path; QByteArray data; };
QList<RegisteredFont> registeredFonts;
bool installFont(QApplication &app, const QByteArray &data) {
    const int id = QFontDatabase::addApplicationFontFromData(data);
    if (id < 0) return false;
    registerFontNames(app, QRawFont(data, 16), QFontDatabase::applicationFontFamilies(id));
    return true;
}

QApplication &application() {
    static int argc = 1;
    static char name[] = "QtSwiftUI";
    static char *argv[] = {name, nullptr};
    if (!qApp) {
        ownedApplication = new QApplication(argc, argv);
        ownedApplication->setStyle(new SwiftWidgetStyle());
        for (const auto &font : registeredFonts) installFont(*ownedApplication, font.data);
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
    Magnification pinch;
    bool directInteraction = false;
    int gestureInputs = 127;
    qint64 gestureDevice = -1;
    QMenu *contextPopup = nullptr;
    bool customContextRequest = false;
    bool hasContextMenu() const { return customContextRequest || (contextPopup && !contextPopup->isEmpty()); }
    void sendContextRequest(QPoint global);
    void openContextMenu(QPoint global, bool keyboard) {
        if (customContextRequest) {
            sendContextRequest(global);
            return;
        }
        contextPopup->popup(global);
        if (keyboard) {
            for (auto *item : contextPopup->actions()) {
                if (item->isEnabled() && !item->isSeparator()) { contextPopup->setActiveAction(item); break; }
            }
        }
    }
    bool isImage = false;
    bool heading = false, adjustable = false;
    bool modal = false;
    bool updatesFrequently = false;
    QString accessibleValue;
    std::optional<QPainterPath> contentShape;
    int tapCount = 0, consecutiveTaps = 0;
    bool trackingTap = false;
    QPointF pressPosition, tapLocation;
    std::optional<QPointF> hoverPosition;
    QElapsedTimer lastTap;
    bool accessibilityHidden = false;
    QStringList accessibilityActions;
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
// Intercept context requests before an embedded native control opens its own menu.
class ContextMenuFilter final : public QObject {
public:
    using QObject::QObject;
    bool eventFilter(QObject *source, QEvent *event) override {
        if (event->type() != QEvent::ContextMenu) return false;
        auto *request = static_cast<QContextMenuEvent *>(event);
        const bool keyboard = request->reason() == QContextMenuEvent::Keyboard;
        for (auto *item = qobject_cast<QWidget *>(source); item && !item->isWindow(); item = item->parentWidget()) {
            auto *group = dynamic_cast<GroupWidget *>(item);
            if (!group || !group->hasContextMenu() || !group->isEnabled()) continue;
            const auto local = keyboard ? group->hitBounds().center() : group->mapFromGlobal(request->globalPos());
            if (!group->hitBounds().contains(local) || (group->contentShape && !group->contentShape->contains(local))) continue;
            group->openContextMenu(group->mapToGlobal(local), keyboard);
            event->accept();
            return true;
        }
        return false;
    }
};

void installContextMenuFilter() {
    static QPointer<ContextMenuFilter> filter;
    if (!filter) {
        filter = new ContextMenuFilter(qApp);
        qApp->installEventFilter(filter);
    }
}

class SwiftButton final : public QPushButton {
public:
    using QPushButton::QPushButton;
    NativeMenu *popup = nullptr;
    bool menuIndicator = true;
protected:
    void initStyleOption(QStyleOptionButton *option) const override {
        QPushButton::initStyleOption(option);
        if (popup && menuIndicator) option->features |= QStyleOptionButton::HasMenu;
    }
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
            auto *owner = group->parentWidget();
            while (owner && owner != this && !qobject_cast<QAbstractButton *>(owner)) owner = owner->parentWidget();
            if (owner != this) continue;
            restricted = true;
            if (group->contentShape->contains(group->mapFrom(this, point))) return true;
        }
        return !restricted;
    }
};
static void sendAccessibleEvent(GroupWidget *target, QSEventKind kind, const QString &value = {});
static void activateAccessibleButton(QAbstractButton *button);
static void notifyMediaAction(QWidget *widget) {
    if (widget->property("qsStartsMedia").toBool()) {
        QAccessibleEvent event(widget, QAccessible::SoundPlayed);
        QAccessible::updateAccessibility(&event);
    }
}

class AccessibleGroup final : public QAccessibleWidget {
public:
    explicit AccessibleGroup(GroupWidget *group) : QAccessibleWidget(group), group(group) {}
    QRect rect() const override {
        const QRect bounds = group->hitBounds();
        return QRect(group->mapToGlobal(bounds.topLeft()), bounds.size());
    }
    QAccessible::Role role() const override {
        if (group->adjustable) return QAccessible::Slider;
        if (group->property("qsSearchField").toBool()) return QAccessible::EditableText;
        if (group->property("qsAXLink").toBool()) return QAccessible::Link;
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
            if (auto *label = group->findChild<QLabel *>()) return label->accessibleName().isEmpty() ? label->text() : label->accessibleName();
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
        names.append(group->accessibilityActions);
        if (group->hasContextMenu()) names.append(showMenuAction());
        if (group->tapCount == 1) names.append(QAccessibleActionInterface::pressAction());
        for (const auto &entry : combinedActions()) names.append(entry.name);
        names.removeDuplicates();
        return names;
    }
    void doAction(const QString &action) override {
        if (!group->isEnabled() || group->accessibilityHidden) return;
        if (action == showMenuAction() && group->hasContextMenu()) {
            group->openContextMenu(group->mapToGlobal(group->hitBounds().center()), true);
            return;
        }
        if (group->accessibilityActions.contains(action)) {
            sendAccessibleEvent(group, QSAccessibilityAction, action);
            return;
        }
        if (group->adjustable && (action == increaseAction() || action == decreaseAction())) {
            sendAccessibleEvent(group, action == increaseAction() ? QSIncrement : QSDecrement);
            return;
        }
        if (group->tapCount == 1 && action == QAccessibleActionInterface::pressAction()) {
            notifyMediaAction(group);
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
        result.hasPopup = group->hasContextMenu();
        result.animated = group->updatesFrequently;
        result.modal = group->modal;
        result.linked = role() == QAccessible::Link;
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
    void setScale(QPointF value, QPointF anchorValue) {
        if (scale == value && anchor == anchorValue) return;
        scale = value;
        anchor = anchorValue;
        updateBoundingRect();
        update();
    }
    QRectF boundingRectFor(const QRectF &source) const override { return matrix(source).mapRect(source); }
protected:
    void draw(QPainter *painter) override {
        auto *root = static_cast<QWidget *>(parent());
        QRect clip = root->rect();
        auto *image = singleRaster(root, clip);
        painter->save();
        painter->setTransform(matrix(sourceBoundingRect(Qt::LogicalCoordinates)), true);
        if (image) {
            // Scaling a widget-sized pixmap discards image detail before magnification.
            painter->setClipRect(clip, Qt::IntersectClip);
            painter->translate(image->mapTo(root, QPoint()));
            image->draw(*painter);
        } else {
            QPoint offset;
            const auto source = sourcePixmap(Qt::LogicalCoordinates, &offset, NoPad);
            painter->setRenderHint(QPainter::SmoothPixmapTransform);
            painter->drawPixmap(offset, source);
        }
        painter->restore();
    }
private:
    static RasterWidget *singleRaster(QWidget *root, QRect &clip) {
        QWidget *node = root;
        while (auto *group = dynamic_cast<GroupWidget *>(node)) {
            if (group->autoFillBackground() || group->testAttribute(Qt::WA_StyledBackground) ||
                (group->hasFocus() && group->property("qsFocusable").toBool())) return nullptr;
            QWidget *only = nullptr;
            for (auto *object : group->children()) {
                auto *child = qobject_cast<QWidget *>(object);
                if (!child || child->isHidden()) continue;
                if (only || child->graphicsEffect() || !child->mask().isEmpty()) return nullptr;
                only = child;
            }
            if (!only) return nullptr;
            clip &= QRect(only->mapTo(root, QPoint()), only->size());
            node = only;
        }
        return dynamic_cast<RasterWidget *>(node);
    }
    double degrees = 0;
    QPointF scale{1, 1};
    QPointF anchor;
    QTransform matrix(const QRectF &source) const {
        const QPointF center(source.x() + anchor.x() * source.width(), source.y() + anchor.y() * source.height());
        QTransform t;
        t.translate(center.x(), center.y());
        t.rotate(degrees);
        t.scale(scale.x(), scale.y());
        t.translate(-center.x(), -center.y());
        return t;
    }
};
class AccessibleButton final : public QAccessibleWidget {
public:
    AccessibleButton(QPushButton *button, bool link)
        : QAccessibleWidget(button, QAccessible::Button), button(button) { button->setProperty("qsAXLink", link); }
    QAccessible::Role role() const override {
        if (button->property("qsAXMenu").toBool()) return QAccessible::ButtonMenu;
        return button->property("qsAXLink").toBool() ? QAccessible::Link : QAccessible::Button;
    }
    QString text(QAccessible::Text kind) const override {
        const QString value = QAccessibleWidget::text(kind);
        if (kind != QAccessible::Name || !value.isEmpty()) return value;
        if (!button->text().isEmpty()) return button->text();
        QStringList parts;
        for (const auto *child : button->findChildren<QWidget *>()) {
            if (auto *rich = qobject_cast<const QTextBrowser *>(child)) parts.append(rich->toPlainText());
            else if (auto *label = qobject_cast<const QLabel *>(child)) parts.append(label->accessibleName().isEmpty() ? label->text() : label->accessibleName());
        }
        return parts.join(' ');
    }
    QStringList actionNames() const override {
        if (role() == QAccessible::ButtonMenu) return {pressAction(), showMenuAction()};
        return {pressAction()};
    }
    void doAction(const QString &action) override {
        if (button->isEnabled() && (action == pressAction() || (role() == QAccessible::ButtonMenu && action == showMenuAction()))) {
            notifyMediaAction(button);
            activateAccessibleButton(button);
        }
    }
    QAccessible::State state() const override {
        auto state = QAccessibleWidget::state();
        state.linked = role() == QAccessible::Link;
        state.selected = button->property("qsSelected").toBool();
        state.pressed = button->isDown();
        state.hasPopup = role() == QAccessible::ButtonMenu;
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
    double materialRadius = 0;
    MaterialBackdrop backdrop;
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
        if (materialRadius > 0 && !backdrop.pixels.isNull()) {
            painter.setClipPath(path);
            painter.setRenderHint(QPainter::SmoothPixmapTransform);
            painter.drawImage(backdrop.region, backdrop.pixels);
        } else if (customPath) painter.drawPath(path);
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
    std::optional<RasterContent> image;
    std::shared_ptr<QSTextParagraph> text;
    bool shadeImage = false;
    double materialRadius = 0;
    MaterialBackdrop backdrop;
};
class CanvasWidget final : public QWidget {
public:
    using QWidget::QWidget;
    std::vector<Drawing> drawings;
    void paintEvent(QPaintEvent *) override {
        QPainter painter(this);
        painter.translate(property("qsFraction").toPointF());
        paintUntil(painter, drawings.size());
    }
    void refreshMaterials() {
        for (size_t i = 0; i < drawings.size(); ++i) {
            auto &drawing = drawings[i];
            if (drawing.materialRadius <= 0) continue;
            drawing.backdrop = MaterialBackdrop::read(this, drawing.materialRadius, drawing.color, [this, i](QPainter &painter) {
                paintUntil(painter, i);
            });
            update();
        }
    }
private:
    void paintUntil(QPainter &painter, size_t end) {
        for (size_t i = 0; i < end; ++i) {
            const auto &drawing = drawings[i];
            painter.save();
            if (drawing.clip) painter.setClipPath(*drawing.clip);
            painter.setOpacity(drawing.opacity);
            if (drawing.filters.empty() && !drawing.shadeImage) paintSource(painter, drawing);
            else paintLayer(painter, drawing);
            painter.restore();
        }
    }
private:
    static void paintSource(QPainter &painter, const Drawing &drawing) {
        painter.setRenderHint(QPainter::Antialiasing, drawing.antialias);
        painter.setTransform(drawing.matrix, true);
        QBrush brush = drawing.gradient ? QBrush(*drawing.gradient) : QBrush(drawing.color);
        const auto &backdrop = drawing.backdrop;
        if (!backdrop.pixels.isNull()) {
            brush.setTextureImage(backdrop.pixels);
            QTransform mapping;
            mapping.translate(backdrop.region.x(), backdrop.region.y());
            mapping.scale(double(backdrop.region.width()) / backdrop.pixels.width(), double(backdrop.region.height()) / backdrop.pixels.height());
            brush.setTransform(mapping * drawing.matrix.inverted());
            painter.setRenderHint(QPainter::SmoothPixmapTransform);
        }
        if (drawing.text) {
            auto &doc = drawing.text->visible();
            const auto rect = drawing.path.boundingRect();
            painter.setClipRect(rect, Qt::IntersectClip);
            painter.translate(rect.topLeft());
            QAbstractTextDocumentLayout::PaintContext context;
            QTransform space;
            space.translate(-rect.x(), -rect.y());
            brush.setTransform(brush.transform() * space);
            context.palette.setBrush(QPalette::Text, brush);
            doc.documentLayout()->draw(&painter, context);
            if (drawing.text->customStrikes) drawTextStrikes(painter, doc, context.palette);
            return;
        }
        if (drawing.image) {
            const auto rect = drawing.path.boundingRect();
            painter.save();
            painter.translate(rect.topLeft());
            drawing.image->draw(painter, rect.size());
            painter.restore();
            if (drawing.shadeImage) {
                // The isolated layer contains only the image. Its alpha masks the color or gradient.
                painter.setCompositionMode(QPainter::CompositionMode_SourceIn);
                painter.fillRect(rect, brush);
            }
            return;
        }
        if (drawing.lineWidth >= 0) {
            painter.strokePath(drawing.path, QPen(brush, drawing.lineWidth, Qt::SolidLine, Qt::FlatCap, Qt::MiterJoin));
        } else {
            painter.fillPath(drawing.path, brush);
        }
    }
    void paintLayer(QPainter &painter, const Drawing &drawing) {
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
    void (*closed)(void *) = nullptr;
    QSDragHandler dragHandler = nullptr;
    QSKeyHandler keyHandler = nullptr;
    bool pending = false, framePending = false, snapshot = false;
    bool dragsByBackground = false;
    std::optional<bool> fullScreenEnabled;
    QSize contentMinimum{0, 0}, contentMaximum{QWIDGETSIZE_MAX, QWIDGETSIZE_MAX};
    std::optional<QSize> lockedNormalSize;

    void applySizeLimits(bool fullScreen) {
        QSize lower = contentMinimum, upper = contentMaximum;
        if (lockedNormalSize) {
            *lockedNormalSize = lockedNormalSize->expandedTo(lower).boundedTo(upper);
            if (!fullScreen) lower = upper = *lockedNormalSize;
        }
        if (minimumSize() != lower) setMinimumSize(lower);
        if (maximumSize() != upper) setMaximumSize(upper);
    }
    struct Placement { QPointF anchor; QPointer<QSWindow> previous; };
    std::optional<Placement> initialPlacement;
    WindowShortcuts shortcuts;
    NativeTransfer transfers;

    void connectMenu(QMenu *menu, int id) {
        QObject::connect(menu, &QMenu::triggered, this, [this, id](QAction *item) {
            const int action = item->data().toInt();
            if (action >= 0) event(context, id, QSActivate, QByteArray::number(action).constData());
        });
    }

    void schedule() {
        if (pending || snapshot) return;
        pending = true;
        QTimer::singleShot(0, this, [this] {
            pending = false;
            render(context, width(), height());
        });
    }
    bool eventFilter(QObject *source, QEvent *input) override {
        if (input->type() == QEvent::Expose && initialPlacement && source == windowHandle() && windowHandle()->isExposed()) {
            const auto placement = *initialPlacement;
            initialPlacement.reset();
            source->removeEventFilter(this);
            qs_position_window(this, placement.anchor.x(), placement.anchor.y(), placement.previous);
            return false;
        }
        if (source == focusWidget() && handleClipboardKey(focusWidget(), input, transfers.handler, context)) return true;
        if (transfers.filter(qobject_cast<QWidget *>(source), input, context)) return true;
        if (keyHandler && source == focusWidget() && (input->type() == QEvent::KeyPress || input->type() == QEvent::KeyRelease)) {
            const auto *key = static_cast<QKeyEvent *>(input);
            const bool release = input->type() == QEvent::KeyRelease;
            if (!(release && key->isAutoRepeat())) {
                const auto chars = WindowShortcuts::characters(key->key(), key->text()).toUtf8();
                const int flags = eventModifierFlags(key->modifiers());
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
        if (group && group->pinch.minimum >= 0 && group->isEnabled()) {
            if (input->type() == QEvent::NativeGesture && nativePinch(group, static_cast<QNativeGestureEvent *>(input))) {
                input->accept();
                return true;
            }
            if (input->type() == QEvent::Gesture && touchPinch(group, static_cast<QGestureEvent *>(input))) return true;
        }
        if (group && group->testAttribute(Qt::WA_Hover) &&
            (input->type() == QEvent::HoverEnter || input->type() == QEvent::HoverMove || input->type() == QEvent::HoverLeave)) {
            std::optional<QPointF> point;
            if (input->type() != QEvent::HoverLeave) {
                const auto position = static_cast<QHoverEvent *>(input)->scenePosition();
                if (QRectF(group->hitBounds()).contains(group->mapFrom(this, position))) point = position;
            }
            if (point != group->hoverPosition) {
                group->hoverPosition = point;
                event(context, group->property("swiftId").toInt(), QSContinuousHover, point ? "1" : "0");
            }
        }
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
            const auto reason = static_cast<QFocusEvent *>(input)->reason();
            const char *value = "1";
            if (input->type() == QEvent::FocusOut) value = "0";
            else if (reason == Qt::MouseFocusReason) value = "mouse";
            else if (reason == Qt::TabFocusReason || reason == Qt::BacktabFocusReason) value = "tab";
            event(context, source->property("swiftId").toInt(), QSFocusChanged, value);
        }
        return false;
    }
    void magnified(GroupWidget *group, double factor, QPointF local, quint64 tick, bool ended) {
        const auto bounds = group->layoutRect;
        if (group->pinch.update(factor, local - bounds.topLeft(), bounds.size(), tick, ended))
            event(context, group->property("swiftId").toInt(), QSMagnified, "");
    }
    bool nativePinch(GroupWidget *group, QNativeGestureEvent *input) {
        const int kind = input->pointingDevice()->type() == QInputDevice::DeviceType::TouchScreen ? 1 : 2;
        if (!(group->gestureInputs & kind)) return false;
        const auto type = input->gestureType();
        const auto tick = input->timestamp() ? input->timestamp() : Magnification::now();
        auto &pinch = group->pinch;
        if (type == Qt::BeginNativeGesture) { pinch.begin(tick); return true; }
        if (type != Qt::ZoomNativeGesture && type != Qt::EndNativeGesture) return false;
        if (!pinch.tracking) {
            if (type == Qt::EndNativeGesture) return false;
            pinch.begin(tick);
        }
        const double next = type == Qt::ZoomNativeGesture ? pinch.factor * (1 + input->value()) : pinch.factor;
        magnified(group, next, group->mapFrom(this, input->scenePosition()), tick, type == Qt::EndNativeGesture);
        return true;
    }
    bool touchPinch(GroupWidget *group, QGestureEvent *input) {
        auto *gesture = static_cast<QPinchGesture *>(input->gesture(Qt::PinchGesture));
        if (!gesture || !(group->gestureInputs & 1)) return false;
        const auto state = gesture->state();
        if (state == Qt::GestureCanceled) {
            cancelGesture(group);
        } else {
            const auto tick = Magnification::now();
            if (state == Qt::GestureStarted) group->pinch.begin(tick);
            magnified(group, gesture->totalScaleFactor(), group->mapFromGlobal(gesture->centerPoint()), tick, state == Qt::GestureFinished);
        }
        input->accept(gesture);
        return true;
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
        const bool active = (group->pointerDrag.tracking && group->pointerDrag.recognized) || (group->pinch.tracking && group->pinch.recognized);
        group->pinch.tracking = false;
        group->cancelPointer();
        if (active) event(context, group->property("swiftId").toInt(), QSGestureCancelled, "");
    }
    void observeFocus(QWidget *item, int id) {
        item->setProperty("swiftId", id);
        item->installEventFilter(this);
    }
    void mousePressEvent(QMouseEvent *mouse) override {
        // Interactive children accept the press before it reaches the window.
        if (dragsByBackground && mouse->button() == Qt::LeftButton &&
            windowHandle() && windowHandle()->startSystemMove()) {
            mouse->accept();
            return;
        }
        QWidget::mousePressEvent(mouse);
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
    void moveEvent(QMoveEvent *) override { schedule(); }
    void closeEvent(QCloseEvent *event) override {
        if (!windowFlags().testFlag(Qt::WindowCloseButtonHint)) {
            event->ignore();
            return;
        }
        QWidget::closeEvent(event);
        if (closed && event->isAccepted()) QTimer::singleShot(0, this, [this] {
            if (!isVisible() && closed) closed(context);
        });
    }
    bool disallowsTransitionFrom(Qt::WindowStates previous) {
        const auto added = windowState() & ~previous;
        return (added.testFlag(Qt::WindowMinimized) && !qs_window_allows_minimize(this)) ||
               (added.testFlag(Qt::WindowFullScreen) && !qs_window_allows_full_screen(this));
    }
    void changeEvent(QEvent *change) override {
        QWidget::changeEvent(change);
        if (change->type() == QEvent::WindowStateChange) {
            const auto previous = static_cast<QWindowStateChangeEvent *>(change)->oldState();
            if (isFullScreen() != previous.testFlag(Qt::WindowFullScreen)) applySizeLimits(isFullScreen());
            if (disallowsTransitionFrom(previous)) {
                // A window manager can request these transitions independently of the application menu.
                QTimer::singleShot(0, this, [this, previous] {
                    if (disallowsTransitionFrom(previous)) setWindowState(previous);
                });
            }
        }
        if (change->type() == QEvent::WindowStateChange || change->type() == QEvent::ActivationChange || change->type() == QEvent::PaletteChange) schedule();
    }
};

namespace {
void GroupWidget::sendContextRequest(QPoint global) {
    auto *host = static_cast<QSWindow *>(window());
    tapLocation = host->mapFromGlobal(global);
    host->event(host->context, property("swiftId").toInt(), QSActivate, "");
}

static void sendAccessibleEvent(GroupWidget *target, QSEventKind kind, const QString &value) {
    auto *window = dynamic_cast<QSWindow *>(target->window());
    if (!window || !target->isEnabled()) return;
    if (kind == QSActivate) target->tapLocation = target->mapTo(window, QRectF(target->layoutRect).center());
    window->event(window->context, target->property("swiftId").toInt(), kind, value.toUtf8().constData());
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
    if (window->lockedNormalSize) {
        window->lockedNormalSize = QSize(width, height);
        window->applySizeLimits(window->isFullScreen());
    }
    window->resize(width, height);
    window->show();
    qs_flush();
}
void qs_request_window_close(QSWindow *window) { window->close(); }
void qs_window_limits(QSWindow *window, double minWidth, double minHeight, double maxWidth, double maxHeight) {
    auto lower = [](double limit) { return std::isfinite(limit) ? int(std::ceil(std::clamp(limit, 0.0, double(QWIDGETSIZE_MAX)))) : 0; };
    auto upper = [](double limit) { return std::isfinite(limit) ? int(std::floor(std::clamp(limit, 0.0, double(QWIDGETSIZE_MAX)))) : QWIDGETSIZE_MAX; };
    window->contentMinimum = QSize(lower(minWidth), lower(minHeight));
    window->contentMaximum = QSize(upper(maxWidth), upper(maxHeight)).expandedTo(window->contentMinimum);
    window->applySizeLimits(window->isFullScreen());
}
QSWindowLevel qs_window_level(QSWindow *window) {
    const auto flags = window->windowFlags();
    if (flags.testFlag(Qt::WindowStaysOnTopHint)) return QSFloatingWindow;
    if (flags.testFlag(Qt::WindowStaysOnBottomHint)) return QSDesktopWindow;
    return QSNormalWindow;
}
static void applyWindowFlags(QSWindow *window, Qt::WindowFlags flags) {
    if (flags == window->windowFlags()) return;
    // Changing a QWidget's window flags hides it. Preserve its presentation
    // and the focused control when a live scene changes its window flags.
    const bool visible = window->isVisible();
    const bool active = window->isActiveWindow();
    const auto geometry = window->geometry();
    const auto state = window->windowState();
    QPointer<QWidget> focus = window->focusWidget();
    window->setWindowFlags(flags);
    if (visible) {
        const bool withoutActivation = window->testAttribute(Qt::WA_ShowWithoutActivating);
        window->setAttribute(Qt::WA_ShowWithoutActivating, !active || withoutActivation);
        window->setGeometry(geometry);
        window->setWindowState(state);
        window->show();
        window->setAttribute(Qt::WA_ShowWithoutActivating, withoutActivation);
        if (active && focus) focus->setFocus(Qt::OtherFocusReason);
    }
}
void qs_set_window_level(QSWindow *window, QSWindowLevel level) {
    auto flags = window->windowFlags();
    flags.setFlag(Qt::WindowStaysOnTopHint, level == QSFloatingWindow);
    flags.setFlag(Qt::WindowStaysOnBottomHint, level == QSDesktopWindow);
    applyWindowFlags(window, flags);
}
int qs_window_allows_minimize(QSWindow *window) { return window->windowFlags().testFlag(Qt::WindowMinimizeButtonHint); }
int qs_window_allows_resize(QSWindow *window) { return window->minimumSize() != window->maximumSize(); }
int qs_window_allows_full_screen(QSWindow *window) {
    if (window->fullScreenEnabled) return *window->fullScreenEnabled;
    if (window->lockedNormalSize || window->contentMinimum == window->contentMaximum) return false;
    const auto *screen = window->screen();
    return !screen || window->contentMaximum.expandedTo(screen->size()) == window->contentMaximum;
}
void qs_window_controls(QSWindow *window, int dismiss, int minimize, int resize, int fullscreen) {
    if (resize) window->lockedNormalSize.reset();
    else if (!window->lockedNormalSize) {
        const auto normal = window->normalGeometry();
        window->lockedNormalSize = window->isFullScreen() && normal.isValid() ? normal.size() : window->size();
    }
    window->applySizeLimits(window->isFullScreen());
    window->fullScreenEnabled = fullscreen < 0 ? std::nullopt : std::optional<bool>(fullscreen != 0);
    auto flags = window->windowFlags();
    const bool canResize = resize && window->contentMinimum != window->contentMaximum;
    flags.setFlag(Qt::CustomizeWindowHint, !dismiss || !minimize || !canResize);
    flags.setFlag(Qt::WindowMaximizeButtonHint, canResize);
    flags.setFlag(Qt::WindowCloseButtonHint, dismiss != 0);
    flags.setFlag(Qt::WindowMinimizeButtonHint, minimize != 0);
    applyWindowFlags(window, flags);
}
void qs_position_window(QSWindow *window, double x, double y, QSWindow *previous) {
    auto *screen = previous ? previous->screen() : window->screen();
    if (!screen || !std::isfinite(x) || !std::isfinite(y)) return;
    // On X11 the frame margins are available after the window manager maps the window.
    if (auto *handle = window->windowHandle(); handle && !handle->isExposed()) {
        window->initialPlacement = QSWindow::Placement{QPointF(x, y), previous};
        handle->installEventFilter(window);
        return;
    }
    const auto available = screen->availableGeometry();
    const auto frame = window->frameGeometry();
    const int dx = std::max(0, available.width() - frame.width());
    const int dy = std::max(0, available.height() - frame.height());
    if (window->isRightToLeft()) x = 1 - x;
    QPoint origin = available.topLeft() + QPoint(int(dx * std::clamp(x, 0.0, 1.0)), int(dy * std::clamp(y, 0.0, 1.0)));
    if (previous) {
        const int step = std::max(1, window->style()->pixelMetric(QStyle::PM_TitleBarHeight, nullptr, window));
        auto offset = previous->frameGeometry().topLeft() - available.topLeft() + QPoint(step, step);
        if (offset.x() > dx || offset.y() > dy) offset = QPoint(step / 2, step / 2);
        origin = available.topLeft() + QPoint(std::clamp(offset.x(), 0, dx), std::clamp(offset.y(), 0, dy));
    }
    window->move(origin);
}
void qs_window_background_drag(QSWindow *window, int enabled) { window->dragsByBackground = enabled != 0; }
void qs_window_raise(QSWindow *window) {
    if (window->isMinimized()) window->showNormal(); else window->show();
    window->raise();
    window->activateWindow();
}
void qs_observe_close(QSWindow *window, void (*closed)(void *)) { window->closed = closed; }
void qs_snapshot_window(QSWindow *window) {
    window->snapshot = true;
    window->setAttribute(Qt::WA_DontShowOnScreen);
    window->setAttribute(Qt::WA_NoSystemBackground);
}
int qs_snapshot_size(QSWindow *window, double width, double height) {
    if (!std::isfinite(width) || !std::isfinite(height) || width <= 0 || height <= 0 ||
        width > QWIDGETSIZE_MAX || height > QWIDGETSIZE_MAX) return 0;
    window->resize(qCeil(width), qCeil(height));
    window->ensurePolished();
    return 1;
}
int qs_snapshot_pixels(QSWindow *window, int width, int height, double scale, int opaque, void *context, QSImageBytes receive) {
    if (width <= 0 || height <= 0 || scale <= 0 || !std::isfinite(scale)) return 0;
    QImage image(width, height, opaque ? QImage::Format_RGBX8888 : QImage::Format_RGBA8888_Premultiplied);
    if (image.isNull()) return 0;
    image.setDevicePixelRatio(scale);
    image.fill(opaque ? Qt::black : Qt::transparent);
    QPainter painter(&image);
    window->QWidget::render(&painter, QPoint(), QRegion(), QWidget::DrawChildren);
    painter.end();
    receive(context, image.constBits(), size_t(image.sizeInBytes()), image.bytesPerLine());
    return 1;
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
    auto pixels = window->grab();
    QPainter painter(&pixels);
    for (auto *popup : window->findChildren<QWidget *>()) {
        if (popup->isVisible() && (qobject_cast<QMenu *>(popup) || dynamic_cast<NativePopover *>(popup)))
            painter.drawPixmap(window->mapFromGlobal(popup->mapToGlobal(QPoint())), popup->grab());
    }
    painter.end();
    return pixels.save(QString::fromUtf8(path), "PNG");
}
int qs_run(QSWindow *window, const char *screenshot, QSPump pump) {
    if (screenshot && !window) return 1;
    auto &app = application();
    runningEventLoop = true;
    const auto cleanup = qScopeGuard([] {
        runningEventLoop = false;
        releaseIdleApplication();
    });
    // Swift's main actor and Foundation timers share the GUI thread with Qt.
    QTimer swiftEvents;
    QObject::connect(&swiftEvents, &QTimer::timeout, &swiftEvents, [pump] { pump(); });
    swiftEvents.start(16);
    if (screenshot) {
        auto capture = [window, path = QByteArray(screenshot)] {
            application().exit(qs_capture(window, path.constData()) ? 0 : 1);
        };
        QTimer::singleShot(qMax(0, qEnvironmentVariableIntValue("QTSWIFTUI_CAPTURE_DELAY_MS")), window, capture);
    }
    return app.exec();
}
int qs_application_active(void) {
    return QGuiApplication::applicationState() == Qt::ApplicationActive;
}
int qs_dark_appearance(void) {
    const auto palette = application().palette();
    return palette.color(QPalette::Window).lightness() < palette.color(QPalette::WindowText).lightness();
}
void qs_application_appearance(int mode) {
    auto &app = application();
    app.setPalette(QPalette());
    if (mode == 0 || qs_dark_appearance() == (mode == 2)) return;
    const bool dark = mode == 2;
    const QColor background = dark ? QColor(44, 44, 46) : QColor(245, 245, 247);
    const QColor text = dark ? QColor(245, 245, 247) : QColor(28, 28, 30);
    QPalette palette(background);
    for (auto role : {QPalette::WindowText, QPalette::Text, QPalette::ButtonText, QPalette::ToolTipText})
        palette.setColor(role, text);
    palette.setColor(QPalette::Base, dark ? QColor(28, 28, 30) : QColor(Qt::white));
    palette.setColor(QPalette::PlaceholderText, dark ? QColor(167, 167, 172) : QColor(100, 100, 105));
    palette.setColor(QPalette::Highlight, QColor(50, 105, 220));
    palette.setColor(QPalette::HighlightedText, Qt::white);
    for (auto role : {QPalette::WindowText, QPalette::Text, QPalette::ButtonText})
        palette.setColor(QPalette::Disabled, role, palette.color(QPalette::PlaceholderText));
    app.setPalette(palette);
}
void qs_active_window_state(int fullscreen) {
    auto *window = QApplication::activeWindow();
    if (!window) return;
    if (auto *scene = dynamic_cast<QSWindow *>(window)) {
        if (!fullscreen && !qs_window_allows_minimize(scene)) return;
        if (fullscreen && !qs_window_allows_full_screen(scene)) return;
    }
    if (!fullscreen) window->showMinimized();
    else if (window->isFullScreen()) window->showNormal();
    else window->showFullScreen();
}
int qs_edit_command(QSEditCommand command) {
    auto *window = dynamic_cast<QSWindow *>(QApplication::activeWindow());
    QWidget *field = window ? window->focusWidget() : nullptr;
    if (!field || !field->isEnabled()) return 0;
    if (command == QSCopy || command == QSCut || command == QSPaste) {
        int key = command == QSCopy ? Qt::Key_C : command == QSCut ? Qt::Key_X : Qt::Key_V;
        QKeyEvent event(QEvent::KeyPress, key, Qt::ControlModifier);
        if (handleClipboardKey(field, &event, window->transfers.handler, window->context)) return 1;
    }
    auto editText = [command](auto *edit) {
        if (edit->isReadOnly() && command != QSCopy && command != QSSelectAll) return 0;
        switch (command) {
        case QSUndo: edit->undo(); break;
        case QSRedo: edit->redo(); break;
        case QSCut: edit->cut(); break;
        case QSCopy: edit->copy(); break;
        case QSPaste: edit->paste(); break;
        case QSPastePlain: edit->insertPlainText(QApplication::clipboard()->text()); break;
        case QSDelete: { auto cursor = edit->textCursor(); cursor.deleteChar(); edit->setTextCursor(cursor); break; }
        case QSSelectAll: edit->selectAll(); break;
        }
        return 1;
    };
    if (auto *edit = qobject_cast<QPlainTextEdit *>(field)) return editText(edit);
    if (auto *edit = qobject_cast<QTextEdit *>(field)) return editText(edit);
    if (auto *edit = qobject_cast<QLineEdit *>(field)) {
        if (edit->isReadOnly() && command != QSCopy && command != QSSelectAll) return 0;
        switch (command) {
        case QSUndo: edit->undo(); break;
        case QSRedo: edit->redo(); break;
        case QSCut: edit->cut(); break;
        case QSCopy: edit->copy(); break;
        case QSPaste: case QSPastePlain: edit->paste(); break;
        case QSDelete: edit->del(); break;
        case QSSelectAll: edit->selectAll(); break;
        }
        return 1;
    }
    if (auto *label = qobject_cast<QLabel *>(field); label && command == QSCopy && label->hasSelectedText()) {
        QApplication::clipboard()->setText(label->selectedText());
        return 1;
    }
    return 0;
}
void qs_request_attention(void) {
    for (auto *window : application().topLevelWidgets())
        if (dynamic_cast<QSWindow *>(window) && window->isVisible()) QApplication::alert(window);
}
int qs_scene_phase(QSWindow *window) {
    const auto app = QGuiApplication::applicationState();
    if (!window->isVisible() || window->isMinimized() || app == Qt::ApplicationHidden || app == Qt::ApplicationSuspended) return 0;
    return app == Qt::ApplicationActive && window->isActiveWindow() ? 2 : 1;
}
int qs_control_active_state(QSWindow *window) {
    if (!window->isVisible() || window->isMinimized() || QGuiApplication::applicationState() != Qt::ApplicationActive) return 0;
    const auto *active = QApplication::activeWindow();
    if (active == window) return 2;
    // A transient panel can hold keyboard focus while its owning window
    // retains the active appearance.
    for (auto *handle = active ? active->windowHandle() : nullptr; handle; handle = handle->transientParent()) {
        if (handle == window->windowHandle()) return 1;
    }
    return 0;
}
void qs_minimize(QSWindow *window, int minimized) {
    if (minimized) window->showMinimized();
    else { window->showNormal(); window->activateWindow(); }
    qs_flush();
}
int qs_reduce_motion(QSWindow *window) {
    return window->style()->styleHint(QStyle::SH_Widget_Animation_Duration, nullptr, window) == 0 ||
           !QApplication::isEffectEnabled(Qt::UI_General);
}
double qs_window_scale(QSWindow *window) { return window->devicePixelRatioF(); }
void qs_set_key_handler(QSWindow *window, QSKeyHandler handler) { window->keyHandler = handler; }
void qs_set_drag_handler(QSWindow *window, QSDragHandler handler) { window->dragHandler = handler; }
void qs_group_gesture(QSWidget w, int taps, int drag, int simultaneous, double dragDistance, double magnifyDelta, int inputs) {
    auto *group = static_cast<GroupWidget *>(w);
    group->tapCount = taps;
    group->windowDrag = drag;
    group->simultaneous = simultaneous;
    const bool touch = magnifyDelta >= 0 && (inputs & 1);
    if (touch != (group->pinch.minimum >= 0 && (group->gestureInputs & 1))) {
        if (touch) group->grabGesture(Qt::PinchGesture);
        else group->ungrabGesture(Qt::PinchGesture);
    }
    group->pinch.minimum = magnifyDelta;
    if (magnifyDelta < 0) group->pinch.tracking = false;
    group->gestureInputs = inputs;
    group->setAttribute(Qt::WA_AcceptTouchEvents, touch || group->directInteraction);
    group->pointerDrag.threshold = dragDistance;
    if (dragDistance < 0) group->pointerDrag.tracking = false;
}
QSMagnifySample qs_magnify_sample(QSWidget w) { return static_cast<GroupWidget *>(w)->pinch.sample; }
void qs_close(QSWindow *window) {
    for (auto *child : window->findChildren<QWidget *>()) {
        if (auto *popup = dynamic_cast<NativePopover *>(child)) popup->disconnectDismissal();
    }
    delete window;
    --liveWindows;
    releaseIdleApplication();
}

QSWidget qs_create(QSWindow *window, QSWidget parent, QSKind kind, int id) {
    QWidget *container = parent ? widget(parent) : window;
    switch (kind) {
    case QSPopover:
        return new NativePopover(container->window(), [window, id] { window->event(window->context, id, QSActivate, ""); });
    case QSLabel: {
        return new PlainLabel(container);
    }
    case QSAttributedLabel: {
        auto *label = new AttributedLabel(container);
        QObject::connect(label, &QTextBrowser::anchorClicked, window, [=](const QUrl &url) {
            window->event(window->context, id, QSActivate, url.toEncoded().constData());
        });
        return label;
    }
    case QSLink: case QSButton: case QSMenuButton: {
        auto *button = new SwiftButton(container);
        if (kind == QSLink) {
            button->setCursor(Qt::PointingHandCursor);
        }
        QAccessible::registerAccessibleInterface(new AccessibleButton(button, kind == QSLink));
        window->observeFocus(button, id);
        if (kind == QSMenuButton) {
            button->setProperty("qsAXMenu", true);
            button->popup = new NativeMenu(button);
            window->connectMenu(button->popup, id);
        } else {
            QObject::connect(button, &QPushButton::clicked, window, [=] { window->event(window->context, id, QSActivate, ""); });
        }
        QObject::connect(button, &QPushButton::pressed, window, [=] { window->event(window->context, id, QSPressedChanged, "1"); });
        QObject::connect(button, &QPushButton::released, window, [=] { window->event(window->context, id, QSPressedChanged, "0"); });
        return button;
    }
    case QSSegmentedPicker: case QSRadioPicker: {
        auto *options = new PickerButtons(container, kind == QSRadioPicker);
        window->observeFocus(options, id);
        QObject::connect(&options->group, &QButtonGroup::idToggled, window, [=](int index, bool checked) {
            if (checked) window->event(window->context, id, QSActivate, QByteArray::number(index).constData());
        });
        return options;
    }
    case QSPicker: {
        auto *picker = new QComboBox(container);
        picker->setSizeAdjustPolicy(QComboBox::AdjustToContents);
        QAccessible::registerAccessibleInterface(new AccessiblePicker(picker));
        window->observeFocus(picker, id);
        QObject::connect(picker, &QComboBox::activated, window, [=](int index) {
            window->event(window->context, id, QSActivate, QByteArray::number(index).constData());
        });
        return picker;
    }
    case QSToggle: {
        auto *toggle = new QCheckBox(container);
        window->observeFocus(toggle, id);
        QObject::connect(toggle, &QCheckBox::toggled, window, [=](bool on) { window->event(window->context, id, QSActivate, on ? "1" : "0"); });
        return toggle;
    }
    case QSMultilineField: case QSTextEditor: case QSRichEditor: {
        auto *edit = kind == QSRichEditor ? new RichTextEditor(container) : new PlainTextEditor(container);
        if (kind == QSMultilineField) {
            edit->configureField();
            edit->submit = [=] { window->event(window->context, id, QSSubmit, ""); };
        }
        edit->setProperty("qsScrollInput", QVariant::fromValue<QObject *>(new ScrollInput(edit)));
        window->observeFocus(edit, id);
        auto cursorChanged = [=] {
            if (!edit->extraSelections().isEmpty()) edit->setExtraSelections({});
            window->event(window->context, id, QSCursorChanged, "");
        };
        QObject::connect(edit, &QPlainTextEdit::cursorPositionChanged, edit, cursorChanged);
        QObject::connect(edit, &QPlainTextEdit::selectionChanged, edit, cursorChanged);
        QObject::connect(edit, &QPlainTextEdit::textChanged, window, [=] {
            window->event(window->context, id, QSActivate, "");
        });
        return edit;
    }
    case QSEdit: case QSSecureEdit: {
        auto *edit = new QLineEdit(container);
        if (kind == QSSecureEdit) edit->setEchoMode(QLineEdit::Password);
        window->observeFocus(edit, id);
        auto cursorChanged = [=] { window->event(window->context, id, QSCursorChanged, ""); };
        QObject::connect(edit, &QLineEdit::cursorPositionChanged, edit, cursorChanged);
        QObject::connect(edit, &QLineEdit::selectionChanged, edit, cursorChanged);
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
    case QSMenuBar: {
        auto *bar = new QMenuBar(container);
        bar->setNativeMenuBar(false);
        QObject::connect(bar, &QMenuBar::triggered, window, [window, id](QAction *item) {
            const int index = item->data().toInt();
            if (index >= 0) window->event(window->context, id, QSActivate, QByteArray::number(index).constData());
        });
        return bar;
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
QSRect qs_present_popover(QSWidget w, QSWindow *window, QSWidget parent, QSRect anchor, QSSize content, QSPopoverEdge edge, int dark) {
    if (window->snapshot) return {};
    auto *source = parent ? widget(parent) : window;
    const auto origin = qs_origin(source);
    const auto point = source->window()->mapToGlobal(QPointF(origin.width + anchor.x, origin.height + anchor.y));
    const auto rect = static_cast<NativePopover *>(w)->present(QRectF(point, QSizeF(anchor.width, anchor.height)),
                                                               QSizeF(content.width, content.height), edge, dark);
    return {double(rect.x()), double(rect.y()), double(rect.width()), double(rect.height())};
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
void qs_scroll_set_offset(QSWidget w, double x, double y) {
    auto *area = static_cast<QScrollArea *>(w);
    auto set = [](QScrollBar *bar, double value) {
        if (std::isfinite(value))
            bar->setValue(qRound(qBound(double(bar->minimum()), value, double(bar->maximum()))));
    };
    set(area->horizontalScrollBar(), x);
    set(area->verticalScrollBar(), y);
}
uint64_t qs_scroll_user_revision(QSWidget w) {
    return static_cast<ScrollInput *>(widget(w)->property("qsScrollInput").value<QObject *>())->revision;
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
void qs_scroll_axes(QSWidget w, int h, int v, int dark) {
    auto *scroll = static_cast<QScrollArea *>(w);
    QPalette palette = application().palette();
    if (dark) {
        palette.setColor(QPalette::Window, QColor(48, 48, 48));
        palette.setColor(QPalette::Base, QColor(42, 42, 42));
        palette.setColor(QPalette::Button, QColor(92, 92, 92));
        palette.setColor(QPalette::WindowText, Qt::white);
        palette.setColor(QPalette::ButtonText, Qt::white);
    }
    for (auto *bar : {scroll->horizontalScrollBar(), scroll->verticalScrollBar()}) {
        const bool transient = (bar->orientation() == Qt::Horizontal ? h : v) == 1;
        if (bar->property("qsTransientBar").toBool() != transient) bar->setProperty("qsTransientBar", transient);
        if (bar->palette() != palette) bar->setPalette(palette);
    }
    scroll->setHorizontalScrollBarPolicy(h ? Qt::ScrollBarAsNeeded : Qt::ScrollBarAlwaysOff);
    scroll->setVerticalScrollBarPolicy(v ? Qt::ScrollBarAsNeeded : Qt::ScrollBarAlwaysOff);
}
void qs_destroy(QSWidget w) {
    if (auto *popup = dynamic_cast<NativePopover *>(widget(w))) popup->disconnectDismissal();
    delete widget(w);
}
void qs_text(QSWidget w, const char *s) {
    auto text = QString::fromUtf8(s);
    if (auto *label = dynamic_cast<PlainLabel *>(widget(w))) label->setSource(text);
    else if (auto *button = qobject_cast<QAbstractButton *>(widget(w))) button->setText(QString(text).replace('&', "&&"));
    else if (auto *edit = qobject_cast<QLineEdit *>(widget(w)); edit && edit->text() != text) {
        const QSignalBlocker block(edit);
        edit->setText(text);
    }
}
static Qt::TextElideMode textElideMode(QSTextTruncation mode) {
    switch (mode) {
    case QSTruncateHead: return Qt::ElideLeft;
    case QSTruncateMiddle: return Qt::ElideMiddle;
    case QSTruncateTail: return Qt::ElideRight;
    }
    return Qt::ElideRight;
}
QSSize qs_measure_text(QSWidget w, double width, int limit, QSTextTruncation mode) {
    auto size = qs_measure(w, width);
    if (limit > 0) {
        if (auto *label = dynamic_cast<PlainLabel *>(widget(w))) {
            const auto visible = label->intrinsicText(limit, textElideMode(mode));
            if (visible != label->source) {
                const double ideal = label->fontMetrics().boundingRect(QRect(0, 0, 1000000, 1000000),
                                                                     Qt::TextExpandTabs | Qt::TextDontClip, visible).width();
                size.width = width >= 0 ? qMin(width, ideal) : ideal;
            }
        } else if (auto *rich = dynamic_cast<AttributedLabel *>(widget(w))) {
            if (auto ideal = rich->intrinsicWidth(limit, textElideMode(mode))) {
                size.width = width >= 0 ? qMin(width, double(*ideal)) : *ideal;
            }
        }
    }
    return size;
}
void qs_text_display(QSWidget w, int limit, QSTextTruncation mode, int automaticName) {
    const auto elide = textElideMode(mode);
    if (auto *label = dynamic_cast<PlainLabel *>(widget(w))) {
        label->display(limit, elide);
        if (automaticName && label->text() != label->source) label->setAccessibleName(label->source);
    } else if (auto *rich = dynamic_cast<AttributedLabel *>(widget(w))) {
        rich->display(limit, elide);
        if (automaticName && limit > 0) rich->setAccessibleName(rich->sourceText());
    }
}
void qs_attributed_begin(QSWidget w) { static_cast<AttributedLabel *>(w)->begin(); }
void qs_attributed_append(QSWidget w, const char *text, size_t count, const char *link, const char *foreground, const char *background,
                          const char *family, double size, int weight, int italic, int underline, const char *underlineColor, int strike, const char *strikeColor, double spacing) {
    static_cast<AttributedLabel *>(w)->append(QString::fromUtf8(text, qsizetype(count)), link, foreground, background, family, size, weight, italic, underline, underlineColor, strike, strikeColor, spacing);
}
void qs_attributed_finish(QSWidget w, int selectable, double lineSpacing) { static_cast<AttributedLabel *>(w)->finish(selectable, lineSpacing); }
void qs_control_scale(QSWidget w, double scale) {
    auto *item = widget(w);
    if (item->property("qsControlScale").toDouble() == scale) return;
    item->setProperty("qsControlScale", scale);
    item->updateGeometry();
    item->update();
}
void qs_field_style(QSWidget w, int style) {
    const bool plain = style == 1;
    auto *item = widget(w);
    const QString sheet = style == 2 ? QStringLiteral("QLineEdit, QPlainTextEdit { border: 1px solid palette(mid); border-radius: 5px; padding: 2px 5px; background: palette(base); } QLineEdit:focus, QPlainTextEdit:focus { border-color: palette(highlight); }") : QString();
    if (item->styleSheet() != sheet) item->setStyleSheet(sheet);
    if (auto *multi = qobject_cast<QPlainTextEdit *>(widget(w))) {
        multi->setFrameShape(plain ? QFrame::NoFrame : QFrame::StyledPanel);
        multi->viewport()->setAutoFillBackground(!plain);
        multi->viewport()->setAttribute(Qt::WA_OpaquePaintEvent, false);
        return;
    }
    auto *edit = static_cast<QLineEdit *>(w);
    edit->setFrame(!plain);
    auto palette = edit->palette();
    palette.setColor(QPalette::Base, plain ? QColor(Qt::transparent) : application().palette().color(QPalette::Base));
    edit->setPalette(palette);
}
void qs_rich_define(QSWidget w, int id, const char *link, const char *foreground, const char *background,
                    const char *family, double size, int weight, int italic, int underline, const char *underlineColor,
                    int strike, const char *strikeColor, double spacing) {
    auto *editor = static_cast<RichTextEditor *>(w);
    bool customStrike;
    auto format = swiftTextFormat(editor->font(), editor->palette(), link, foreground, background, family, size, weight,
                                  italic, underline, underlineColor, strike, strikeColor, spacing, customStrike);
    if (customStrike) format.setFontStrikeOut(true);
    editor->define(id, format);
}
int qs_rich_revision(QSWidget w) { return static_cast<RichTextEditor *>(w)->document()->revision(); }
void qs_rich_begin(QSWidget w) { static_cast<RichTextEditor *>(w)->begin(); }
void qs_rich_append(QSWidget w, int id, const char *text, size_t count) { static_cast<RichTextEditor *>(w)->append(QString::fromUtf8(text, qsizetype(count)), id); }
void qs_rich_finish(QSWidget w) { static_cast<RichTextEditor *>(w)->finish(); }
void qs_rich_typing(QSWidget w, int id) { static_cast<RichTextEditor *>(w)->typing(id); }
void qs_rich_read(QSWidget w, void *context, QSEditorRun receive) { static_cast<RichTextEditor *>(w)->read(context, receive); }
QSTextRange qs_editor_selection(QSWidget w) {
    if (auto *line = qobject_cast<QLineEdit *>(widget(w))) {
        if (line->hasSelectedText()) return {line->selectionStart(), line->selectionEnd()};
        return {line->cursorPosition(), line->cursorPosition()};
    }
    const auto cursor = static_cast<PlainTextEditor *>(w)->textCursor();
    return {cursor.selectionStart(), cursor.selectionEnd()};
}
void qs_editor_select(QSWidget w, const QSTextRange *ranges, size_t count, int upstream) {
    const QSignalBlocker block(widget(w));
    if (auto *line = qobject_cast<QLineEdit *>(widget(w))) {
        if (!count) { line->deselect(); return; }
        auto range = ranges[0];
        if (range.start == range.end) line->setCursorPosition(range.start);
        else line->setSelection(upstream ? range.end : range.start, upstream ? range.start - range.end : range.end - range.start);
        return;
    }
    auto *editor = static_cast<PlainTextEditor *>(w);
    auto cursor = editor->textCursor();
    QList<QTextEdit::ExtraSelection> extra;
    for (size_t index = 0; index < count; ++index) {
        const auto range = ranges[index];
        if (range.start < 0 || range.end >= editor->document()->characterCount()) continue;
        QTextCursor next(editor->document());
        next.setPosition(upstream ? range.end : range.start);
        next.setPosition(upstream ? range.start : range.end, QTextCursor::KeepAnchor);
        if (index == 0) cursor = next;
        else {
            QTextEdit::ExtraSelection selected;
            selected.cursor = next;
            selected.format.setForeground(editor->palette().highlightedText());
            selected.format.setBackground(editor->palette().highlight());
            extra.append(selected);
        }
    }
    if (!count) cursor.clearSelection();
    if (!extra.isEmpty() || !editor->extraSelections().isEmpty()) editor->setExtraSelections(extra);
    const auto current = editor->textCursor();
    if (cursor.selectionStart() != current.selectionStart() || cursor.selectionEnd() != current.selectionEnd())
        editor->setTextCursor(cursor);
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
double qs_field_height(QSWidget w, double width, int minimum, int maximum) {
    return static_cast<PlainTextEditor *>(w)->fieldHeight(width, minimum, maximum);
}
QSBaselines qs_text_baselines(QSWidget w, double width, double height) {
    if (auto *rich = dynamic_cast<AttributedLabel *>(widget(w))) return rich->baselines(width, height);
    const auto metrics = widget(w)->fontMetrics();
    const double actual = qs_measure(w, width).height;
    const double drawn = qMin(actual, height);
    const double first = (height - drawn) / 2 + metrics.ascent();
    return {first, first + qMax(0.0, drawn - metrics.height())};
}
double qs_line_height(QSWidget w) { return widget(w)->fontMetrics().lineSpacing(); }
void qs_autocorrection(QSWidget w, int disabled) {
    auto *item = widget(w);
    const auto *edit = qobject_cast<QLineEdit *>(item);
    auto hints = item->inputMethodHints();
    hints.setFlag(Qt::ImhNoPredictiveText, disabled || (edit && edit->echoMode() == QLineEdit::Password));
    item->setInputMethodHints(hints);
}
char *qs_choose_save_path(const char *filename, const char *filter) {
    const QString path = QFileDialog::getSaveFileName(application().activeWindow(), {}, QString::fromUtf8(filename), QString::fromUtf8(filter));
    return path.isEmpty() ? nullptr : strdup(path.toUtf8().constData());
}
char *qs_choose_files(const char *mimeTypes, int directory, int multiple, const char *start, const char *prompt) {
    QSFileImporter dialog(application().activeWindow(), QString::fromUtf8(mimeTypes), directory, multiple);
    if (start) dialog.setDirectory(QString::fromUtf8(start));
    if (prompt) dialog.setLabelText(QFileDialog::Accept, QString::fromUtf8(prompt));
    if (dialog.exec() != QDialog::Accepted) return nullptr;
    QStringList result;
    for (const auto &url : dialog.importURLs())
        if (url.isLocalFile()) result.append(QString::fromLatin1(url.toEncoded(QUrl::FullyEncoded)));
    return result.isEmpty() ? nullptr : strdup(result.join('\n').toUtf8().constData());
}
void qs_clipboard_text(const char *text) { application().clipboard()->setText(QString::fromUtf8(text)); }
void qs_hint(QSWidget w, const char *s, const char *color) {
    auto *item = widget(w);
    if (*color) {
        auto palette = item->palette();
        palette.setColor(QPalette::PlaceholderText, QColor(QString::fromUtf8(color)));
        item->setPalette(palette);
    }
    if (auto *editor = qobject_cast<QPlainTextEdit *>(widget(w))) editor->setPlaceholderText(QString::fromUtf8(s));
    else static_cast<QLineEdit *>(w)->setPlaceholderText(QString::fromUtf8(s));
}
void qs_picker_option(QSWidget w, int index, const char *title, const char *symbol, int enabled) {
    if (auto *options = dynamic_cast<PickerButtons *>(widget(w))) {
        options->option(index, QString::fromUtf8(title), QString::fromUtf8(symbol), enabled != 0);
        return;
    }
    auto *picker = static_cast<QComboBox *>(w);
    const QString text = QString::fromUtf8(title);
    if (index == picker->count()) picker->addItem(text);
    else if (picker->itemText(index) != text) picker->setItemText(index, text);
    auto *model = qobject_cast<QStandardItemModel *>(picker->model());
    if (model && model->item(index)) model->item(index)->setEnabled(enabled);
    const QString symbolName = QString::fromUtf8(symbol);
    if (!symbolName.isEmpty() || !picker->itemIcon(index).isNull())
        picker->setItemIcon(index, systemSymbol(symbolName, 16, picker->palette().color(QPalette::Text)));
}
void qs_picker_selection(QSWidget w, int count, int selected) {
    if (auto *options = dynamic_cast<PickerButtons *>(widget(w))) {
        options->selection(count, selected);
        return;
    }
    auto *picker = static_cast<QComboBox *>(w);
    while (picker->count() > count) picker->removeItem(picker->count() - 1);
    picker->setCurrentIndex(selected);
}
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
    for (const auto &entry : registeredFonts) if (entry.path == font) return 1;
    QFile file(font);
    if (!file.open(QIODevice::ReadOnly)) return 0;
    const auto bytes = file.readAll();
    if (!installFont(app, bytes)) return 0;
    registeredFonts.append({font, bytes});
    return 1;
}
QSTextParagraph *qs_text_paragraph(const char *family, double size, int weight, int italic, double tracking) {
    auto font = resolveFont(application().font(), QString::fromUtf8(family), weight, italic);
    font.setPixelSize(qMax(1, qRound(size)));
    return new QSTextParagraph(font, tracking);
}
double qs_text_width(const char *text, const char *family, double size, double spacing) {
    auto font = resolveFont(application().font(), QString::fromUtf8(family), -1, false);
    font.setPixelSize(qMax(1, qRound(size)));
    font.setLetterSpacing(QFont::AbsoluteSpacing, spacing);
    return QFontMetricsF(font).horizontalAdvance(QString::fromUtf8(text));
}
QSSize qs_text_ink(const char *text, size_t count, const char *family, double size) {
    if (!std::isfinite(size) || size <= 0 || size > 65535) return {};
    auto font = resolveFont(application().font(), QString::fromUtf8(family), -1, false);
    font.setPixelSize(qMax(1, qRound(size)));
    const auto ink = QFontMetricsF(font).tightBoundingRect(QString::fromUtf8(text, qsizetype(count)));
    return {ink.width(), ink.height()};
}
QSFontMetrics qs_font_metrics(const char *family, double size) {
    const auto font = resolveFont(application().font(), QString::fromUtf8(family), -1, false);
    auto raw = QRawFont::fromFont(font);
    raw.setPixelSize(size);
    return {raw.ascent(), raw.descent(), raw.xHeight(), raw.leading()};
}
void qs_style(QSWidget w, const char *family, double points, int weight, int italic, double tracking,
              const char *color, int alignment, int wrap) {
    auto *item = widget(w);
    QFont font = resolveFont(application().font(), QString::fromUtf8(family), weight, italic);
    font.setLetterSpacing(QFont::AbsoluteSpacing, tracking);
    font.setPixelSize(qMax(1, qRound(points)));
    item->setFont(font);
    item->setProperty("qsTextBrush", {});
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
    if (auto *rich = dynamic_cast<AttributedLabel *>(item)) {
        rich->setLayoutOptions(Qt::AlignAbsolute | (alignment < 0 ? Qt::AlignLeft : alignment > 0 ? Qt::AlignRight : Qt::AlignHCenter), wrap);
    } else if (auto *label = qobject_cast<QLabel *>(item)) {
        label->setWordWrap(wrap);
        label->setAlignment(Qt::AlignAbsolute | Qt::AlignVCenter | (alignment < 0 ? Qt::AlignLeft : alignment > 0 ? Qt::AlignRight : Qt::AlignHCenter));
    }
}
void qs_surface(QSWidget w, const char *color, double radius) {
    auto *surface = static_cast<Surface *>(w);
    surface->materialRadius = 0;
    surface->backdrop = {};
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
void qs_path_visit(const QSPath *path, int closeContours, void *context, QSPathVisitor visit) {
    for (int i = 0; i < path->elementCount(); ++i) {
        const auto point = path->elementAt(i);
        if (point.isMoveTo()) {
            if (i && closeContours) visit(context, 4, 0, 0, 0, 0, 0, 0);
            visit(context, 0, point.x, point.y, 0, 0, 0, 0);
        } else if (point.isLineTo()) {
            visit(context, 1, point.x, point.y, 0, 0, 0, 0);
        } else if (point.isCurveTo() && i + 2 < path->elementCount()) {
            const auto second = path->elementAt(++i), end = path->elementAt(++i);
            visit(context, 3, end.x, end.y, point.x, point.y, second.x, second.y);
        }
    }
    if (closeContours && !path->isEmpty()) visit(context, 4, 0, 0, 0, 0, 0, 0);
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
void qs_surface_material(QSWidget w, double radius, unsigned tint) {
    auto *surface = static_cast<Surface *>(w);
    surface->materialRadius = radius;
    surface->fill = QColor::fromRgba(tint);
}
void qs_window_materials(QSWindow *window) {
    // Read back after native widgets have their final geometry and stacking order.
    for (auto *child : window->findChildren<QWidget *>()) {
        if (auto *canvas = dynamic_cast<CanvasWidget *>(child); canvas && canvas->isVisibleTo(window)) canvas->refreshMaterials();
        auto *surface = dynamic_cast<Surface *>(child);
        if (surface && surface->materialRadius > 0 && surface->isVisibleTo(window)) {
            surface->backdrop = MaterialBackdrop::read(surface, surface->materialRadius, surface->fill);
            surface->update();
        }
    }
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
void qs_canvas_text_take(QSWidget w, QSTextParagraph *paragraph) {
    static_cast<CanvasWidget *>(w)->drawings.back().text.reset(paragraph);
}
void qs_canvas_image(QSWidget w, QSRasterImage source, int shaded) {
    auto &drawing = static_cast<CanvasWidget *>(w)->drawings.back();
    drawing.image.emplace(source);
    drawing.shadeImage = shaded;
}
void qs_canvas_blur(QSWidget w, double radius, unsigned blurOptions, unsigned filterOptions) {
    if (std::isfinite(radius) && radius > 0)
        static_cast<CanvasWidget *>(w)->drawings.back().filters.push_back({radius, blurOptions, filterOptions});
}
void qs_canvas_material(QSWidget w, double radius, unsigned tint) {
    auto &drawing = static_cast<CanvasWidget *>(w)->drawings.back();
    drawing.materialRadius = radius;
    drawing.color = QColor::fromRgba(tint);
}
void qs_canvas_color(QSWidget w, const char *color) {
    static_cast<CanvasWidget *>(w)->drawings.back().color = QColor(QString::fromUtf8(color));
}
static QGradientStops qtStops(const QSGradientStop *stops, size_t count) {
    QGradientStops colors;
    colors.reserve(count);
    for (size_t i = 0; i < count; ++i) colors.append({stops[i].location, QColor::fromRgba(stops[i].argb)});
    return colors;
}
void qs_text_gradient(QSWidget w, double x1, double y1, double x2, double y2, const QSGradientStop *stops, size_t count) {
    QLinearGradient gradient(x1, y1, x2, y2);
    gradient.setStops(qtStops(stops, count));
    widget(w)->setProperty("qsTextBrush", QBrush(gradient));
}
static void applyTextBrush(QWidget *item, const QBrush &unit, QSize size) {
    auto brush = unit;
    brush.setTransform(QTransform::fromScale(size.width(), size.height()));
    auto palette = item->palette();
    for (auto role : {QPalette::WindowText, QPalette::Text, QPalette::ButtonText})
        for (auto group : {QPalette::Active, QPalette::Inactive})
            palette.setBrush(group, role, brush);
    item->setPalette(palette);
}
void qs_canvas_gradient(QSWidget w, double x1, double y1, double x2, double y2, unsigned options,
                        const QSGradientStop *stops, size_t count) {
    auto &gradient = static_cast<CanvasWidget *>(w)->drawings.back().gradient.emplace(x1, y1, x2, y2);
    gradient.setSpread((options & 2) ? QGradient::ReflectSpread : (options & 1) ? QGradient::RepeatSpread : QGradient::PadSpread);
    gradient.setStops(qtStops(stops, count));
}
void qs_direction(QSWidget w, int rtl) { widget(w)->setLayoutDirection(rtl ? Qt::RightToLeft : Qt::LeftToRight); }
void qs_direct_touch(QSWidget w, int enabled) {
    auto *group = static_cast<GroupWidget *>(w);
    group->directInteraction = enabled;
    group->setAttribute(Qt::WA_AcceptTouchEvents, enabled || (group->pinch.minimum >= 0 && (group->gestureInputs & 1)));
}
// Qt 6.4 has no standard zoom cursors. Cache a high-contrast glyph at the window's display scale.
static QCursor zoomCursor(bool zoomIn, qreal scale) {
    const QString key = QStringLiteral("qtswiftui-zoom-%1-%2").arg(zoomIn).arg(scale);
    QPixmap pixmap;
    if (!QPixmapCache::find(key, &pixmap)) {
        pixmap = QPixmap(qCeil(24 * scale), qCeil(24 * scale));
        pixmap.setDevicePixelRatio(scale);
        pixmap.fill(Qt::transparent);
        QPainter painter(&pixmap);
        painter.setRenderHint(QPainter::Antialiasing);
        QPainterPath glass;
        glass.addEllipse(QPointF(9, 9), 6.5, 6.5);
        glass.moveTo(14, 14);
        glass.lineTo(21, 21);
        glass.moveTo(6.5, 9);
        glass.lineTo(11.5, 9);
        if (zoomIn) { glass.moveTo(9, 6.5); glass.lineTo(9, 11.5); }
        painter.strokePath(glass, QPen(Qt::white, 4, Qt::SolidLine, Qt::RoundCap));
        painter.strokePath(glass, QPen(Qt::black, 1.5, Qt::SolidLine, Qt::RoundCap));
        painter.end();
        QPixmapCache::insert(key, pixmap);
    }
    return QCursor(pixmap, 9, 9);
}

static QCursor pointerCursor(QSPointer style, qreal scale) {
    switch (style) {
    case QSPointerAutomatic: return Qt::ArrowCursor;
    case QSPointerArrow: return Qt::ArrowCursor;
    case QSPointerText: return Qt::IBeamCursor;
    case QSPointerCross: return Qt::CrossCursor;
    case QSPointerOpenHand: return Qt::OpenHandCursor;
    case QSPointerClosedHand: return Qt::ClosedHandCursor;
    case QSPointerLink: return Qt::PointingHandCursor;
    case QSPointerColumn: return Qt::SplitHCursor;
    case QSPointerRow: return Qt::SplitVCursor;
    case QSPointerZoomIn: case QSPointerZoomOut: return zoomCursor(style == QSPointerZoomIn, scale);
    }
    return Qt::ArrowCursor;
}
void qs_pointer_style(QSWidget w, QSPointer style) {
    if (style == QSPointerAutomatic) widget(w)->unsetCursor();
    else widget(w)->setCursor(pointerCursor(style, widget(w)->devicePixelRatioF()));
}
int qs_has_pointer_style(QSWindow *window, int x, int y, QSPointer style) {
    auto *target = window->childAt(QPoint(x, y));
    if (!target) return 0;
    const auto expected = pointerCursor(style, target->devicePixelRatioF());
    const auto actual = target->cursor();
    if (actual.shape() != expected.shape()) return 0;
    return expected.shape() != Qt::BitmapCursor || (actual.hotSpot() == expected.hotSpot() &&
        actual.pixmap().toImage() == expected.pixmap().toImage());
}
int qs_direct_adjust(QSWindow *window, const char *value, int increment) {
    for (auto *target : window->findChildren<QWidget *>()) {
        if (!target->testAttribute(Qt::WA_AcceptTouchEvents)) continue;
        auto *element = QAccessible::queryAccessibleInterface(target);
        if (!element || element->role() != QAccessible::Slider || element->text(QAccessible::Value) != QString::fromUtf8(value)) continue;
        const auto action = increment ? QAccessibleActionInterface::increaseAction() : QAccessibleActionInterface::decreaseAction();
        auto *actions = element->actionInterface();
        if (!actions || !actions->actionNames().contains(action)) continue;
        actions->doAction(action);
        qs_flush();
        return 1;
    }
    return 0;
}
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
int qs_keyboard_modifiers(void) { return eventModifierFlags(QGuiApplication::keyboardModifiers()); }
int qs_keyboard_focus_visible(void) {
    const auto *window = QApplication::activeWindow();
    return window && window->testAttribute(Qt::WA_KeyboardFocusChange);
}
void qs_focus_effect(QSWidget w, int enabled) { widget(w)->setProperty("qsNoFocusEffect", !enabled); }
void qs_group_focus(QSWidget w, int enabled, int interactions) {
    auto *group = widget(w);
    const bool acceptsFocus = enabled && interactions;
    group->setProperty("qsFocusable", acceptsFocus);
    if (!acceptsFocus) {
        // Removing the container as a focus target leaves nested editors independently focusable.
        group->setFocusProxy(nullptr);
        group->setFocusPolicy(Qt::NoFocus);
        return;
    }
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
    if (group->focusPolicy() != Qt::StrongFocus) group->setFocusPolicy(Qt::StrongFocus);
}
void qs_continuous_hover(QSWidget w) { widget(w)->setAttribute(Qt::WA_Hover); }
QSSize qs_hover_location(QSWidget w) {
    const auto point = static_cast<GroupWidget *>(w)->hoverPosition.value_or(QPointF());
    return {point.x(), point.y()};
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
void qs_group_scale(QSWidget w, double x, double y, double anchorX, double anchorY) {
    auto *item = widget(w);
    if (x == 1 && y == 1) {
        if (item->graphicsEffect()) item->setGraphicsEffect(nullptr);
        return;
    }
    auto *effect = dynamic_cast<RotationEffect *>(item->graphicsEffect());
    if (!effect) { effect = new RotationEffect(item); item->setGraphicsEffect(effect); }
    effect->setScale(QPointF(x, y), QPointF(anchorX, anchorY));
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
void qs_view_shadow(QSWidget w, unsigned argb, double radius, double x, double y) {
    auto *item = widget(w);
    if (!qAlpha(argb) || !std::isfinite(radius) || !std::isfinite(x) || !std::isfinite(y)) {
        if (item->graphicsEffect()) item->setGraphicsEffect(nullptr);
        return;
    }
    auto *effect = dynamic_cast<ViewShadow *>(item->graphicsEffect());
    if (!effect) { effect = new ViewShadow; item->setGraphicsEffect(effect); }
    effect->configure(QColor::fromRgba(argb), qMax(0.0, radius), QPointF(x, y));
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
void qs_transition_front(QSWidget w) { widget(w)->raise(); }

QSWidget qs_transition_snapshot(QSWindow *window, QSWidget w) {
    auto *source = widget(w);
    if (!source->isVisibleTo(window) || source->window() != window) return nullptr;
    QRect clip = source->rect();
    for (auto *ancestor = source->parentWidget(); ancestor; ancestor = ancestor->parentWidget()) {
        clip &= QRect(source->mapFrom(ancestor, QPoint()), ancestor->size());
        if (ancestor == window) break;
    }
    if (clip.isEmpty()) return nullptr;
    // Keep the final visible pixels after Swift removes the view and its event handlers.
    qs_group_opacity(w, 1);
    const QPixmap pixels = source->grab(clip);
    if (pixels.isNull()) return nullptr;
    auto *layer = new QLabel(window);
    layer->setAttribute(Qt::WA_TransparentForMouseEvents);
    layer->setAttribute(Qt::WA_NoSystemBackground);
    layer->setFocusPolicy(Qt::NoFocus);
    layer->setPixmap(pixels);
    layer->setGeometry(QRect(source->mapTo(window, clip.topLeft()), clip.size()));
    layer->show();
    return layer;
}

// Give ancestor effects one premultiplied source image for the entire subtree.
class CompositingGroup final : public QGraphicsEffect {
    void draw(QPainter *painter) override {
        QPoint offset;
        const auto source = sourcePixmap(Qt::LogicalCoordinates, &offset, NoPad);
        painter->drawPixmap(offset, source);
    }
};
void qs_compositing_group(QSWidget w) {
    auto *group = widget(w);
    if (!group->graphicsEffect()) group->setGraphicsEffect(new CompositingGroup());
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
void qs_transfer_handler(QSWindow *window, QSTransferHandler handler) { window->transfers.handler = handler; }
void qs_transfer_scope(QSWidget item, int source, int destination) {
    auto *group = widget(item);
    group->setProperty("qsDragSource", bool(source));
    group->setProperty("qsDropTarget", bool(destination));
    if (group->acceptDrops() != bool(destination)) group->setAcceptDrops(destination);
}
int qs_transfer_between(QSWindow *window, int fromX, int fromY, int toX, int toY) {
    return window->transfers.transferBetween(window, {fromX, fromY}, {toX, toY}, window->context);
}
void qs_context_request_scope(QSWidget w, int enabled) {
    auto *group = static_cast<GroupWidget *>(w);
    group->customContextRequest = enabled;
    if (enabled) installContextMenuFilter();
}
int qs_theme_icon(const char *name, int extent, void *context, QSImageBytes receive) {
    application();
    const QString key = QString::fromUtf8(name);
    if (!receive || extent <= 0 || extent > 1024 || key.isEmpty() || key.contains('/')) return 0;
    const auto icon = QIcon::fromTheme(key);
    if (icon.isNull()) return 0;
    auto image = icon.pixmap(extent, extent).toImage();
    if (image.isNull()) return 0;
    QImage canvas(extent, extent, QImage::Format_RGBA8888);
    canvas.fill(Qt::transparent);
    QPainter painter(&canvas);
    image.setDevicePixelRatio(1);
    const auto fit = image.size().scaled(extent, extent, Qt::KeepAspectRatio);
    painter.drawImage(QRect(QPoint((extent - fit.width()) / 2, (extent - fit.height()) / 2), fit), image);
    painter.end();
    receive(context, canvas.constBits(), canvas.sizeInBytes(), canvas.bytesPerLine());
    return 1;
}
QSSize qs_primary_screen_size(void) {
    auto *screen = application().primaryScreen();
    if (!screen) return {0, 0};
    const QSize size = screen->geometry().size();
    return {double(size.width()), double(size.height())};
}
void qs_file_import(QSWidget w, const char *mime_types, int directories, int multiple, const char *default_directory,
                    const char *message, const char *confirmation, const char *key, const char *state, QSFileDialogSave save) {
    auto *group = static_cast<GroupWidget *>(w);
    if (group->findChild<QFileDialog *>(QString(), Qt::FindDirectChildrenOnly)) return;
    auto *dialog = new QSFileImporter(group, QString::fromUtf8(mime_types), directories, multiple);
    dialog->restoreConfiguration(state, default_directory);
    if (message) dialog->setWindowTitle(QString::fromUtf8(message));
    if (confirmation) {
        const auto label = QString::fromUtf8(confirmation);
        if (auto *selection = dialog->findChild<QPushButton *>(QStringLiteral("qsImportSelection")))
            selection->setText(label);
        else
            dialog->setLabelText(QFileDialog::Accept, label);
    }
    QObject::connect(dialog, &QDialog::finished, group, [group, dialog, key = QByteArray(key), save](int result) {
        if (!key.isEmpty() && save) save(key.constData(), dialog->configuration().constData());
        QStringList urls;
        if (result == QDialog::Accepted) {
            for (const auto &url : dialog->importURLs()) urls.append(QString::fromLatin1(url.toEncoded(QUrl::FullyEncoded)));
        }
        const QString value = result == QDialog::Rejected ? QStringLiteral("cancel") : urls.join('\n');
        QTimer::singleShot(0, group, [group, value, finished = QPointer<QFileDialog>(dialog)] {
            delete finished.data();
            sendAccessibleEvent(group, QSActivate, value);
        });
    });
    QTimer::singleShot(0, dialog, [dialog] { dialog->open(); });
}
int qs_alert_begin(QSWidget w, const char *title, const char *message) {
    auto *group = static_cast<GroupWidget *>(w);
    if (group->findChild<QMessageBox *>(QString(), Qt::FindDirectChildrenOnly)) return 0;
    auto *box = new QMessageBox(QMessageBox::NoIcon, QString::fromUtf8(title), QString::fromUtf8(title),
                                QMessageBox::NoButton, group);
    box->setTextFormat(Qt::PlainText);
    box->setInformativeText(QString::fromUtf8(message));
    box->setWindowModality(Qt::WindowModal);
    QObject::connect(box, &QDialog::finished, group, [group, box] {
        auto *clicked = box->clickedButton();
        int index = clicked ? clicked->property("qsAlertIndex").toInt() : -1;
        QTimer::singleShot(0, group, [group, index] { sendAccessibleEvent(group, QSActivate, QString::number(index)); });
    });
    return 1;
}
void qs_alert_button(QSWidget w, int index, const char *label, int role) {
    auto *box = widget(w)->findChild<QMessageBox *>(QString(), Qt::FindDirectChildrenOnly);
    if (!box) return;
    auto *button = label ? box->addButton(QString::fromUtf8(label).replace('&', "&&"),
                                          role == 1 ? QMessageBox::RejectRole : role == 2 ? QMessageBox::DestructiveRole : QMessageBox::AcceptRole)
                         : box->addButton(role == 1 ? QMessageBox::Cancel : QMessageBox::Ok);
    button->setProperty("qsAlertIndex", index);
    if (role == 1) box->setEscapeButton(button);
    else if (!box->defaultButton()) box->setDefaultButton(button);
}
int qs_alert_response(QSWindow *window, const char *title, const char *message, const char *button) {
    for (auto *box : window->findChildren<QMessageBox *>()) {
        if (!box->isVisible() || box->text() != QString::fromUtf8(title) || box->informativeText() != QString::fromUtf8(message)) continue;
        if (!button) return 1;
        for (auto *entry : box->buttons()) {
            if (entry->text().remove('&') != QString::fromUtf8(button)) continue;
            entry->click();
            qs_flush();
            return 1;
        }
    }
    return 0;
}
void qs_alert_show(QSWidget w) {
    if (auto *box = widget(w)->findChild<QMessageBox *>(QString(), Qt::FindDirectChildrenOnly)) {
        QTimer::singleShot(0, box, [box] { box->open(); });
    }
}
QSWidget qs_context_menu(QSWidget w) {
    auto *group = static_cast<GroupWidget *>(w);
    if (!group->contextPopup) {
        installContextMenuFilter();
        group->contextPopup = new QMenu(group);
        auto *window = static_cast<QSWindow *>(group->window());
        window->connectMenu(group->contextPopup, group->property("swiftId").toInt());
    }
    return group->contextPopup;
}
QSWidget qs_menu_begin(QSWidget w, int indicator) {
    auto *button = static_cast<SwiftButton *>(w);
    if (button->menuIndicator != bool(indicator)) {
        button->menuIndicator = indicator;
        button->updateGeometry();
        button->update();
    }
    return button->popup;
}
int qs_menu_indicator_width(QSWidget w) {
    auto *button = static_cast<SwiftButton *>(w);
    return button->popup && button->menuIndicator ? button->style()->pixelMetric(QStyle::PM_MenuButtonIndicator, nullptr, button) : 0;
}
int qs_button_down(QSWidget w) { return static_cast<QPushButton *>(w)->isDown(); }
int qs_window_has_focus(QSWindow *window) { return window->focusWidget() != nullptr; }
int qs_try_focus(QSWidget w) {
    auto *item = widget(w);
    if (!item->isEnabled() || item->focusPolicy() == Qt::NoFocus) return 0;
    auto *window = item->window();
    const QRect bounds(item->mapTo(window, QPoint()), item->size());
    if (!item->isVisibleTo(window) || !bounds.intersects(window->rect())) return 0;
    if (!item->hasFocus()) item->setFocus(Qt::OtherFocusReason);
    return 1;
}
void qs_focus(QSWidget w, int active) {
    if (active) qs_try_focus(w);
    else if (widget(w)->hasFocus()) widget(w)->clearFocus();
}
void qs_enabled(QSWidget w, int enabled) { widget(w)->setEnabled(enabled); }
void qs_accessible_control(QSWidget w, int selected, int button, int toggle, int link, int startsMedia) {
    auto *item = widget(w);
    const bool changed = item->property("qsSelected").toBool() != bool(selected);
    item->setProperty("qsSelected", bool(selected));
    item->setProperty("qsAXLink", bool(link));
    item->setProperty("qsAXButton", bool(button));
    item->setProperty("qsAXToggle", bool(toggle));
    item->setProperty("qsStartsMedia", bool(startsMedia));
    if (changed) {
        QAccessible::State state;
        state.selected = true;
        state.checked = bool(toggle);
        QAccessibleStateChangeEvent event(item, state);
        QAccessible::updateAccessibility(&event);
    }
}
void qs_group_actions_clear(QSWidget w) { static_cast<GroupWidget *>(w)->accessibilityActions.clear(); }
void qs_group_action(QSWidget w, const char *name) {
    static_cast<GroupWidget *>(w)->accessibilityActions.append(QString::fromUtf8(name));
}
void qs_accessibility(QSWidget w, const char *label, const char *identifier, const char *hint, int search) {
    widget(w)->setAccessibleDescription(QString::fromUtf8(hint));
    widget(w)->setProperty("qsSearchField", bool(search));
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
    if (auto *label = dynamic_cast<PlainLabel *>(item)) {
        auto metrics = label->fontMetrics();
        auto flags = Qt::TextExpandTabs | Qt::TextDontClip;
        auto natural = metrics.boundingRect(QRect(0, 0, 1000000, 1000000), flags, label->source);
        int ideal = qMax(0, natural.width());
        int available = width < 0 || !std::isfinite(width) ? ideal : qMin(ideal, qMax(1, qRound(width)));
        if (label->wordWrap() && available < ideal) flags |= Qt::TextWordWrap;
        auto box = metrics.boundingRect(QRect(0, 0, available, 1000000), flags, label->source);
        return {double(available), double(qMax(metrics.height(), box.height()))};
    }
    if (auto *editor = qobject_cast<QPlainTextEdit *>(item)) {
        return {0, double(editor->fontMetrics().height() * editor->blockCount())};
    }
    auto size = item->sizeHint();
    if (dynamic_cast<SwiftButton *>(item)) size.rwidth() += qs_menu_indicator_width(w);
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
    // A text line measured at a fractional width can wrap its final word if
    // rounding both edges gives the native document less than that width.
    const bool textLabel = dynamic_cast<AttributedLabel *>(item) || dynamic_cast<PlainLabel *>(item);
    const int right = enclose ? qCeil(origin.x() + width) : textLabel ? left + qCeil(width) : qRound(origin.x() + width);
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
    if (const auto brush = item->property("qsTextBrush"); brush.isValid())
        applyTextBrush(item, brush.value<QBrush>(), geometry.size());
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
    if (!group->property("qsDragSource").toBool() && !group->acceptDrops() && !group->hasContextMenu() && !group->tapCount && !group->windowDrag && group->pointerDrag.threshold < 0 && group->pinch.minimum < 0 && !group->property("qsHover").toBool() &&
        !group->testAttribute(Qt::WA_SetCursor) && !group->testAttribute(Qt::WA_Hover) &&
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
        if (child->isHidden() || child->isWindow()) continue;
        QRect footprint = child->geometry();
        if (group->sizedToContent && child->graphicsEffect())
            footprint = child->graphicsEffect()->boundingRectFor(child->rect()).translated(child->pos()).toAlignedRect();
        paint = paint.united(footprint.intersected(viewport));
    }
    if (paint == group->rect()) return;
    const QPoint offset = -paint.topLeft();
    group->layoutRect.translate(offset);
    group->setGeometry(QRect(group->pos() - offset, paint.size()));
    for (auto *child : children) if (!child->isWindow()) child->move(child->pos() + offset);
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
int qs_select_import_entry(QSWindow *window, const char *path, int extend) {
    for (auto *view : window->findChildren<QAbstractItemView *>()) {
        auto *model = qobject_cast<QFileSystemModel *>(view->model());
        if (!model || !view->isVisible()) continue;
        const auto index = model->index(QString::fromUtf8(path));
        if (!index.isValid() || view->rootIndex() != index.parent()) continue;
        auto changes = extend ? QItemSelectionModel::Select : QItemSelectionModel::ClearAndSelect;
        view->selectionModel()->select(index, changes | QItemSelectionModel::Rows);
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
    auto *popup = qobject_cast<QMenu *>(QApplication::activePopupWidget());
    auto *target = popup && window->findChildren<QMenu *>().contains(popup) ? popup->windowHandle() : window->windowHandle();
    auto combination = sequence[0];
    QKeyEvent press(QEvent::KeyPress, combination.key(), combination.keyboardModifiers());
    QKeyEvent release(QEvent::KeyRelease, combination.key(), combination.keyboardModifiers());
    QApplication::sendEvent(target, &press);
    for (int i = 0; i < repeats; ++i) {
        QKeyEvent repeated(QEvent::KeyPress, combination.key(), combination.keyboardModifiers(), QString(), true);
        QApplication::sendEvent(target, &repeated);
    }
    QApplication::sendEvent(target, &release);
    qs_flush();
    return 1;
}
int qs_key_escape(QSWindow *window) {
    QKeyEvent key(QEvent::KeyPress, Qt::Key_Escape, Qt::NoModifier);
    auto *modal = QApplication::activeModalWidget();
    QWidget *target = window->focusWidget() ? window->focusWidget() : window;
    if (modal && window->findChildren<QWidget *>().contains(modal)) target = modal;
    QApplication::sendEvent(target, &key);
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
int qs_open_context_menu(QSWindow *window, int x, int y, int keyboard) {
    const QPoint point(x, y);
    auto *target = keyboard ? window->focusWidget() : window->childAt(point);
    if (!target) return 0;
    const QPoint local = target->mapFrom(window, point), global = window->mapToGlobal(point);
    if (!keyboard) {
        // The offscreen platform does not synthesize a context request after the secondary click.
        QMouseEvent press(QEvent::MouseButtonPress, local, global, Qt::RightButton, Qt::RightButton, Qt::NoModifier);
        QApplication::sendEvent(target, &press);
        QMouseEvent release(QEvent::MouseButtonRelease, local, global, Qt::RightButton, Qt::NoButton, Qt::NoModifier);
        QApplication::sendEvent(target, &release);
    }
    QContextMenuEvent request(keyboard ? QContextMenuEvent::Keyboard : QContextMenuEvent::Mouse, local, global);
    QApplication::sendEvent(target, &request);
    qs_flush();
    return qobject_cast<QMenu *>(QApplication::activePopupWidget()) != nullptr;
}
static QAction *popupItem(QSWindow *window, const char *title) {
    auto *menu = qobject_cast<QMenu *>(QApplication::activePopupWidget());
    if (!menu || !window->findChildren<QMenu *>().contains(menu)) return nullptr;
    const auto label = QString::fromUtf8(title).replace("&", "&&");
    for (auto *item : menu->actions()) {
        if (!item->isSeparator() && item->text() == label) return item;
    }
    return nullptr;
}
int qs_popup_item_state(QSWindow *window, const char *title) {
    auto *item = popupItem(window, title);
    return item ? int(item->isEnabled()) | (int(item->isChecked()) << 1) : -1;
}
int qs_click_popup_item(QSWindow *window, const char *title) {
    auto *item = popupItem(window, title);
    if (!item || !item->isEnabled()) return 0;
    auto *menu = static_cast<QMenu *>(QApplication::activePopupWidget());
    const QPoint local = menu->actionGeometry(item).center(), global = menu->mapToGlobal(local);
    QMouseEvent move(QEvent::MouseMove, local, global, Qt::NoButton, Qt::NoButton, Qt::NoModifier);
    QApplication::sendEvent(menu, &move);
    QMouseEvent press(QEvent::MouseButtonPress, local, global, Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
    QApplication::sendEvent(menu, &press);
    QMouseEvent release(QEvent::MouseButtonRelease, local, global, Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
    QApplication::sendEvent(menu, &release);
    return 1;
}
static int clickPoint(QWidget *window, int x, int y, const QPointingDevice *device) {
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
static NativePopover *activePopover(QSWindow *owner) {
    auto *popup = dynamic_cast<NativePopover *>(QApplication::activePopupWidget());
    for (auto *parent = popup ? popup->parentWidget() : nullptr; parent; parent = parent->parentWidget())
        if (parent == owner) return popup;
    return nullptr;
}
QSRect qs_window_frame(QSWindow *window) {
    const auto r = window->frameGeometry();
    return {double(r.x()), double(r.y()), double(r.width()), double(r.height())};
}
QSRect qs_active_popover_frame(QSWindow *window) {
    auto *popup = activePopover(window);
    if (!popup) return {};
    const auto point = window->mapFromGlobal(popup->mapToGlobal(QPoint()));
    return {double(point.x()), double(point.y()), double(popup->width()), double(popup->height())};
}
int qs_click_popover(QSWindow *window, int x, int y) {
    auto *popup = activePopover(window);
    return popup ? clickPoint(popup, x, y, QPointingDevice::primaryPointingDevice()) : 0;
}
int qs_escape_popover(QSWindow *window) {
    auto *popup = activePopover(window);
    if (!popup) return 0;
    QKeyEvent escape(QEvent::KeyPress, Qt::Key_Escape, Qt::NoModifier);
    QApplication::sendEvent(popup, &escape);
    return escape.isAccepted();
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
void qs_native_pinch(QSWindow *window, int phase, double x, double y, double delta, unsigned long timestamp) {
    const QPointF point(x, y);
    auto type = phase == 0 ? Qt::BeginNativeGesture : phase == 1 ? Qt::ZoomNativeGesture : Qt::EndNativeGesture;
    static const QPointingDevice pad("Test touchpad", 46, QInputDevice::DeviceType::TouchPad, QPointingDevice::PointerType::Finger,
                                     QInputDevice::Capability::Position, 5, 1);
    QNativeGestureEvent input(type, &pad, 2, point, point, window->mapToGlobal(point), delta, {});
    input.setTimestamp(timestamp);
    QApplication::sendEvent(window->windowHandle(), &input);
    qs_flush();
}
void qs_move_pointer(QSWindow *window, double x, double y) {
    const QPointF local(x, y);
    QMouseEvent move(QEvent::MouseMove, local, local, window->mapToGlobal(local), Qt::NoButton, Qt::NoButton, Qt::NoModifier);
    QApplication::sendEvent(window->windowHandle(), &move);
    qs_flush();
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
    for (auto *item : window->findChildren<QWidget *>(QString::fromUtf8(id))) {
        auto *accessible = QAccessible::queryAccessibleInterface(item);
        if (accessible && accessible->role() == QAccessible::Link && accessible->state().linked &&
            accessible->text(QAccessible::Name) == QString::fromUtf8(name)) return 1;
    }
    return 0;
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
