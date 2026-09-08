#!/usr/bin/env node

const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");

const weatherScript = fs.readFileSync("config/fedora/kde/weather.js", "utf8");

class Widget {
    constructor(type, panel) {
        this.type = type;
        this.panel = panel;
        this.currentConfigGroup = [];
        this.config = new Map();
    }

    get index() {
        return this.panel.items.indexOf(this);
    }

    set index(index) {
        this.panel.items.splice(this.panel.items.indexOf(this), 1);
        this.panel.items.splice(index, 0, this);
    }

    key(name) {
        return `${this.currentConfigGroup.join("/")}/${name}`;
    }

    readConfig(name, fallback) {
        return this.config.get(this.key(name)) ?? fallback;
    }

    writeConfig(name, value) {
        this.config.set(this.key(name), value);
    }

    reloadConfig() {}

    remove() {
        this.panel.items.splice(this.panel.items.indexOf(this), 1);
    }
}

class Panel {
    constructor() {
        this.items = [];
    }

    addWidget(type) {
        const widget = new Widget(type, this);
        this.items.push(widget);
        return widget;
    }

    widgets(type) {
        return type ? this.items.filter(widget => widget.type === type) : [...this.items];
    }
}

function reconcile(panel, values) {
    const context = {
        ConfigFile: class {
            readEntry(key) {
                return values[key] ?? "";
            }
        },
        knownWidgetTypes: ["org.kde.plasma.weather"],
        panels: () => [panel],
    };
    vm.runInNewContext(weatherScript, context);
}

function baselinePanel() {
    const panel = new Panel();
    panel.addWidget("org.kde.plasma.taskmanager");
    panel.addWidget("org.kde.plasma.digitalclock");
    return panel;
}

const disabledPanel = baselinePanel();
const disabledTypes = disabledPanel.items.map(widget => widget.type);
reconcile(disabledPanel, {Enabled: false});
assert.deepEqual(disabledPanel.items.map(widget => widget.type), disabledTypes);

const panel = baselinePanel();
reconcile(panel, {Enabled: true, Provider: "noaa", Location: "FIRST STATION, AA"});
assert.deepEqual(panel.items.map(widget => widget.type), [
    "org.kde.plasma.taskmanager",
    "org.kde.plasma.weather",
    "org.kde.plasma.digitalclock",
]);

reconcile(panel, {Enabled: true, Provider: "noaa", Location: "SECOND STATION, BB"});
const managed = panel.widgets("org.kde.plasma.weather");
assert.equal(managed.length, 1);
managed[0].currentConfigGroup = ["WeatherStation"];
assert.equal(managed[0].readConfig("source", ""), "noaa|weather|SECOND STATION, BB");

const unrelated = panel.addWidget("org.kde.plasma.weather");
reconcile(panel, {Enabled: false});
assert.deepEqual(panel.widgets("org.kde.plasma.weather"), [unrelated]);
