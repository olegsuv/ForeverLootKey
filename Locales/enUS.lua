local _, ns = ...

ns.L = {
    PREFIX = "|cff33ff99Forever LootKey|r: ",
    APPLIED = "set up: auto loot on, nearest corpse/object becomes your interact target (%d/%d settings applied). Bind a key to \"Interact with Target\".",
    RESTORED = "your previous settings are restored. You can now disable the addon.",
    NOTHING_TO_RESTORE = "nothing to restore, the addon has not changed your settings.",
    RANGE_SET = "interact range set to %d yards.",
    RANGE_BAD = "range must be a number from %d to %d.",
    ICON_SET = "icon size set to %d.",
    ICON_BAD = "icon size must be a number from %d to %d.",
    WHO = "interact target: %s | mode %s, range %s, auto loot %s",
    NONE = "none",
    CORPSE = " (corpse)",
    NOT_SUPPORTED = "not supported by this client",
    ON = "on",
    OFF = "off",
    HELP = {
        "/lootkey on - apply the settings (done automatically on first login)",
        "/lootkey off - restore your previous settings (run before uninstalling)",
        "/lootkey range <%d-%d> - interact range in yards (default %d)",
        "/lootkey icon <%d-%d> - size of the icon over the target (default %d)",
        "/lootkey who - show what the interact key would use right now",
    },
}
