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
enum QSEventKind { QSActivate, QSFocusChanged, QSSubmit, QSPressedChanged, QSExitCommand, QSHoverChanged, QSIncrement, QSDecrement };
typedef void (*QSEvent)(void *context, int id, enum QSEventKind kind, const char *value);
enum QSKind { QSLabel, QSButton, QSToggle, QSEdit, QSSecureEdit, QSSurface, QSScroll, QSSlider, QSProgress, QSGroup, QSCanvas, QSLink };

QSWindow *qs_window(const char *title, void *context, QSRender render, QSEvent event);
void qs_open(QSWindow *, int width, int height);
void qs_update(QSWindow *);
double qs_window_scale(QSWindow *);
int qs_scene_phase(QSWindow *);
void qs_animation_frame(QSWindow *);
typedef void (*QSPump)(void);
int qs_run(QSWindow *, const char *screenshot, QSPump pump);
int qs_capture(QSWindow *, const char *path);
int qs_dark_ink(QSWindow *, int x, int y, int width, int height);
void qs_close(QSWindow *);
QSWidget qs_create(QSWindow *, QSWidget parent, enum QSKind, int id);
QSWidget qs_scroll_content(QSWidget);
QSRect qs_scroll_viewport(QSWidget);
void qs_scroll_size(QSWidget, int width, int height);
void qs_scroll_axes(QSWidget, int horizontal, int vertical);
void qs_destroy(QSWidget);
void qs_text(QSWidget, const char *);
void qs_hint(QSWidget, const char *);
void qs_checked(QSWidget, int);
void qs_value(QSWidget, double);
int qs_register_font(const char *path);
void qs_style(QSWidget, const char *family, double points, int weight, int italic, double tracking, const char *color, int alignment, int wrap);
void qs_selectable(QSWidget, int enabled);
void qs_exit_scope(QSWidget, int enabled);
void qs_request_close(QSWindow *);
void qs_shortcut_begin(QSWindow *);
void qs_shortcut_finish(QSWindow *);
void qs_button_shortcut(QSWindow *, QSWidget, const char *key, int flags, int automatic);
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
void qs_path_trim(QSPath *target, const QSPath *source, double from, double to);
void qs_canvas_clip(QSWidget, const QSPath *);
void qs_canvas_blur(QSWidget, double radius, unsigned blurOptions, unsigned filterOptions);
void qs_surface_path(QSWidget, const QSPath *, int evenOdd, int antialias);
void qs_canvas_clear(QSWidget);
void qs_canvas_path(QSWidget, const QSPath *, QSAffine, double opacity, double lineWidth, int evenOdd, int antialias);
void qs_canvas_color(QSWidget, const char *color);
void qs_canvas_gradient(QSWidget, double x1, double y1, double x2, double y2);
void qs_canvas_stop(QSWidget, double location, const char *color);
void qs_hit_testing(QSWidget, int enabled);
void qs_direction(QSWidget, int rtl);
void qs_group(QSWidget, int behavior, int isImage, int updatesFrequently, const char *value);
void qs_adjustable(QSWidget, int adjustable);
void qs_group_hidden(QSWidget, int hidden);
void qs_group_hover(QSWidget, int enabled);
typedef struct { double time, startX, startY, x, y, velocityX, velocityY; int ended; } QSDragSample;
typedef void (*QSDragHandler)(void *context, int id, QSDragSample sample);
void qs_set_drag_handler(QSWindow *, QSDragHandler);
typedef int (*QSKeyHandler)(void *context, int id, int phase, const char *characters, int modifiers);
void qs_set_key_handler(QSWindow *, QSKeyHandler);
void qs_group_gesture(QSWidget, int taps, int windowDrag, int simultaneous, double dragDistance, int inputs);
void qs_group_spin(QSWidget, int milliseconds);
void qs_group_opacity(QSWidget, double value);
void qs_group_rotation(QSWidget, double degrees, double anchorX, double anchorY);
void qs_group_shape(QSWidget, const QSPath *, int evenOdd);
void qs_group_clip(QSWidget, const QSPath *, int evenOdd, int antialias);
void qs_group_semantics(QSWidget, int heading, int modal);
void qs_group_finish_layout(QSWidget);
void qs_match_place(QSWidget drawing, QSWidget marker, double x, double y, double width, double height);
void qs_group_focus(QSWidget, int enabled, int interactions);
void qs_focus_effect(QSWidget, int enabled);
void qs_help(QSWidget, const char *text);
unsigned qs_pixel(QSWindow *, int x, int y);
void qs_plain_button(QSWidget, int);
int qs_button_down(QSWidget);
void qs_focus(QSWidget, int active);
void qs_enabled(QSWidget, int);
void qs_accessible_control(QSWidget, int selected, int button, int toggle);
void qs_accessibility(QSWidget, const char *label, const char *identifier);
QSSize qs_measure(QSWidget, double width);
QSSize qs_origin(QSWidget);
QSSize qs_tap_location(QSWidget);
void qs_place(QSWidget, double x, double y, double width, double height);

// Drive the native controls in the offscreen integration tests.
void qs_flush(void);
int qs_accessible_value_is(QSWindow *, const char *name, const char *value);
int qs_accessible_checked(QSWindow *, const char *name);
int qs_accessible_element(QSWindow *, const char *name, int childCount, const char *action);
int qs_click(QSWindow *, const char *identifier);
int qs_enter(QSWindow *, const char *identifier, const char *value);
int qs_read_text(QSWindow *, const char *identifier, const char *expected);
int qs_key_return(QSWindow *, const char *identifier);
int qs_key_escape(QSWindow *);
int qs_send_key_sequence(QSWindow *, const char *keys);
int qs_send_repeated_key(QSWindow *, const char *keys, int repeats);
void qs_minimize(QSWindow *, int minimized);
int qs_scroll_to_end(QSWindow *);
int qs_hover(QSWindow *, const char *identifier, int inside);
int qs_has_help(QSWindow *, const char *identifier, const char *expected);
int qs_is_named_link(QSWindow *, const char *identifier, const char *name);
int qs_select_text(QSWindow *, const char *identifier, int start, int length, const char *expected);
int qs_fixed_font(QSWindow *, const char *identifier);
int qs_uses_family(QSWindow *, const char *text, const char *family);
int qs_has_focus(QSWindow *, const char *identifier);
int qs_mouse_click(QSWindow *, const char *identifier);
int qs_click_point(QSWindow *, int x, int y);
int qs_click_device(QSWindow *, int x, int y, int kind);
int qs_drag_pointer(QSWindow *, int x1, int y1, int x2, int y2, int steps);
int qs_click_named_button(QSWindow *, const char *label);
int qs_tab(QSWindow *);
int qs_mouse_button(QSWindow *, const char *identifier, int down);
#ifdef __cplusplus
}
#endif
