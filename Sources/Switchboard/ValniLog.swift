import os.log

public enum ValniLog {
    public static let routing   = Logger(subsystem: "com.benovi.valni", category: "routing")
    public static let inference = Logger(subsystem: "com.benovi.valni", category: "inference")
    public static let agent     = Logger(subsystem: "com.benovi.valni", category: "agent")
    public static let tools     = Logger(subsystem: "com.benovi.valni", category: "tools")
    public static let viewModel = Logger(subsystem: "com.benovi.valni", category: "viewModel")
    public static let download  = Logger(subsystem: "com.benovi.valni", category: "download")
    public static let models    = Logger(subsystem: "com.benovi.valni", category: "models")
}
