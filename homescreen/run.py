#!/usr/bin/env python3
"""Minimal PySide6 launcher for the home screen prototype.

No application logic lives here: everything is in QML/JS so it ports to
Plasma Bigscreen unchanged. This file only creates the engine and loads main.qml.
"""
import os
import sys
from pathlib import Path

from PySide6.QtCore import QUrl
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine

# QML's XMLHttpRequest needs this to read the local config/*.json files.
os.environ.setdefault("QML_XHR_ALLOW_FILE_READ", "1")
# Fedora's /usr/share/qt6/qtlogging.ini sets *.debug=false, which hides console.log.
os.environ.setdefault("QT_LOGGING_RULES", "qml.debug=true;js.debug=true")
os.environ.setdefault("QT_FORCE_STDERR_LOGGING", "1")


def main() -> int:
    app = QGuiApplication(sys.argv)
    app.setApplicationName("tv-homescreen")

    engine = QQmlApplicationEngine()
    engine.setOutputWarningsToStandardError(False)
    engine.warnings.connect(
        lambda warnings: [print(f"QML error: {w.toString()}", file=sys.stderr, flush=True) for w in warnings]
    )
    engine.load(QUrl.fromLocalFile(str(Path(__file__).resolve().parent / "main.qml")))
    if not engine.rootObjects():
        print("error: failed to load main.qml", file=sys.stderr)
        return 1
    return app.exec()


if __name__ == "__main__":
    sys.exit(main())
