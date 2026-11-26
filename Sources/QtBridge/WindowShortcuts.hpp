#pragma once
#include <QAbstractButton>
#include <QHash>
#include <QPointer>
#include <QPushButton>
#include <QShortcut>
#include <QWidget>

class WindowShortcuts {
    struct Binding {
        QShortcut *shortcut;
        QPointer<QAbstractButton> target;
    };
    QHash<QKeySequence, Binding> bindings;

    static Qt::Key specialKey(char32_t character, bool mirror) {
        switch (character) {
        case 0x08: return Qt::Key_Backspace;
        case 0x09: return Qt::Key_Tab;
        case 0x0d: return Qt::Key_Return;
        case 0x1b: return Qt::Key_Escape;
        case 0xf700: return Qt::Key_Up;
        case 0xf701: return Qt::Key_Down;
        case 0xf702: return mirror ? Qt::Key_Right : Qt::Key_Left;
        case 0xf703: return mirror ? Qt::Key_Left : Qt::Key_Right;
        case 0xf728: return Qt::Key_Delete;
        case 0xf729: return Qt::Key_Home;
        case 0xf72b: return Qt::Key_End;
        case 0xf72c: return Qt::Key_PageUp;
        case 0xf72d: return Qt::Key_PageDown;
        case 0xf739: return Qt::Key_Clear;
        default: return static_cast<Qt::Key>(QChar::toUpper(character));
        }
    }

public:
    void begin() {
        for (auto &binding : bindings) binding.target.clear();
    }
    void add(QWidget *window, QAbstractButton *button, const QString &character, int flags, bool automatic) {
        const auto scalars = character.normalized(QString::NormalizationForm_C).toUcs4();
        if (auto *push = qobject_cast<QPushButton *>(button))
            push->setDefault(character == QStringLiteral("\r") && flags == 0);
        // Qt's key events expose Shift, Control, Alt, Meta and the keypad flag.
        if (!button->isEnabled() || scalars.size() != 1 || (flags & ~62) != 0) return;
        Qt::KeyboardModifiers modifiers;
        if (flags & 2) modifiers |= Qt::ShiftModifier;
        if (flags & 4) modifiers |= Qt::ControlModifier;
        if (flags & 8) modifiers |= Qt::AltModifier;
        if (flags & 16) modifiers |= Qt::MetaModifier;
        if (flags & 32) modifiers |= Qt::KeypadModifier;
        auto key = specialKey(scalars.first(), automatic && button->isRightToLeft());
        const QKeySequence sequence(QKeyCombination(modifiers, key));
        auto it = bindings.find(sequence);
        if (it == bindings.end()) {
            auto *shortcut = new QShortcut(sequence, window);
            it = bindings.insert(sequence, {shortcut, nullptr});
            QObject::connect(shortcut, &QShortcut::activated, window, [this, sequence] {
                const auto target = bindings.value(sequence).target;
                if (target && target->isEnabled() && target->isVisible()) target->click();
            });
        }
        // Registration follows the Swift view tree, including keyed collections.
        if (!it->target) it->target = button;
    }
    void finish() {
        for (auto it = bindings.begin(); it != bindings.end();) {
            if (it->target) { ++it; continue; }
            delete it->shortcut;
            it = bindings.erase(it);
        }
    }
};
