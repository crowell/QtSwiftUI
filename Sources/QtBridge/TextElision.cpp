#include "TextElision.hpp"
#include <QTextBlock>
#include <QTextBoundaryFinder>
#include <QTextCursor>
#include <QTextDocumentFragment>
#include <QTextLayout>
#include <optional>

namespace {
void appendRange(QTextCursor &out, QTextDocument &source, int from, int to) {
    if (to <= from) return;
    QTextCursor span(&source);
    span.setPosition(from);
    span.setPosition(to, QTextCursor::KeepAnchor);
    out.insertFragment(span.selection());
}

struct LastLine {
    int start;
    int end;
    bool wrapped;
    bool paragraphOverflows;
};

std::optional<LastLine> lastVisibleLine(QTextDocument &source, int limit, qreal width) {
    source.setTextWidth(width);
    (void)source.size(); // Ensure each QTextBlock has a laid-out set of lines.
    int count = 0;
    for (auto block = source.begin(); block.isValid(); block = block.next()) {
        auto *layout = block.layout();
        for (int i = 0; i < layout->lineCount(); ++i) {
            const auto line = layout->lineAt(i);
            if (++count != limit) continue;
            const bool hasMore = i + 1 < layout->lineCount() || block.next().isValid();
            if (!hasMore && line.naturalTextWidth() <= width) return std::nullopt;
            return LastLine{block.position() + line.textStart(), block.position() + block.length() - 1,
                            i > 0, i + 1 < layout->lineCount() || line.naturalTextWidth() > width};
        }
    }
    return std::nullopt;
}
}

std::unique_ptr<QTextDocument> elidedDocument(QTextDocument &source, qreal width, int lines, Qt::TextElideMode mode) {
    if (lines <= 0 || width <= 0) return {};
    const auto last = lastVisibleLine(source, lines, width);
    if (!last) return {};

    const QString text = source.toPlainText().mid(last->start, last->end - last->start);
    QVector<int> boundaries{0};
    QTextBoundaryFinder finder(QTextBoundaryFinder::Grapheme, text);
    for (int end = finder.toNextBoundary(); end != -1; end = finder.toNextBoundary()) boundaries.append(end);
    const int length = boundaries.size() - 1;
    const bool needsToken = mode == Qt::ElideRight || last->paragraphOverflows;

    auto writeLastLine = [&](QTextCursor &dst, int keep) {
        if (!needsToken) { appendRange(dst, source, last->start, last->end); return; }
        const int front = mode == Qt::ElideRight ? keep : mode == Qt::ElideLeft ? 0 : (keep + 1) / 2;
        const int back = keep - front;
        appendRange(dst, source, last->start, last->start + boundaries[front]);
        QTextCursor style(&source);
        style.setPosition(qMin(last->end, last->start + qMax(1, boundaries[front])));
        auto format = style.charFormat();
        format.setAnchor(false);
        format.setAnchorHref(QString());
        dst.insertText(QString(QChar(0x2026)), format);
        appendRange(dst, source, last->start + boundaries[length - back], last->end);
    };

    int best = length;
    if (needsToken) {
        int lo = 0, hi = length;
        while (lo < hi) {
            const int mid = lo + (hi - lo + 1) / 2;
            QTextDocument candidate;
            candidate.setDocumentMargin(0);
            candidate.setDefaultFont(source.defaultFont());
            QTextCursor cursor(&candidate);
            writeLastLine(cursor, mid);
            if (candidate.idealWidth() <= width) lo = mid;
            else hi = mid - 1;
        }
        best = lo;
    }

    std::unique_ptr<QTextDocument> display(source.clone());
    QTextCursor out(display.get());
    out.setPosition(last->start);
    out.movePosition(QTextCursor::End, QTextCursor::KeepAnchor);
    out.removeSelectedText();
    if (last->wrapped) {
        // The elided suffix must stay on the final line even if a shorter word would wrap back.
        out.insertText(QString(QChar::LineSeparator));
    }
    writeLastLine(out, best);
    display->setTextWidth(width);
    return display;
}
