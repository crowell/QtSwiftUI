#pragma once
#include <QVariant>

// Qt asks the focused editor which Return key to display on the input method.
template<class Editor>
class SubmitKeyEditor : public Editor {
public:
    using Editor::Editor;
    QVariant inputMethodQuery(Qt::InputMethodQuery query) const override {
        if (query == Qt::ImEnterKeyType) {
            const auto key = this->property("qsEnterKey");
            if (key.isValid()) return key;
        }
        return Editor::inputMethodQuery(query);
    }
};
