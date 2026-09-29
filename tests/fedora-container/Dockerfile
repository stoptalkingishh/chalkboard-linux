# Fedora 43 environment for the container integration tests.
#
# This image approximates the provisioned child desktop's *package* state so the
# curation and verification logic can be exercised against a real Fedora desktop
# file database. It is not, and cannot be, a running Plasma session: there is no
# display server, no systemd running as PID 1, no D-Bus, and therefore no Plasma
# Shell, no SDDM autologin, and no KWin. See README.md for exactly what this does
# and does not establish.
FROM fedora:43

# Toolchain first, so the expensive KDE install sits in a later layer that stays
# cached when only the test scripts change.
RUN dnf -y install \
      ShellCheck \
      desktop-file-utils \
      gawk \
      nodejs \
      policycoreutils \
      procps-ng \
      python3 \
      shadow-utils \
      systemd \
      util-linux \
    && dnf clean all

# plasma-desktop is the metapackage that brings the system tools curation exists
# to hide: konsole, kate, kwrite, dolphin, discover, systemsettings, okular, ark.
# Without it the container's application set is a fraction of the real device's
# (measured: 38 .desktop files instead of ~86) and every denylist assertion
# becomes far weaker.
#
# The rest mirror the child-facing applications deploy.sh installs.
RUN dnf -y install \
      bluedevil \
      cage \
      gcompris-qt \
      kcalc \
      kdeplasma-addons \
      kmail \
      kmines \
      kolourpaint \
      konsole \
      ksshaskpass \
      ktuberling \
      libreoffice-writer \
      plasma-desktop \
      plasma-keyboard \
      plasma-nm \
      plasma-pa \
      plasma-systemsettings \
      sddm \
    && dnf clean all

WORKDIR /repo
CMD ["bash", "tests/fedora-container/run.sh"]
