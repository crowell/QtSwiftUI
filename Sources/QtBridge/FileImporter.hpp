#pragma once
#include <QAbstractItemView>
#include <QDialogButtonBox>
#include <QFileDialog>
#include <QFileSystemModel>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMimeDatabase>
#include <QPushButton>

// QFileDialog has native modes for files and for one directory. For mixed selections
// and multiple directories, keep its normal navigation and add a selection action.
class QSFileImporter final : public QFileDialog {
    QList<QUrl> chosen;
    QStringList patterns;
    bool onlyDirectories;

    QList<QUrl> selectedEntries() const {
        for (auto *view : findChildren<QAbstractItemView *>()) {
            if (!view->isVisible() || !view->selectionModel()) continue;
            auto *model = qobject_cast<QFileSystemModel *>(view->model());
            if (!model) continue;
            QList<QUrl> urls;
            for (const auto &index : view->selectionModel()->selectedRows(0)) {
                const auto info = model->fileInfo(index);
                if (!info.exists() || (!info.isDir() && (onlyDirectories || !QDir::match(patterns, info.fileName())))) return {};
                urls.append(QUrl::fromLocalFile(info.absoluteFilePath()));
            }
            if (!urls.isEmpty()) return urls;
        }
        return {};
    }

    static QStringList filePatterns(const QString &mimeTypes) {
        QMimeDatabase database;
        QStringList result;
        for (const auto &mime : mimeTypes.split('\n', Qt::SkipEmptyParts)) {
            if (mime == "*") return {"*"};
            if (mime.endsWith("/*")) {
                const auto prefix = mime.chopped(1);
                for (const auto &type : database.allMimeTypes())
                    if (type.name().startsWith(prefix)) result.append(type.globPatterns());
            } else {
                result.append(database.mimeTypeForName(mime).globPatterns());
            }
        }
        if (result.isEmpty()) return {"*"};
        result.removeDuplicates();
        result.sort();
        return result;
    }

public:
    QSFileImporter(QWidget *parent, const QString &mimeTypes, int directories, bool multiple)
        : QFileDialog(parent), patterns(filePatterns(mimeTypes)), onlyDirectories(directories == 1) {
        const bool extended = directories == 2 || (onlyDirectories && multiple);
        if (extended) setOption(QFileDialog::DontUseNativeDialog);
        setAcceptMode(QFileDialog::AcceptOpen);
        setWindowModality(Qt::WindowModal);
        setSupportedSchemes({"file"});
        setFileMode(onlyDirectories && !extended ? QFileDialog::Directory
                    : multiple ? QFileDialog::ExistingFiles : QFileDialog::ExistingFile);
        if (onlyDirectories) setFilter(QDir::AllDirs | QDir::NoDotAndDotDot | QDir::Drives);
        if (!onlyDirectories && patterns != QStringList{"*"})
            setNameFilter(tr("Supported files (%1)").arg(patterns.join(' ')));
        if (extended) {
            auto *buttons = findChild<QDialogButtonBox *>();
            if (buttons) {
                auto *select = buttons->addButton(tr("Import Selection"), QDialogButtonBox::ActionRole);
                select->setObjectName("qsImportSelection");
                connect(select, &QPushButton::clicked, this, [this] {
                    auto urls = selectedEntries();
                    if (urls.isEmpty()) return;
                    chosen = urls;
                    QDialog::accept();
                });
            }
        }
    }
    void restoreConfiguration(const char *state, const char *defaultDirectory) {
        QString folder = QString::fromUtf8(defaultDirectory);
        if (state) {
            const auto settings = QJsonDocument::fromJson(QByteArray(state)).object();
            restoreState(QByteArray::fromBase64(settings.value("layout").toString().toLatin1()));
            restoreGeometry(QByteArray::fromBase64(settings.value("geometry").toString().toLatin1()));
            const auto saved = settings.value("directory").toString();
            if (QDir::isAbsolutePath(saved) && QFileInfo(saved).isDir()) folder = saved;
        }
        if (!folder.isEmpty()) setDirectory(folder);
    }

    QByteArray configuration() const {
        const QJsonObject settings{
            {"directory", directory().absolutePath()},
            {"layout", QString::fromLatin1(saveState().toBase64())},
            {"geometry", QString::fromLatin1(saveGeometry().toBase64())}
        };
        return QJsonDocument(settings).toJson(QJsonDocument::Compact);
    }

    void accept() override {
        for (const auto &url : selectedUrls()) {
            if (!url.isLocalFile()) return;
            const QFileInfo info(url.toLocalFile());
            if (!info.isDir() && (onlyDirectories || !QDir::match(patterns, info.fileName()))) return;
        }
        QFileDialog::accept();
    }
    QList<QUrl> importURLs() const { return chosen.isEmpty() ? selectedUrls() : chosen; }
};
