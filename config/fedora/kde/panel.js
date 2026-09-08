for (const existingPanel of panels()) {
    existingPanel.remove();
}

const panel = new Panel;
panel.location = "bottom";
panel.height = 68;
panel.hiding = "none";
panel.lengthMode = "fill";

const dashboardFavorites = [
    "applications:chalkboard-browser.desktop",
    "applications:chalkboard-coolmath-games.desktop",
    "applications:chalkboard-cutemaze.desktop",
    "applications:chalkboard-gcompris.desktop",
    "applications:chalkboard-kcalc.desktop",
    "applications:chalkboard-kidpix.desktop",
    "applications:chalkboard-kmines.desktop",
    "applications:chalkboard-kolourpaint.desktop",
    "applications:chalkboard-ktuberling.desktop",
    "applications:chalkboard-writer.desktop",
    "applications:chalkboard-teach-your-monster.desktop",
    "preferred://filemanager"
];

const panelLaunchers = [
    "applications:chalkboard-gcompris.desktop",
    "applications:chalkboard-kidpix.desktop",
    "applications:chalkboard-writer.desktop",
    "applications:chalkboard-teach-your-monster.desktop",
    "applications:chalkboard-coolmath-games.desktop",
    "preferred://filemanager"
];

const dashboard = panel.addWidget("org.kde.plasma.kickerdash");
dashboard.currentConfigGroup = ["General"];
dashboard.writeConfig("favoriteApps", dashboardFavorites.join(","));
dashboard.writeConfig("showRecentDocs", false);
dashboard.writeConfig("useExtraRunners", false);

const tasks = panel.addWidget("org.kde.plasma.icontasks");
tasks.currentConfigGroup = ["General"];
tasks.writeConfig("launchers", panelLaunchers.join(","));
tasks.writeConfig("iconSpacing", 2);
tasks.writeConfig("showOnlyCurrentActivity", true);
tasks.writeConfig("showOnlyCurrentDesktop", true);

panel.addWidget("org.kde.plasma.panelspacer");
panel.addWidget("org.kde.plasma.devicenotifier");
panel.addWidget("org.kde.plasma.notifications");
panel.addWidget("org.kde.plasma.bluetooth");
panel.addWidget("org.kde.plasma.volume");
panel.addWidget("org.kde.plasma.networkmanagement");
panel.addWidget("org.kde.plasma.battery");

const powerLauncher = panel.addWidget("org.kde.plasma.icon");
powerLauncher.currentConfigGroup = ["General"];
powerLauncher.writeConfig("url", "file:///home/chalkboard/.local/share/applications/chalkboard-power.desktop");
powerLauncher.writeConfig("localPath", "/home/chalkboard/.local/share/applications/chalkboard-power.desktop");

panel.addWidget("org.kde.plasma.digitalclock");
