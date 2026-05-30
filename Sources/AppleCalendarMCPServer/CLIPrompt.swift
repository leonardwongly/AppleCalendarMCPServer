import Foundation

struct CLIPrompt {
    static func selectCalendar(from calendars: [CalendarSummary]) -> CalendarSummary? {
        if calendars.isEmpty {
            print("❌ No calendars available")
            return nil
        }

        if calendars.count == 1 {
            return calendars[0]
        }

        print("\nAvailable calendars:")
        for (index, calendar) in calendars.enumerated() {
            let writable = calendar.allowsContentModifications ? "✓" : "✗"
            print("  \(index + 1)) \(calendar.title) [\(writable) writable]")
        }

        while true {
            print("Select calendar (1-\(calendars.count)): ", terminator: "")
            fflush(stdout)
            
            if let input = readLine(), let index = Int(input), index > 0 && index <= calendars.count {
                return calendars[index - 1]
            }
            print("Invalid selection. Try again.")
        }
    }

    static func getText(prompt: String, defaultValue: String? = nil) -> String? {
        print("\(prompt)", terminator: defaultValue != nil ? " [\(defaultValue!)]: " : ": ")
        fflush(stdout)

        if let input = readLine(), !input.trimmingCharacters(in: .whitespaces).isEmpty {
            return input
        }
        return defaultValue
    }

    static func getDate(prompt: String) -> Date? {
        while true {
            print("\(prompt) (YYYY-MM-DD HH:MM): ", terminator: "")
            fflush(stdout)

            guard let input = readLine() else { return nil }

            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"

            if let date = dateFormatter.date(from: input) {
                return date
            }

            print("Invalid format. Please use YYYY-MM-DD HH:MM")
        }
    }

    static func getBoolean(prompt: String, defaultValue: Bool = false) -> Bool {
        let defaultStr = defaultValue ? "Y/n" : "y/N"
        print("\(prompt) [\(defaultStr)]: ", terminator: "")
        fflush(stdout)

        if let input = readLine() {
            let trimmed = input.trimmingCharacters(in: .whitespaces).lowercased()
            if trimmed == "y" || trimmed == "yes" {
                return true
            } else if trimmed == "n" || trimmed == "no" {
                return false
            }
        }
        return defaultValue
    }

    static func confirmAction(_ message: String) -> Bool {
        print("\n\(message)")
        return getBoolean(prompt: "Continue?", defaultValue: false)
    }
}
