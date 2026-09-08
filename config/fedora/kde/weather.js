const config = new ConfigFile("/etc/chalkboard/weather.conf", "Weather");
const enabled = String(config.readEntry("Enabled")).toLowerCase() === "true";
const provider = String(config.readEntry("Provider"));
const location = String(config.readEntry("Location"));
const weatherType = "org.kde.plasma.weather";

function managedWeatherWidgets() {
    const managed = [];
    for (const panel of panels()) {
        for (const widget of panel.widgets(weatherType)) {
            widget.currentConfigGroup = ["Chalkboard"];
            if (String(widget.readConfig("Managed", "false")).toLowerCase() === "true") {
                managed.push(widget);
            }
        }
    }
    return managed;
}

const managed = managedWeatherWidgets();
if (!enabled) {
    for (const widget of managed) {
        widget.remove();
    }
} else {
    if (provider !== "noaa" || !location || location.includes("|")) {
        throw new Error("invalid Chalkboard weather configuration");
    }
    if (!knownWidgetTypes.includes(weatherType)) {
        throw new Error("the packaged KDE weather widget is not installed");
    }

    let weather = managed.shift();
    for (const duplicate of managed) {
        duplicate.remove();
    }

    if (!weather) {
        const baselinePanels = panels().filter(panel =>
            panel.widgets("org.kde.plasma.taskmanager").length === 1
            && panel.widgets("org.kde.plasma.digitalclock").length === 1
        );
        if (baselinePanels.length !== 1) {
            throw new Error("could not identify the Chalkboard baseline panel");
        }

        const panel = baselinePanels[0];
        const clock = panel.widgets("org.kde.plasma.digitalclock")[0];
        weather = panel.addWidget(weatherType);
        // Tag immediately after creation so a later failure never leaves an
        // untagged widget that the disabled path cannot find or remove.
        weather.currentConfigGroup = ["Chalkboard"];
        weather.writeConfig("Managed", true);
        weather.index = clock.index;
    }

    weather.currentConfigGroup = ["Chalkboard"];
    weather.writeConfig("Managed", true);
    weather.currentConfigGroup = ["WeatherStation"];
    weather.writeConfig("source", provider + "|weather|" + location);
    weather.currentConfigGroup = ["Appearance"];
    weather.writeConfig("showTemperatureInCompactMode", true);
    weather.reloadConfig();
}
