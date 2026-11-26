#include "QtBridge.h"
#include "CanvasBlur.hpp"
#include <QApplication>
#include <QAccessibleWidget>
#include <QCheckBox>
#include <QDir>
#include <QDesktopServices>
#include <QUrl>
#include <QLabel>
#include <QFontInfo>
#include <QGraphicsOpacityEffect>
#include <QEnterEvent>
#include <QLineEdit>
#include <QKeyEvent>
#include <QMouseEvent>
#include <QPainter>
#include <QPainterPath>
#include <QProgressBar>
#include <QPushButton>
#include <QResizeEvent>
#include <QScrollArea>
#include <QScrollBar>
#include <QSignalBlocker>
#include <QSlider>
#include <QTimer>
#include <cmath>
#include <optional>
#include <vector>

struct QSPath : QPainterPath {};

namespace {
QTransform transform(QSAffine t) { return QTransform(t.a, t.b, t.c, t.d, t.tx, t.ty); }
QApplication *ownedApplication = nullptr;
int liveWindows = 0;
QApplication &application() {
    static int argc = 1;
    static char name[] = "QtSwiftUI";
    static char *argv[] = {name, nullptr};
    if (!qApp) ownedApplication = new QApplication(argc, argv);
    return *qApp;
}
class GroupWidget final : public QWidget {
public:
    using QWidget::QWidget;
    bool exposeChildren = true;
    bool isImage = false;
    bool accessibilityHidden = false;
};
class AccessibleGroup final : public QAccessibleWidget {
public:
    explicit AccessibleGroup(GroupWidget *group) : QAccessibleWidget(group), group(group) {}
    QAccessible::Role role() const override { return group->isImage ? QAccessible::Graphic : QAccessible::Grouping; }
    QAccessible::State state() const override {
        auto result = QAccessibleWidget::state();
        if (group->accessibilityHidden) result.invisible = true;
        return result;
    }
    int childCount() const override { return group->exposeChildren && !group->accessibilityHidden ? QAccessibleWidget::childCount() : 0; }
    QAccessibleInterface *child(int index) const override { return group->exposeChildren && !group->accessibilityHidden ? QAccessibleWidget::child(index) : nullptr; }
private:
    GroupWidget *group;
};
class AccessibleLink final : public QAccessibleWidget {
public:
    explicit AccessibleLink(QPushButton *button) : QAccessibleWidget(button, QAccessible::Link), button(button) {}
    QString text(QAccessible::Text kind) const override {
        const QString value = QAccessibleWidget::text(kind);
        if (kind != QAccessible::Name || !value.isEmpty()) return value;
        QStringList parts;
        for (const auto *label : button->findChildren<QLabel *>()) parts.append(label->text());
        return parts.join(' ');
    }
    QStringList actionNames() const override { return {QAccessibleActionInterface::pressAction()}; }
    void doAction(const QString &action) override {
        if (action == QAccessibleActionInterface::pressAction() && button->isEnabled()) button->click();
    }
    QAccessible::State state() const override {
        auto state = QAccessibleWidget::state();
        state.linked = true;
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
    bool pending = false;

    void schedule() {
        if (pending) return;
        pending = true;
        QTimer::singleShot(0, this, [this] {
            pending = false;
            render(context, width(), height());
        });
    }
    bool eventFilter(QObject *source, QEvent *input) override {
        if ((input->type() == QEvent::Enter || input->type() == QEvent::Leave) && source->property("qsHover").toBool()) {
            event(context, source->property("swiftId").toInt(), QSHoverChanged, input->type() == QEvent::Enter ? "1" : "0");
        }
        if (input->type() == QEvent::FocusIn || input->type() == QEvent::FocusOut) {
            event(context, source->property("swiftId").toInt(), QSFocusChanged,
                  input->type() == QEvent::FocusIn ? "1" : "0");
        }
        return false;
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
};

QSWindow *qs_window(const char *title, void *context, QSRender render, QSEvent event) {
    application();
    ++liveWindows;
    auto *window = new QSWindow();
    window->context = context;
    window->render = render;
    window->event = event;
    window->setWindowTitle(QString::fromUtf8(title));
    return window;
}
void qs_open(QSWindow *window, int width, int height) {
    window->resize(width, height);
    window->show();
    qs_flush();
}
void qs_request_close(QSWindow *window) { window->close(); }
int qs_open_url(const char *url) {
    const QUrl destination = QUrl::fromEncoded(QByteArray(url), QUrl::StrictMode);
    return destination.isValid() && !destination.isRelative() && QDesktopServices::openUrl(destination);
}
void qs_update(QSWindow *window) { window->schedule(); }
void qs_flush() { application().processEvents(); }
int qs_run(QSWindow *window, const char *screenshot, QSPump pump) {
    // Swift's main actor and Foundation timers share the GUI thread with Qt.
    QTimer swiftEvents;
    QObject::connect(&swiftEvents, &QTimer::timeout, window, [pump] { pump(); });
    swiftEvents.start(16);
    if (screenshot) {
        auto capture = [window, path = QString::fromUtf8(screenshot)] {
            application().exit(window->grab().save(path, "PNG") ? 0 : 1);
        };
        QTimer::singleShot(qMax(0, qEnvironmentVariableIntValue("QTSWIFTUI_CAPTURE_DELAY_MS")), window, capture);
    }
    return application().exec();
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
    case QSLink: case QSButton: {
        auto *button = new QPushButton(container);
        if (kind == QSLink) {
            button->setCursor(Qt::PointingHandCursor);
            QAccessible::registerAccessibleInterface(new AccessibleLink(button));
        }
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
    case QSEdit: case QSSecureEdit: {
        auto *edit = new QLineEdit(container);
        if (kind == QSSecureEdit) edit->setEchoMode(QLineEdit::Password);
        window->observeFocus(edit, id);
        QObject::connect(edit, &QLineEdit::textEdited, window, [=](const QString &s) { window->event(window->context, id, QSActivate, s.toUtf8().constData()); });
        QObject::connect(edit, &QLineEdit::returnPressed, window, [=] { window->event(window->context, id, QSSubmit, ""); });
        return edit;
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
    case QSProgress: {
        auto *bar = new QProgressBar(container);
        bar->setTextVisible(false);
        return bar;
    }
    }
    return nullptr;
}
QSWidget qs_scroll_content(QSWidget w) { return static_cast<QScrollArea *>(w)->widget(); }
void qs_scroll_size(QSWidget w, int width, int height) { widget(qs_scroll_content(w))->resize(width, height); }
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
    if (auto *label = qobject_cast<QLabel *>(item)) {
        label->setWordWrap(wrap);
        label->setAlignment(Qt::AlignVCenter | (alignment < 0 ? Qt::AlignLeft : alignment > 0 ? Qt::AlignRight : Qt::AlignHCenter));
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
    auto rect = path->boundingRect();
    return {rect.x(), rect.y(), rect.width(), rect.height()};
}
QSSize qs_path_position(const QSPath *path) {
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
void qs_path_clip(QSPath *target, const QSPath *source, int evenOdd, int inverse) {
    QPainterPath shape = *source;
    shape.setFillRule(evenOdd ? Qt::OddEvenFill : Qt::WindingFill);
    static_cast<QPainterPath &>(*target) = inverse ? target->subtracted(shape) : target->intersected(shape);
}
void qs_canvas_clip(QSWidget w, const QSPath *path) {
    static_cast<CanvasWidget *>(w)->drawings.back().clip = *path;
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
void qs_canvas_gradient(QSWidget w, double x1, double y1, double x2, double y2) {
    static_cast<CanvasWidget *>(w)->drawings.back().gradient.emplace(x1, y1, x2, y2);
}
void qs_canvas_stop(QSWidget w, double location, const char *color) {
    static_cast<CanvasWidget *>(w)->drawings.back().gradient->setColorAt(location, QColor(QString::fromUtf8(color)));
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
    case 7: path.addRoundedRect(QRectF(x, y, a, b), c, d); break;
    }
}
void qs_group(QSWidget w, int exposeChildren, int isImage) {
    auto *group = static_cast<GroupWidget *>(w);
    group->exposeChildren = exposeChildren;
    group->isImage = isImage;
}
void qs_group_hidden(QSWidget w, int hidden) { static_cast<GroupWidget *>(w)->accessibilityHidden = hidden; }
void qs_group_hover(QSWidget w, int enabled) { widget(w)->setProperty("qsHover", bool(enabled)); }
void qs_help(QSWidget w, const char *text) { widget(w)->setToolTip(QString::fromUtf8(text)); }
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
void qs_accessibility(QSWidget w, const char *label, const char *identifier) {
    widget(w)->setAccessibleName(QString::fromUtf8(label));
    widget(w)->setObjectName(QString::fromUtf8(identifier));
}
QSSize qs_measure(QSWidget w, double width) {
    auto *item = widget(w);
    item->ensurePolished();
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
    auto size = item->sizeHint();
    return {double(size.width()), double(size.height())};
}
QSSize qs_origin(QSWidget w) {
    auto *item = widget(w);
    const auto point = QPointF(item->mapTo(item->window(), QPoint())) + item->property("qsFraction").toPointF();
    return {point.x(), point.y()};
}
void qs_place(QSWidget w, double x, double y, double width, double height) {
    auto *item = widget(w);
    const auto parentFraction = item->parentWidget()->property("qsFraction").toPointF();
    const QPointF origin(x + parentFraction.x(), y + parentFraction.y());
    // Keep fractional placement through grouping widgets. QPainter can retain it
    // when a SwiftUI drawing falls between Qt's integer widget coordinates.
    const bool vector = dynamic_cast<Surface *>(item) || dynamic_cast<CanvasWidget *>(item);
    const bool enclose = vector || dynamic_cast<GroupWidget *>(item);
    const int left = enclose ? qFloor(origin.x()) : qRound(origin.x());
    const int top = enclose ? qFloor(origin.y()) : qRound(origin.y());
    const int right = enclose ? qCeil(origin.x() + width) : qRound(origin.x() + width);
    const int bottom = enclose ? qCeil(origin.y() + height) : qRound(origin.y() + height);
    item->setProperty("qsFraction", origin - QPointF(left, top));
    if (vector) item->setProperty("qsSize", QSizeF(width, height));
    item->setGeometry(left, top, width > 0 ? qMax(0, right - left) : 0, height > 0 ? qMax(0, bottom - top) : 0);
    item->raise();
    item->show();
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
int qs_has_focus(QSWindow *window, const char *id) {
    auto *item = window->findChild<QWidget *>(QString::fromUtf8(id));
    return item && item->hasFocus();
}
int qs_mouse_button(QSWindow *window, const char *id, int down) {
    auto *button = window->findChild<QAbstractButton *>(QString::fromUtf8(id));
    if (!button || !button->isEnabled()) return 0;
    const auto location = button->mapTo(window, button->rect().center());
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
