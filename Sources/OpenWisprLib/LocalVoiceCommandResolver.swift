import Foundation

public enum LocalVoiceCommandResolver {
    public static func resolve(
        rawCommand: String?,
        executablePath: String
    ) -> String? {
        if let rawCommand, rawCommand.hasPrefix("-psn_") {
            return "start"
        }
        if rawCommand == nil,
           executablePath.contains(".app/Contents/MacOS/") {
            return "start"
        }
        return rawCommand
    }
}
