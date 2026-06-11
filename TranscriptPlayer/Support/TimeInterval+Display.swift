import Foundation

extension TimeInterval {
    /// Formato di visualizzazione del player: "m:ss", o "h:mm:ss" oltre l'ora.
    var playerDisplayString: String {
        let value = max(0, Int(rounded(.down)))
        let hours = value / 3_600
        let minutes = (value % 3_600) / 60
        let seconds = value % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
