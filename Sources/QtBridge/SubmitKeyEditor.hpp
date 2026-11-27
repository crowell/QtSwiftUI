#pragma once
#include <QVariant>

// Qt asks the focused editor which Return key to display on the input method.
template<class Editor>
class SubmitKeyEditor : public Editor {
public:
    using Editor::Editor;
    const unsigned char *utf8Value(const QString &text, size_t *count) {
        utf8 = text.toUtf8();
        *count = size_t(utf8.size());
        return reinterpret_cast<const unsigned char *>(utf8.constData());
    }
    QVariant inputMethodQuery(Qt::InputMethodQuery query) const override {
        if (query == Qt::ImEnterKeyType) {
            const auto key = this->property("qsEnterKey");
            if (key.isValid()) return key;
        }
        return Editor::inputMethodQuery(query);
    }
private:
    QByteArray utf8;
};
