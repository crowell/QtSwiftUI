#pragma once
#include <QTextCursor>
#include <QTextDocument>

struct QSTextParagraph {
    QTextDocument document;
    QTextCursor cursor{&document};
    double tracking;
    QList<int> collapsedSeparators;
    bool endedWithCR = false;
    QSTextParagraph(QFont font, double tracking) : tracking(tracking) {
        font.setLetterSpacing(QFont::AbsoluteSpacing, tracking);
        document.setDocumentMargin(0);
        document.setDefaultFont(font);
    }
};
