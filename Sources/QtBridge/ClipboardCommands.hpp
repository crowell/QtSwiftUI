#pragma once
#include "QtBridge.h"
#include <QEvent>
#include <QWidget>

bool handleClipboardKey(QWidget *focused, QEvent *event, QSTransferHandler handler, void *context);
