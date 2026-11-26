#pragma once
#include <QMenu>
#include <QPushButton>

class NativeMenu final : public QMenu {
public:
    explicit NativeMenu(QPushButton *anchor);
    void open(bool fromKeyboard);
protected:
    bool eventFilter(QObject *source, QEvent *event) override;
private:
    QPushButton *anchor;
};
