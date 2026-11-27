#include "QtBridge.h"
#include "PlainTextEditor.hpp"
#include <QFontMetricsF>
#include <QLineEdit>
#include <QTextLayout>
#include <cmath>
#include <limits>

double qs_field_height(QSWidget w, double width, int minimum, int maximum) {
    return qs_field_size(w, width < 0 ? std::numeric_limits<double>::infinity() : width, -1, minimum, maximum).height;
}

QSSize qs_field_size(QSWidget handle, double width, double height, int minimumLines, int maximumLines) {
    auto *widget = static_cast<QWidget *>(handle);
    widget->ensurePolished();
    auto *multi = dynamic_cast<PlainTextEditor *>(widget);
    auto *single = qobject_cast<QLineEdit *>(widget);
    const bool framed = multi ? multi->frameShape() != QFrame::NoFrame : single->hasFrame();
    const double horizontalInsets = framed ? 12 : 4;
    const double verticalInsets = framed ? 8 : 0;
    const double lineHeight = std::ceil(QFontMetricsF(widget->font()).lineSpacing());

    // A secure field has zero ideal width for every value and prompt.
    if (single && single->echoMode() != QLineEdit::Normal) {
        const auto lines = framed ? 1 : single->text().count(QChar::LineFeed) + 1;
        return {qMax(0.0, width), lines * lineHeight + verticalInsets};
    }

    QString text = multi ? multi->value() : single->text();
    if (text.isEmpty()) text = multi ? multi->placeholderText() : single->placeholderText();
    const bool ideal = width < 0;
    const bool wrap = multi && width > 0 && std::isfinite(width);
    const double available = qMax(1.0, width - horizontalInsets);
    const int limit = multi ? maximumLines : (ideal ? 0 : 1);

    double longest = 0;
    int lines = 0;
    for (const auto paragraph : QStringView(text).tokenize(u'\n')) {
        QTextLayout layout(paragraph.toString(), widget->font());
        QTextOption option = multi ? multi->document()->defaultTextOption() : QTextOption();
        option.setWrapMode(wrap ? QTextOption::WrapAtWordBoundaryOrAnywhere : QTextOption::NoWrap);
        option.setFlags(option.flags() | QTextOption::IncludeTrailingSpaces);
        layout.setTextOption(option);
        layout.beginLayout();
        for (auto line = layout.createLine(); line.isValid(); line = layout.createLine()) {
            if (wrap) line.setLineWidth(available);
            else line.setNumColumns(std::numeric_limits<int>::max());
            longest = qMax(longest, line.horizontalAdvance());
            ++lines;
            if (limit > 0 && lines >= limit) break;
        }
        layout.endLayout();
        if (limit > 0 && lines >= limit) break;
    }
    double naturalHeight = qMax(1, lines) * lineHeight + verticalInsets;
    if (multi && !ideal) {
        if (height >= 0) naturalHeight = qMin(height, naturalHeight);
        if (minimumLines > 0) naturalHeight = qMax(naturalHeight, minimumLines * lineHeight + verticalInsets);
    }
    return {ideal ? longest + horizontalInsets : width, naturalHeight};
}
