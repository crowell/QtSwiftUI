#pragma once
#include <QPainterPath>

// Return the portion of a path between two fractions of its total arc length.
QPainterPath trimmed(const QPainterPath &path, double start, double end);
