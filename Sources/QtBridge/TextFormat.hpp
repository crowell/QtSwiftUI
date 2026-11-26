#pragma once
#include "RegisteredFonts.hpp"
#include "TextStrike.hpp"
#include <QPalette>

inline QTextCharFormat swiftTextFormat(const QFont &base, const QPalette &palette, const char *link, const char *foreground,
                                       const char *background, const char *family, double size, int weight, bool italic,
                                       int underline, const char *underlineColor, int strike, const char *strikeColor,
                                       bool &customStrike) {
    QTextCharFormat format;
    if (*link) {
        format.setAnchor(true);
        format.setAnchorHref(QString::fromUtf8(link));
        format.setForeground(palette.color(QPalette::Link));
        format.setFontUnderline(false);
    }
    if (*foreground) format.setForeground(QColor(QString::fromUtf8(foreground)));
    if (*background) format.setBackground(QColor(QString::fromUtf8(background)));
    if (size > 0) {
        QFont face = resolveFont(base, QString::fromUtf8(family), weight, italic);
        face.setPixelSize(qMax(1, qRound(size)));
        face.setLetterSpacing(base.letterSpacingType(), base.letterSpacing());
        format.setFont(face);
    }
    if (underline) format.setUnderlineStyle(static_cast<QTextCharFormat::UnderlineStyle>(underline));
    if (*underlineColor) format.setUnderlineColor(QColor(QString::fromUtf8(underlineColor)));
    customStrike = setStrikeFormat(format, strike, QString::fromUtf8(strikeColor));
    return format;
}
