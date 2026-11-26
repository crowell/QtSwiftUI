#pragma once
#include <QTextDocument>
#include <memory>

// Returns a display document only when text extends beyond the last visible line.
// The source document remains available for measurement, accessibility and reflow.
std::unique_ptr<QTextDocument> elidedDocument(QTextDocument &source, qreal width, int lines,
                                             Qt::TextElideMode mode);
