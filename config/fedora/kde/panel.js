for (const existingPanel of panels()) {
    existingPanel.remove();
}

const panel = new Panel;
panel.location = "bottom";
panel.height = 72;
panel.hiding = "none";
panel.lengthMode = "fill";

const launchers = [
    "chalkboard-gcompris.desktop",
    "chalkboard-kidpix.desktop",
    "chalkboard-kolourpaint.desktop",
    "chalkboard-writer.desktop",
    "chalkboard-teach-your-monster.desktop",
    "chalkboard-coolmath-games.desktop",
    "chalkboard-ktuberling.desktop",
    "chalkboard-cutemaze.desktop",
    "chalkboard-kmines.desktop",
    "chalkboard-kcalc.desktop",
    "chalkboard-browser.desktop"
];

for (const desktopFile of launchers) {
    const launcher = panel.addWidget("org.kde.plasma.icon");
    launcher.currentConfigGroup = ["General"];
    launcher.writeConfig("url", "file:///home/chalkboard/.local/share/applications/" + desktopFile);
    launcher.writeConfig("localPath", "/home/chalkboard/.local/share/applications/" + desktopFile);
}

panel.addWidget("org.kde.plasma.panelspacer");
panel.addWidget("org.kde.plasma.networkmanagement");
panel.addWidget("org.kde.plasma.battery");

const powerLauncher = panel.addWidget("org.kde.plasma.icon");
powerLauncher.currentConfigGroup = ["General"];
powerLauncher.writeConfig("url", "file:///home/chalkboard/.local/share/applications/chalkboard-power.desktop");
powerLauncher.writeConfig("localPath", "/home/chalkboard/.local/share/applications/chalkboard-power.desktop");

panel.addWidget("org.kde.plasma.digitalclock");
