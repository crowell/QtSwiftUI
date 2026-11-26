#include "QtBridge.h"
#include "NativeMenu.hpp"
#include <QKeyEvent>
#include <QVariant>

NativeMenu::NativeMenu(QPushButton *button) : QMenu(button), anchor(button) {
    button->installEventFilter(this);
    connect(button, &QPushButton::clicked, this, [this] { open(false); });
}

void NativeMenu::open(bool fromKeyboard) {
    if (isEmpty() || isVisible() || !anchor->isEnabled()) return;
    int x = anchor->layoutDirection() == Qt::RightToLeft ? anchor->width() - sizeHint().width() : 0;
    popup(anchor->mapToGlobal(QPoint(x, anchor->height())));
    if (fromKeyboard) {
        for (auto *item : actions()) {
            if (item->isEnabled() && !item->isSeparator()) { setActiveAction(item); break; }
        }
    }
}

bool NativeMenu::eventFilter(QObject *source, QEvent *event) {
    if (source == anchor && event->type() == QEvent::KeyPress) {
        auto *key = static_cast<QKeyEvent *>(event);
        if (key->key() == Qt::Key_Down || key->key() == Qt::Key_Space || key->key() == Qt::Key_Return || key->key() == Qt::Key_Enter) {
            open(true);
            return true;
        }
    }
    return QMenu::eventFilter(source, event);
}

namespace {
void removeItem(QMenu *menu, QAction *item) {
    auto *submenu = item->menu();
    menu->removeAction(item);
    if (submenu) delete submenu;
    else delete item;
}
}

// Update actions in place so focus and an open submenu survive unrelated view updates.
QSWidget qs_menu_item(QSWidget handle, int index, const char *title, int enabled, int checked, int separator, int submenu, int action) {
    auto *menu = static_cast<QMenu *>(handle);
    auto *item = menu->actions().value(index);
    if (!item || bool(item->menu()) != bool(submenu)) {
        auto *replacement = submenu ? (new QMenu(menu))->menuAction() : new QAction(menu);
        menu->insertAction(item, replacement);
        if (item) removeItem(menu, item);
        item = replacement;
    }
    // Qt interprets a single ampersand as a mnemonic.
    item->setText(QString::fromUtf8(title).replace("&", "&&"));
    item->setSeparator(separator);
    item->setEnabled(enabled);
    item->setCheckable(checked >= 0);
    if (checked >= 0) item->setChecked(checked != 0);
    item->setData(action);
    return item->menu();
}

void qs_menu_finish(QSWidget handle, int count) {
    auto *menu = static_cast<QMenu *>(handle);
    auto items = menu->actions();
    while (items.size() > count) removeItem(menu, items.takeLast());
}
