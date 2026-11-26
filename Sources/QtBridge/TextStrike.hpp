#pragma once
#include <QPainter>
#include <QTextCharFormat>
#include <QTextDocument>

bool setStrikeFormat(QTextCharFormat &format, int style, const QString &color);
void drawTextStrikes(QPainter &painter, QTextDocument &document, const QPalette &palette);
