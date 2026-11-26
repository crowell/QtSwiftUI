#pragma once
#include <QElapsedTimer>
#include <QPainter>
#include <QProgressBar>
#include <QTimer>

class BusyIndicator final : public QProgressBar {
public:
    explicit BusyIndicator(QWidget *parent) : QProgressBar(parent) {
        setRange(0, 0);
        setTextVisible(false);
        timer.setInterval(80);
        connect(&timer, &QTimer::timeout, this, [this] { update(); });
    }
protected:
    void showEvent(QShowEvent *event) override {
        QProgressBar::showEvent(event);
        clock.start();
        timer.start();
    }
    void hideEvent(QHideEvent *event) override {
        timer.stop();
        QProgressBar::hideEvent(event);
    }
    void paintEvent(QPaintEvent *) override {
        QPainter painter(this);
        painter.setRenderHint(QPainter::Antialiasing);
        painter.translate(width() / 2.0, height() / 2.0);
        const qreal diameter = qMin(width(), height());
        const int step = clock.isValid() ? (clock.elapsed() / 80) % 8 : 0;
        for (int i = 0; i < 8; ++i) {
            QColor ink = palette().color(QPalette::Text);
            ink.setAlpha(52 + 26 * ((i - step + 8) % 8));
            painter.setPen(QPen(ink, diameter * 0.10, Qt::SolidLine, Qt::RoundCap));
            painter.drawLine(QPointF(0, -diameter * 0.24), QPointF(0, -diameter * 0.42));
            painter.rotate(45);
        }
    }
private:
    QElapsedTimer clock;
    QTimer timer;
};
