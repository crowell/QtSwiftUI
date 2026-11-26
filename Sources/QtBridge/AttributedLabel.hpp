#pragma once
#include <QLabel>
#include <QTextCursor>
#include <QTextDocument>
#include <cmath>

// QLabel owns selection and link input. The same formatted document measures the label.
class AttributedLabel final : public QLabel {
public:
    explicit AttributedLabel(QWidget *parent) : QLabel(parent) {
        setTextFormat(Qt::RichText);
        setMargin(0);
        setIndent(0);
        setOpenExternalLinks(false);
    }

    void begin() {
        content.clear();
        content.setDocumentMargin(0);
        content.setDefaultFont(font());
        hasLinks = false;
    }
    void append(const QString &text, const char *link, const char *foreground, const char *background,
                const char *family, double size, int weight, bool italic) {
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
            QFont face = font();
            if (*family) face.setFamily(QString::fromUtf8(family));
            face.setPixelSize(qMax(1, qRound(size)));
            face.setWeight(static_cast<QFont::Weight>(weight));
            face.setItalic(italic);
            format.setFont(face);
        }
        QTextCursor cursor(&content);
        cursor.movePosition(QTextCursor::End);
        cursor.insertText(text, format);
    }
    void finish(bool selectable) {
        auto flags = hasLinks ? Qt::LinksAccessibleByMouse | Qt::LinksAccessibleByKeyboard : Qt::NoTextInteraction;
        if (selectable) flags |= Qt::TextSelectableByMouse | Qt::TextSelectableByKeyboard;
        if (flags != textInteractionFlags()) setTextInteractionFlags(flags);
        const QString html = content.toHtml();
        if (html != text()) setText(html);
    }
    QSizeF measure(double width) {
        content.setTextWidth(-1);
        const auto ideal = std::ceil(content.idealWidth());
        const auto available = wordWrap() && std::isfinite(width) && width >= 0 ? qMin(ideal, width) : ideal;
        content.setTextWidth(available);
        return {available, std::ceil(content.size().height())};
    }

private:
    QTextDocument content;
    bool hasLinks = false;
};
