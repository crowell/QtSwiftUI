#include "ClipboardCommands.hpp"
#include <QApplication>
#include <QClipboard>
#include <QKeyEvent>
#include <QMimeData>
#include <QUrl>
#include <memory>
#include <vector>

namespace {
class ClipboardItems final : public QMimeData {
public:
    std::vector<std::unique_ptr<QMimeData>> items;
    void publishFormats() {
        // Qt exposes a single MIME offer to other desktop apps. Keep all native
        // alternatives for one item, and join multi-item text and URL lists.
        QStringList text;
        QList<QUrl> urls;
        for (const auto &item : items) {
            if (item->hasText()) text.append(item->text());
            urls.append(item->urls());
            for (const auto &format : item->formats())
                if (!hasFormat(format)) setData(format, item->data(format));
        }
        if (text.size() > 1) setText(text.join('\n'));
        if (!urls.isEmpty()) setUrls(urls);
    }
};
int commandFor(QKeyEvent *key) {
    if (key->matches(QKeySequence::Copy)) return QSCopyItems;
    if (key->matches(QKeySequence::Cut)) return QSCutItems;
    if (key->matches(QKeySequence::Paste)) return QSPasteItems;
    return -1;
}
}
void qs_clipboard_scope(QSWidget item, int command) {
    static_cast<QWidget *>(item)->setProperty("qsClipboardCommand", command);
}
uint64_t qs_clipboard_revision() {
    static uint64_t revision = 0;
    static const auto connection = QObject::connect(QApplication::clipboard(), &QClipboard::dataChanged, [] { ++revision; });
    return revision;
}
void *qs_clipboard_contents() { return const_cast<QMimeData *>(QApplication::clipboard()->mimeData()); }
void *qs_clipboard_add_item(void *clipboard) {
    auto *items = static_cast<ClipboardItems *>(clipboard);
    return items->items.emplace_back(std::make_unique<QMimeData>()).get();
}
int qs_clipboard_item_count(void *clipboard) {
    if (!clipboard) return 0;
    if (auto *items = dynamic_cast<ClipboardItems *>(static_cast<QMimeData *>(clipboard))) return int(items->items.size());
    return 1;
}
void *qs_clipboard_item(void *clipboard, int index) {
    if (index < 0 || index >= qs_clipboard_item_count(clipboard)) return nullptr;
    if (auto *items = dynamic_cast<ClipboardItems *>(static_cast<QMimeData *>(clipboard))) return items->items[index].get();
    return clipboard;
}
bool handleClipboardKey(QWidget *focused, QEvent *event, QSTransferHandler handler, void *context) {
    if (!handler || !focused || (event->type() != QEvent::KeyPress && event->type() != QEvent::ShortcutOverride)) return false;
    const int command = commandFor(static_cast<QKeyEvent *>(event));
    if (command < 0) return false;
    for (auto *w = focused; w && !w->isWindow(); w = w->parentWidget()) {
        const auto scope = w->property("qsClipboardCommand");
        if (!scope.isValid() || !w->isEnabled() || scope.toInt() != command) continue;
        if (event->type() == QEvent::ShortcutOverride) { event->accept(); return true; }
        auto *clipboard = QApplication::clipboard();
        const int id = w->property("swiftId").toInt();
        if (command == QSPasteItems) {
            auto *mime = const_cast<QMimeData *>(clipboard->mimeData());
            if (!mime || !handler(context, id, QSPasteItems, mime, 0, 0)) continue;
        } else {
            auto items = std::make_unique<ClipboardItems>();
            if (!handler(context, id, QSTransferPhase(command), items.get(), 0, 0)) continue;
            if (!items->items.empty()) {
                items->publishFormats();
                clipboard->setMimeData(items.release());
            }
        }
        event->accept();
        return true;
    }
    return false;
}
