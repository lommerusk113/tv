# Headless dev/test environment for the home screen prototype.
# Same Qt as the Bazzite laptop (Fedora 44, PySide6 6.11). Renders into Xvfb with Mesa llvmpipe,
# so the screenshot + key-press test loop works without a GPU or a real display.
# Second dnf line: Plasma Bigscreen + plasmoidviewer (and the QML modules its home screen imports) for
# scripts/bigscreen-start.sh, which runs our home screen inside the real Bigscreen containment; x11vnc for scripts/vnc.sh.
FROM registry.fedoraproject.org/fedora:44

RUN dnf -y install --setopt=install_weak_deps=False \
        python3-pyside6 \
        qt6-qtbase-gui qt6-qtdeclarative \
        mesa-dri-drivers mesa-libGL mesa-libEGL \
        xorg-x11-server-Xvfb xdotool ImageMagick \
        google-noto-sans-fonts abattis-cantarell-fonts dejavu-sans-fonts \
        qt6-qtsvg \
        procps-ng git tzdata \
    && dnf -y install --setopt=install_weak_deps=False \
        plasma-bigscreen plasma-sdk plasma-milou kdeconnectd plasma-nm plasma-pa openbox dbus-x11 x11vnc \
    && dnf clean all

ENV TZ=Europe/Oslo \
    DISPLAY=:99 \
    QT_QPA_PLATFORM=xcb \
    LIBGL_ALWAYS_SOFTWARE=1

WORKDIR /work
CMD ["bash"]
