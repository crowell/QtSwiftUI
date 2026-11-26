#pragma once
#include <QButtonGroup>
#include <QAccessibleWidget>
#include <QComboBox>
#include <QAbstractItemView>
#include <QBoxLayout>
#include <QPushButton>
#include <QRadioButton>
#include <QSignalBlocker>
#include <QVector>
#include "SymbolIcons.hpp"

class AccessiblePicker final : public QAccessibleWidget {
    QComboBox *picker;
public:
    explicit AccessiblePicker(QComboBox *picker) : QAccessibleWidget(picker, QAccessible::ComboBox), picker(picker) {}
    QString text(QAccessible::Text kind) const override {
        if (kind == QAccessible::Value) return picker->currentText();
        return QAccessibleWidget::text(kind);
    }
    QAccessible::State state() const override {
        auto result = QAccessibleWidget::state();
        result.hasPopup = true;
        result.expandable = true;
        result.expanded = picker->view()->isVisible();
        result.collapsed = !result.expanded;
        return result;
    }
    int childCount() const override { return picker->view()->isVisible() ? 1 : 0; }
    QAccessibleInterface *child(int index) const override {
        return index == 0 && childCount() ? QAccessible::queryAccessibleInterface(picker->view()) : nullptr;
    }
    int indexOfChild(const QAccessibleInterface *item) const override {
        return item && childCount() && item->object() == picker->view() ? 0 : -1;
    }
    QStringList actionNames() const override {
        auto names = QAccessibleWidget::actionNames();
        if (picker->isEnabled()) names.append(showMenuAction());
        return names;
    }
    void doAction(const QString &action) override {
        if (action == showMenuAction() && picker->isEnabled()) picker->showPopup();
        else QAccessibleWidget::doAction(action);
    }
};

class PickerButtons final : public QWidget {
    bool radio;
    QBoxLayout *row;
    QVector<QAbstractButton *> options;

public:
    QButtonGroup group;
    PickerButtons(QWidget *parent, bool radio) : QWidget(parent), radio(radio),
        row(new QBoxLayout(radio ? QBoxLayout::TopToBottom : QBoxLayout::LeftToRight, this)), group(this) {
        row->setContentsMargins(0, 0, 0, 0);
        row->setSpacing(radio ? 3 : 0);
    }
    void option(int index, const QString &title, const QString &symbol, bool enabled) {
        if (index == options.size()) {
            QAbstractButton *button;
            if (radio) button = new QRadioButton(this);
            else {
                auto *segment = new QPushButton(this);
                segment->setCheckable(true);
                button = segment;
            }
            group.addButton(button, index);
            options.push_back(button);
            row->addWidget(button);
        }
        auto *button = options.at(index);
        button->setText(QString(title).replace("&", "&&"));
        button->setEnabled(enabled);
        if (!symbol.isEmpty() || !button->icon().isNull())
            button->setIcon(systemSymbol(symbol, 16, palette().color(QPalette::ButtonText)));
    }
    void selection(int count, int selected) {
        const QSignalBlocker blocker(&group);
        while (options.size() > count) delete options.takeLast();
        // A multi-source picker can have no common selection.
        group.setExclusive(false);
        for (int i = 0; i < options.size(); ++i) options.at(i)->setChecked(i == selected);
        group.setExclusive(true);
        setFocusProxy(options.value(selected, options.value(0)));
    }
};
