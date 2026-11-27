#include "KeyboardModifiers.hpp"
#include <QGuiApplication>
#if QT_CONFIG(xcb)
#include <QtGui/qguiapplication_platform.h>
#include <X11/XKBlib.h>
#endif

int eventModifierFlags(Qt::KeyboardModifiers modifiers) {
    return (modifiers & Qt::ShiftModifier ? 2 : 0) | (modifiers & Qt::ControlModifier ? 4 : 0)
         | (modifiers & Qt::AltModifier ? 8 : 0) | (modifiers & Qt::MetaModifier ? 16 : 0)
         | (modifiers & Qt::KeypadModifier ? 32 : 0);
}

bool matchesGestureModifiers(intptr_t required, Qt::KeyboardModifiers modifiers) {
    if (!required) return true;
    int flags = eventModifierFlags(modifiers);
#if QT_CONFIG(xcb)
    // Qt omits the latched Caps Lock state and the hardware Fn key from KeyboardModifiers.
    if (required & (1 | 64)) {
        if (auto *native = qGuiApp->nativeInterface<QNativeInterface::QX11Application>()) {
            auto *display = native->display();
            if (required & 1) {
                Bool on = False;
                const Atom caps = XInternAtom(display, "Caps Lock", True);
                if (caps != None && XkbGetNamedIndicator(display, caps, nullptr, &on, nullptr, nullptr) && on) flags |= 1;
            }
            if (required & 64) {
                const KeySym symbol = XStringToKeysym("XF86Fn");
                const KeyCode code = symbol == NoSymbol ? 0 : XKeysymToKeycode(display, symbol);
                char keys[32];
                if (code && XQueryKeymap(display, keys) && (keys[code / 8] & (1 << (code % 8)))) flags |= 64;
            }
        }
    }
#endif
    return (flags & required) == required;
}
