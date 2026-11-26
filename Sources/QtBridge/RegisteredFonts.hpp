#pragma once
#include <QApplication>
#include <QRawFont>
#include <QVariant>
#include <QtEndian>

// SwiftUI accepts PostScript face names. QFont selects a family plus style.
inline void registerFontNames(QApplication &app, const QRawFont &raw, const QStringList &families) {
    if (!raw.isValid()) return;
    const auto table = raw.fontTable("name");
    if (table.size() < 6) return;
    auto word = [&](int offset) { return int(qFromBigEndian<quint16>(table.constData() + offset)); };
    const int records = word(2), strings = word(4);
    if (6 + records * 12 > table.size()) return;
    QFont face(families.value(0, raw.familyName()));
    // A directly loaded QRawFont can report the default requested weight.
    // The OpenType OS/2 table records the weight and style of this specific face.
    const auto os2 = raw.fontTable("OS/2");
    const int weight = os2.size() >= 6 ? qFromBigEndian<quint16>(os2.constData() + 4) : raw.weight();
    face.setWeight(static_cast<QFont::Weight>(qBound(1, weight, 1000)));
    const int selection = os2.size() >= 64 ? qFromBigEndian<quint16>(os2.constData() + 62) : 0;
    face.setStyle(selection & 1 ? QFont::StyleItalic : selection & 512 ? QFont::StyleOblique : raw.style());
    for (int i = 0; i < records; ++i) {
        const int offset = 6 + i * 12;
        const int platform = word(offset), id = word(offset + 6);
        if (id != 4 && id != 6) continue;
        const int start = strings + word(offset + 10), count = word(offset + 8);
        if (start + count > table.size()) continue;
        QString name;
        if (platform == 0 || platform == 3) {
            for (int j = 0; j + 1 < count; j += 2) name.append(QChar(ushort(word(start + j))));
        } else if (platform == 1 && id == 6) {
            name = QString::fromLatin1(table.constData() + start, count);
        }
        if (!name.isEmpty() && name != raw.familyName())
            app.setProperty(("qsFontFace/" + name).toUtf8().constData(), face);
    }
}

inline QFont resolveFont(QFont font, const QString &name, int weight, bool italic) {
    if (!name.isEmpty()) {
        const auto registered = qApp->property(("qsFontFace/" + name).toUtf8().constData());
        if (registered.isValid()) font = registered.value<QFont>();
        else font.setFamily(name);
    }
    if (weight >= 0) font.setWeight(static_cast<QFont::Weight>(weight));
    if (italic) font.setItalic(true);
    return font;
}
