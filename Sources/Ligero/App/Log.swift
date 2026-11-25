import os

/// os.Logger with the subsystem from SPEC §3. Read with:
/// `log stream --predicate 'subsystem == "app.allinone"'`
enum Log {
    static let subsystem = "app.allinone"
    static let app = Logger(subsystem: subsystem, category: "app")
    static let hotKeys = Logger(subsystem: subsystem, category: "hotkeys")
    static let permissions = Logger(subsystem: subsystem, category: "permissions")
    static let modules = Logger(subsystem: subsystem, category: "modules")
    static let snap = Logger(subsystem: subsystem, category: "snap")
    static let scroll = Logger(subsystem: subsystem, category: "scroll")
}
