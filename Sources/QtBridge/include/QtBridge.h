#pragma once
#ifdef __cplusplus
extern "C" {
#endif

typedef struct QSWindow QSWindow;
typedef void *QSWidget;
typedef struct { double width, height; } QSSize;
typedef void (*QSRender)(void *context, int width, int height);
enum QSEventKind { QSActivate, QSFocusChanged, QSSubmit, QSPressedChanged };
typedef void (*QSEvent)(void *context, int id, enum QSEventKind kind, const char *value);
enum QSKind { QSLabel, QSButton, QSToggle, QSEdit, QSSecureEdit, QSSurface, QSScroll, QSSlider, QSProgress, QSGroup };

QSWindow *qs_window(const char *title, void *context, QSRender render, QSEvent event);
void qs_open(QSWindow *, int width, int height);
void qs_update(QSWindow *);
typedef void (*QSPump)(void);
int qs_run(QSWindow *, const char *screenshot, QSPump pump);
void qs_close(QSWindow *);
QSWidget qs_create(QSWindow *, QSWidget parent, enum QSKind, int id);
QSWidget qs_scroll_content(QSWidget);
void qs_scroll_size(QSWidget, int width, int height);
void qs_scroll_axes(QSWidget, int horizontal, int vertical);
void qs_destroy(QSWidget);
void qs_text(QSWidget, const char *);
void qs_hint(QSWidget, const char *);
void qs_checked(QSWidget, int);
void qs_value(QSWidget, double);
void qs_style(QSWidget, double points, int weight, int italic, const char *color, int alignment, int wrap);
void qs_surface(QSWidget, const char *color, double radius);
void qs_path_reset(QSWidget);
void qs_path_step(QSWidget, int op, double x, double y, double a, double b, double c, double d);
void qs_group(QSWidget, int exposeChildren, int isImage);
void qs_plain_button(QSWidget, int);
int qs_button_down(QSWidget);
void qs_focus(QSWidget, int active);
void qs_enabled(QSWidget, int);
void qs_accessibility(QSWidget, const char *label, const char *identifier);
QSSize qs_measure(QSWidget, double width);
QSSize qs_origin(QSWidget);
void qs_place(QSWidget, double x, double y, double width, double height);

// Drive the native controls in the offscreen integration tests.
void qs_flush(void);
int qs_click(QSWindow *, const char *identifier);
int qs_enter(QSWindow *, const char *identifier, const char *value);
int qs_read_text(QSWindow *, const char *identifier, const char *expected);
int qs_key_return(QSWindow *, const char *identifier);
int qs_has_focus(QSWindow *, const char *identifier);
int qs_mouse_click(QSWindow *, const char *identifier);
int qs_mouse_button(QSWindow *, const char *identifier, int down);
#ifdef __cplusplus
}
#endif
