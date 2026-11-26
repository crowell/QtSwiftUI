#pragma once
#include <QTextCursor>
#include <QTextDocument>
#include <memory>

struct QSTextParagraph {
    QTextDocument document;
    QTextCursor cursor{&document};
    std::unique_ptr<QTextDocument> display;
    bool customStrikes = false;
    QTextDocument &visible() { return display ? *display : document; }
    double tracking;
    QList<int> collapsedSeparators;
    bool endedWithCR = false;
    QSTextParagraph(QFont font, double tracking) : tracking(tracking) {
        font.setLetterSpacing(QFont::AbsoluteSpacing, tracking);
        document.setDocumentMargin(0);
        document.setDefaultFont(font);
    }
};
