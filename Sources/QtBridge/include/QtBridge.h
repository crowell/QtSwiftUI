#pragma once
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif

typedef struct QSWindow QSWindow;
typedef void *QSWidget;
typedef struct { double width, height; } QSSize;
typedef struct { double x, y, width, height; } QSRect;
typedef struct { double a, b, c, d, tx, ty; } QSAffine;
typedef struct QSPath QSPath;
typedef void (*QSRender)(void *context, int width, int height);
enum QSEventKind { QSActivate, QSFocusChanged, QSSubmit, QSPressedChanged, QSExitCommand, QSHoverChanged };
typedef void (*QSEvent)(void *context, int id, enum QSEventKind kind, const char *value);
enum QSKind { QSLabel, QSButton, QSToggle, QSEdit, QSSecureEdit, QSSurface, QSScroll, QSSlider, QSProgress, QSGroup, QSCanvas, QSLink };

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
void qs_style(QSWidget, const char *family, double points, int weight, int italic, double tracking, const char *color, int alignment, int wrap);
void qs_selectable(QSWidget, int enabled);
void qs_exit_scope(QSWidget, int enabled);
void qs_request_close(QSWindow *);
int qs_open_url(const char *url);
void qs_surface(QSWidget, const char *color, double radius);
QSPath *qs_path_new(void);
void qs_path_delete(QSPath *);
QSRect qs_path_bounds(const QSPath *);
QSSize qs_path_position(const QSPath *);
int qs_path_contains(const QSPath *, double x, double y, int evenOdd);
void qs_path_step(QSPath *, int op, double x, double y, double a, double b, double c, double d);
void qs_path_append(QSPath *, const QSPath *, QSAffine);
void qs_path_stroke(QSPath *target, const QSPath *source, double width, int cap, int join, double miterLimit,
                    const double *dash, size_t count, double phase);
void qs_path_clip(QSPath *target, const QSPath *source, int evenOdd, int inverse);
void qs_canvas_clip(QSWidget, const QSPath *);
void qs_canvas_blur(QSWidget, double radius, unsigned blurOptions, unsigned filterOptions);
void qs_surface_path(QSWidget, const QSPath *, int evenOdd, int antialias);
void qs_canvas_clear(QSWidget);
void qs_canvas_path(QSWidget, const QSPath *, QSAffine, double opacity, double lineWidth, int evenOdd, int antialias);
void qs_canvas_color(QSWidget, const char *color);
void qs_canvas_gradient(QSWidget, double x1, double y1, double x2, double y2);
void qs_canvas_stop(QSWidget, double location, const char *color);
void qs_hit_testing(QSWidget, int enabled);
void qs_group(QSWidget, int exposeChildren, int isImage);
void qs_group_hidden(QSWidget, int hidden);
void qs_group_hover(QSWidget, int enabled);
void qs_group_opacity(QSWidget, double value);
void qs_help(QSWidget, const char *text);
unsigned qs_pixel(QSWindow *, int x, int y);
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
int qs_key_escape(QSWindow *);
int qs_scroll_to_end(QSWindow *);
int qs_hover(QSWindow *, const char *identifier, int inside);
int qs_has_help(QSWindow *, const char *identifier, const char *expected);
int qs_is_named_link(QSWindow *, const char *identifier, const char *name);
int qs_select_text(QSWindow *, const char *identifier, int start, int length, const char *expected);
int qs_fixed_font(QSWindow *, const char *identifier);
int qs_has_focus(QSWindow *, const char *identifier);
int qs_mouse_click(QSWindow *, const char *identifier);
int qs_mouse_button(QSWindow *, const char *identifier, int down);
#ifdef __cplusplus
}
#endif
