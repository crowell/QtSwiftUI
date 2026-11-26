#pragma once
#include "RegisteredFonts.hpp"
#include "TextElision.hpp"
#include "TextStrike.hpp"
#include <QTextBrowser>
#include <QPointer>
#include <QScrollBar>
#include <QWheelEvent>
#include <QTextCursor>
#include <QTextDocument>
#include <QAbstractTextDocumentLayout>
#include <QTextBlock>
#include <cmath>
#include <optional>

// Keep native QTextCharFormats intact for painting, link hit testing and selection.
class AttributedLabel final : public QTextBrowser {
public:
    explicit AttributedLabel(QWidget *parent) : QTextBrowser(parent) {
        setFrameShape(QFrame::NoFrame);
        setHorizontalScrollBarPolicy(Qt::ScrollBarAlwaysOff);
        setVerticalScrollBarPolicy(Qt::ScrollBarAlwaysOff);
        setOpenExternalLinks(false);
        setOpenLinks(false);
        viewport()->setAutoFillBackground(false);
    }

    void setLayoutOptions(Qt::Alignment alignment, bool wrap) {
        wraps = wrap;
        option.setAlignment(alignment);
        option.setWrapMode(wrap ? QTextOption::WrapAtWordBoundaryOrAnywhere : QTextOption::NoWrap);
    }

    void begin() {
        pending.clear();
        content.clear();
        content.setDefaultTextOption(option);
        content.setDocumentMargin(0);
        content.setDefaultFont(font());
        hasLinks = false;
        hasCustomStrikes = false;
    }
    void append(const QString &text, const char *link, const char *foreground, const char *background,
                const char *family, double size, int weight, bool italic, int underline, const char *underlineColor, int strike, const char *strikeColor) {
        QTextCharFormat format;
        if (*link) {
            hasLinks = true;
            format.setAnchor(true);
            format.setAnchorHref(QString::fromUtf8(link));
            format.setForeground(palette().color(QPalette::Link));
            format.setFontUnderline(false);
        }
        if (*foreground) format.setForeground(QColor(QString::fromUtf8(foreground)));
        if (*background) format.setBackground(QColor(QString::fromUtf8(background)));
        if (size > 0) {
            QFont face = resolveFont(font(), QString::fromUtf8(family), weight, italic);
            face.setPixelSize(qMax(1, qRound(size)));
            face.setLetterSpacing(font().letterSpacingType(), font().letterSpacing());
            format.setFont(face);
        }
        if (underline) format.setUnderlineStyle(static_cast<QTextCharFormat::UnderlineStyle>(underline));
        if (*underlineColor) format.setUnderlineColor(QColor(QString::fromUtf8(underlineColor)));
        hasCustomStrikes |= setStrikeFormat(format, strike, QString::fromUtf8(strikeColor));
        pending.append({text, format});
        QTextCursor cursor(&content);
        cursor.movePosition(QTextCursor::End);
        cursor.insertText(text, format);
    }
    void finish(bool selectable, double requestedSpacing) {
        const qreal spacing = std::isfinite(requestedSpacing) ? qMax(0.0, requestedSpacing) : 0;
        // Qt 6.4's FreeType backend can report the height of an unscaled sbix
        // strike even though it draws the glyph at the requested pixel size.
        // Keep the original graphemes and anchors selectable in the text document.
        for (auto block = content.begin(); block.isValid(); block = block.next()) {
            bool oversizedStrike = false;
            qreal lineHeight = QFontMetricsF(font()).height();
            for (auto it = block.begin(); !it.atEnd(); ++it) {
                const QFont face = it.fragment().charFormat().font().resolve(font());
                const auto height = QFontMetricsF(face).height();
                const auto size = face.pixelSize();
                if (size > 0 && height > 3 * size && !QRawFont::fromFont(face).fontTable("sbix").isEmpty()) {
                    oversizedStrike = true;
                    lineHeight = qMax(lineHeight, qreal(size));
                } else {
                    lineHeight = qMax(lineHeight, height);
                }
            }
            if (oversizedStrike || spacing > 0) {
                QTextCursor cursor(block);
                auto format = block.blockFormat();
                if (oversizedStrike)
                    format.setLineHeight(std::ceil(lineHeight) + spacing, QTextBlockFormat::FixedHeight);
                else
                    format.setLineHeight(spacing, QTextBlockFormat::LineDistanceHeight);
                cursor.setBlockFormat(format);
            }
        }
        auto flags = hasLinks ? Qt::LinksAccessibleByMouse | Qt::LinksAccessibleByKeyboard : Qt::NoTextInteraction;
        if (selectable) flags |= Qt::TextSelectableByMouse | Qt::TextSelectableByKeyboard;
        if (flags != textInteractionFlags()) setTextInteractionFlags(flags);
        const auto alignment = option.alignment();
        if (pending == displayed && font() == displayedFont && displayedAlignment == alignment && displayedWrap == wraps && lineSpacing == spacing) return;
        lineSpacing = spacing;
        displayed = pending;
        displayedFont = font();
        displayedAlignment = alignment;
        displayedWrap = wraps;
        displayWidth = -1;
        truncated = false;
        replaceDocument(content.clone(this));
    }
    void display(int limit, Qt::TextElideMode mode) {
        const int width = viewport()->width();
        if (displayWidth == width && displayLimit == limit && displayMode == mode) return;
        displayWidth = width;
        displayLimit = limit;
        displayMode = mode;
        if (auto shortened = elidedDocument(content, width, limit, mode)) {
            truncated = true;
            shortened->setParent(this);
            replaceDocument(shortened.release());
        } else if (truncated) {
            truncated = false;
            replaceDocument(content.clone(this));
        }
    }
    QString sourceText() const { return content.toPlainText(); }

    std::optional<qreal> intrinsicWidth(int limit, Qt::TextElideMode mode) {
        if (limit <= 0 || content.blockCount() <= limit) return std::nullopt;
        // With no wrapping, the last visible paragraph still needs room for its truncation mark.
        content.setTextWidth(-1);
        const qreal natural = content.idealWidth();
        auto visible = elidedDocument(content, natural + QFontMetricsF(font()).maxWidth() + 1, limit, mode);
        if (!visible) return std::nullopt;
        visible->setTextWidth(-1);
        return std::ceil(visible->idealWidth());
    }

private:
    void replaceDocument(QTextDocument *next) {
        const auto selection = textCursor();
        const int anchor = selection.anchor(), position = selection.position();
        QPointer<QTextDocument> previous = document();
        setDocument(next);
        if (previous && previous->parent() == this) delete previous;
        QTextCursor cursor(document());
        cursor.setPosition(qMin(anchor, document()->characterCount() - 1));
        cursor.setPosition(qMin(position, document()->characterCount() - 1), QTextCursor::KeepAnchor);
        setTextCursor(cursor);
        alignDocument();
    }
public:
    QSizeF measure(double width) {
        content.setTextWidth(-1);
        const auto ideal = std::ceil(content.idealWidth());
        const auto available = std::isfinite(width) && width >= 0 ? qMin(ideal, width) : ideal;
        content.setTextWidth(available);
        return {available, std::ceil(content.size().height() - lineSpacing)};
    }

    QSBaselines baselines(double width, double height) {
        const auto measured = measure(width);
        auto baseline = [&](QTextBlock block, bool last) {
            auto *layout = block.layout();
            const auto line = layout->lineAt(last ? layout->lineCount() - 1 : 0);
            return (height - measured.height()) / 2 + content.documentLayout()->blockBoundingRect(block).top()
                 + line.y() + line.ascent();
        };
        return {baseline(content.firstBlock(), false), baseline(content.lastBlock(), true)};
    }

private:
    void paintEvent(QPaintEvent *event) override {
        QTextBrowser::paintEvent(event);
        if (hasCustomStrikes) {
            QPainter painter(viewport());
            painter.setClipRegion(event->region());
            painter.translate(-horizontalScrollBar()->value(), -verticalScrollBar()->value());
            drawTextStrikes(painter, *document(), palette());
        }
    }
    void resizeEvent(QResizeEvent *event) override {
        QTextBrowser::resizeEvent(event);
        alignDocument();
    }
    void wheelEvent(QWheelEvent *event) override { event->ignore(); }

    void alignDocument() {
        document()->setTextWidth(viewport()->width());
        const int top = qMax(0, int((height() - (document()->size().height() - lineSpacing)) / 2));
        if (viewportMargins().top() != top) setViewportMargins(0, top, 0, 0);
        verticalScrollBar()->setValue(0);
    }

    QTextDocument content;
    QList<QPair<QString, QTextCharFormat>> pending, displayed;
    QFont displayedFont;
    QTextOption option;
    Qt::Alignment displayedAlignment;
    bool wraps = true, displayedWrap = true;
    qreal lineSpacing = 0;
    bool hasLinks = false, hasCustomStrikes = false;
    bool truncated = false;
    int displayWidth = -1, displayLimit = 0;
    Qt::TextElideMode displayMode = Qt::ElideRight;
};
