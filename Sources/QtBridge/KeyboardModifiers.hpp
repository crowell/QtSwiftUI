#pragma once
#include <QtCore/Qt>
#include <cstdint>

int eventModifierFlags(Qt::KeyboardModifiers modifiers);
bool matchesGestureModifiers(intptr_t required, Qt::KeyboardModifiers modifiers);
