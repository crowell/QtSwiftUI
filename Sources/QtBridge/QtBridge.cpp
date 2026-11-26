#include "QtBridge.h"
#include <QApplication>
#include <QAccessibleWidget>
#include <QCheckBox>
#include <QDir>
#include <QLabel>
#include <QLineEdit>
#include <QKeyEvent>
#include <QMouseEvent>
#include <QPainter>
#include <QPainterPath>
#include <QProgressBar>
#include <QPushButton>
#include <QResizeEvent>
#include <QScrollArea>
#include <QSignalBlocker>
#include <QSlider>
#include <QTimer>
#include <cmath>

namespace {
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
};
class AccessibleGroup final : public QAccessibleWidget {
public:
    explicit AccessibleGroup(GroupWidget *group) : QAccessibleWidget(group), group(group) {}
    QAccessible::Role role() const override { return group->isImage ? QAccessible::Graphic : QAccessible::Grouping; }
    int childCount() const override { return group->exposeChildren ? QAccessibleWidget::childCount() : 0; }
    QAccessibleInterface *child(int index) const override { return group->exposeChildren ? QAccessibleWidget::child(index) : nullptr; }
private:
    GroupWidget *group;
};
class Surface final : public QWidget {
public:
    using QWidget::QWidget;
    QColor fill;
    QPainterPath path;
    bool customPath = false;
    double radius = 0;
    void paintEvent(QPaintEvent *) override {
        QPainter painter(this);
        painter.setRenderHint(QPainter::Antialiasing);
        painter.setPen(Qt::NoPen);
        painter.setBrush(fill);
        const double r = std::min(radius, std::min(width(), height()) / 2.0);
        if (customPath) painter.drawPath(path);
        else painter.drawRoundedRect(QRectF(rect()), r, r);
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
    case QSButton: {
        auto *button = new QPushButton(container);
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
    case QSGroup: {
        auto *group = new GroupWidget(container);
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
    if (auto *label = qobject_cast<QLabel *>(widget(w))) label->setText(text);
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
void qs_style(QSWidget w, double points, int weight, int italic, const char *color, int alignment, int wrap) {
    auto *item = widget(w);
    QFont font = application().font();
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
void qs_path_reset(QSWidget w) {
    auto *surface = static_cast<Surface *>(w);
    surface->customPath = true;
    surface->path = QPainterPath();
    surface->path.setFillRule(Qt::WindingFill);
}
void qs_path_step(QSWidget w, int op, double x, double y, double a, double b, double c, double d) {
    auto &path = static_cast<Surface *>(w)->path;
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
    auto point = widget(w)->mapTo(widget(w)->window(), QPoint(0, 0));
    return {double(point.x()), double(point.y())};
}
void qs_place(QSWidget w, double x, double y, double width, double height) {
    widget(w)->setGeometry(qRound(x), qRound(y), qMax(0, qRound(x + width) - qRound(x)), qMax(0, qRound(y + height) - qRound(y)));
    widget(w)->raise();
    widget(w)->show();
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
int qs_read_text(QSWindow *window, const char *id, const char *expected) {
    auto *label = window->findChild<QLabel *>(QString::fromUtf8(id));
    return label && label->text() == QString::fromUtf8(expected);
}
