import Foundation

enum ToolArguments {
    static func parseSearch(_ arguments: [String: JSONValue]) throws -> EventSearchRequest {
        try rejectUnknown(arguments, allowed: ["start", "end", "calendarIds", "query", "limit"])

        let start = try parseDate(arguments, key: "start", required: true)
        let end = try parseDate(arguments, key: "end", required: true)
        try validateDateRange(start: start!, end: end!)

        let calendarIDs = try parseStringArray(arguments, key: "calendarIds")
        let query = try parseOptionalString(arguments, key: "query", maxLength: 200)
        let limit = try parseOptionalInt(arguments, key: "limit", range: 1...5_000) ?? 1_000
        return EventSearchRequest(start: start!, end: end!, calendarIDs: calendarIDs, query: query, limit: limit)
    }

    static func parseCreate(_ arguments: [String: JSONValue]) throws -> CreateEventRequest {
        try rejectUnknown(arguments, allowed: ["calendarId", "title", "start", "end", "isAllDay", "location", "notes", "url"])

        let calendarID = try parseRequiredString(arguments, key: "calendarId", maxLength: 500)
        let title = try parseRequiredString(arguments, key: "title", maxLength: 500)
        let start = try parseDate(arguments, key: "start", required: true)!
        let end = try parseDate(arguments, key: "end", required: true)!
        try validateStartEnd(start: start, end: end)
        let isAllDay = try parseOptionalBool(arguments, key: "isAllDay") ?? false
        let location = try parseOptionalString(arguments, key: "location", maxLength: 500)
        let notes = try parseOptionalString(arguments, key: "notes", maxLength: 10_000)
        let url = try parseOptionalURL(arguments, key: "url")

        return CreateEventRequest(
            calendarID: calendarID,
            title: title,
            start: start,
            end: end,
            isAllDay: isAllDay,
            location: location,
            notes: notes,
            url: url
        )
    }

    static func parseUpdate(_ arguments: [String: JSONValue]) throws -> UpdateEventRequest {
        try rejectUnknown(arguments, allowed: ["eventId", "title", "start", "end", "isAllDay", "location", "notes", "url", "calendarId", "span"])

        let eventID = try parseRequiredString(arguments, key: "eventId", maxLength: 500)
        let title = try parseOptionalString(arguments, key: "title", maxLength: 500)
        let start = try parseDate(arguments, key: "start", required: false)
        let end = try parseDate(arguments, key: "end", required: false)
        if let start, let end {
            try validateStartEnd(start: start, end: end)
        }
        let isAllDay = try parseOptionalBool(arguments, key: "isAllDay")
        let locationPatch = try parseNullableString(arguments, key: "location", maxLength: 500)
        let notesPatch = try parseNullableString(arguments, key: "notes", maxLength: 10_000)
        let urlPatch = try parseNullableURL(arguments, key: "url")
        let calendarID = try parseOptionalString(arguments, key: "calendarId", maxLength: 500)
        let spanRaw = try parseOptionalString(arguments, key: "span", maxLength: 50) ?? "thisEvent"

        guard let span = UpdateEventRequest.Span(rawValue: spanRaw) else {
            throw ServerError.invalidParams("span must be one of: thisEvent, futureEvents")
        }

        if title == nil,
           start == nil,
           end == nil,
           isAllDay == nil,
           !locationPatch.wasProvided,
           !notesPatch.wasProvided,
           !urlPatch.wasProvided,
           calendarID == nil {
            throw ServerError.invalidParams("At least one mutable field must be provided for update")
        }

        return UpdateEventRequest(
            eventID: eventID,
            title: title,
            start: start,
            end: end,
            isAllDay: isAllDay,
            location: locationPatch.value,
            notes: notesPatch.value,
            url: urlPatch.value,
            calendarID: calendarID,
            span: span,
            clearLocation: locationPatch.shouldClear,
            clearNotes: notesPatch.shouldClear,
            clearURL: urlPatch.shouldClear
        )
    }

    static func parseDelete(_ arguments: [String: JSONValue]) throws -> DeleteEventRequest {
        try rejectUnknown(arguments, allowed: ["eventId", "span"])

        let eventID = try parseRequiredString(arguments, key: "eventId", maxLength: 500)
        let spanRaw = try parseOptionalString(arguments, key: "span", maxLength: 50) ?? "thisEvent"
        guard let span = UpdateEventRequest.Span(rawValue: spanRaw) else {
            throw ServerError.invalidParams("span must be one of: thisEvent, futureEvents")
        }
        return DeleteEventRequest(eventID: eventID, span: span)
    }

    private static func rejectUnknown(_ arguments: [String: JSONValue], allowed: Set<String>) throws {
        let unknown = arguments.keys.filter { !allowed.contains($0) }.sorted()
        guard unknown.isEmpty else {
            throw ServerError.invalidParams("Unknown fields: \(unknown.joined(separator: ", "))")
        }
    }

    private static func parseRequiredString(_ arguments: [String: JSONValue], key: String, maxLength: Int) throws -> String {
        guard let value = arguments[key]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            throw ServerError.invalidParams("\(key) is required")
        }
        guard value.count <= maxLength else {
            throw ServerError.invalidParams("\(key) must be at most \(maxLength) characters")
        }
        return value
    }

    private static func parseOptionalString(_ arguments: [String: JSONValue], key: String, maxLength: Int) throws -> String? {
        guard let raw = arguments[key] else { return nil }
        guard case let .string(value) = raw else {
            throw ServerError.invalidParams("\(key) must be a string")
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= maxLength else {
            throw ServerError.invalidParams("\(key) must be at most \(maxLength) characters")
        }
        return trimmed
    }

    private struct NullablePatch<Value> {
        let value: Value?
        let wasProvided: Bool
        let shouldClear: Bool
    }

    private static func parseNullableString(
        _ arguments: [String: JSONValue],
        key: String,
        maxLength: Int
    ) throws -> NullablePatch<String> {
        guard let raw = arguments[key] else {
            return NullablePatch(value: nil, wasProvided: false, shouldClear: false)
        }
        if case .null = raw {
            return NullablePatch(value: nil, wasProvided: true, shouldClear: true)
        }
        guard case let .string(value) = raw else {
            throw ServerError.invalidParams("\(key) must be a string or null")
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= maxLength else {
            throw ServerError.invalidParams("\(key) must be at most \(maxLength) characters")
        }
        return NullablePatch(value: trimmed, wasProvided: true, shouldClear: false)
    }

    private static func parseNullableURL(
        _ arguments: [String: JSONValue],
        key: String
    ) throws -> NullablePatch<URL> {
        let patch = try parseNullableString(arguments, key: key, maxLength: 2_000)
        guard let value = patch.value else {
            return NullablePatch(value: nil, wasProvided: patch.wasProvided, shouldClear: patch.shouldClear)
        }
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else {
            throw ServerError.invalidParams("\(key) must be a valid http or https URL, or null to clear it")
        }
        return NullablePatch(value: url, wasProvided: true, shouldClear: false)
    }

    private static func parseOptionalBool(_ arguments: [String: JSONValue], key: String) throws -> Bool? {
        guard let raw = arguments[key] else { return nil }
        guard let value = raw.boolValue else {
            throw ServerError.invalidParams("\(key) must be a boolean")
        }
        return value
    }

    private static func parseOptionalInt(
        _ arguments: [String: JSONValue],
        key: String,
        range: ClosedRange<Int>
    ) throws -> Int? {
        guard let raw = arguments[key] else { return nil }
        guard case let .number(number) = raw,
              number.rounded() == number,
              number >= Double(range.lowerBound),
              number <= Double(range.upperBound) else {
            throw ServerError.invalidParams("\(key) must be an integer from \(range.lowerBound) through \(range.upperBound)")
        }
        return Int(number)
    }

    private static func parseStringArray(_ arguments: [String: JSONValue], key: String) throws -> [String]? {
        guard let raw = arguments[key] else { return nil }
        guard let array = raw.arrayValue else {
            throw ServerError.invalidParams("\(key) must be an array of strings")
        }
        let strings = try array.map { item -> String in
            guard let string = item.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !string.isEmpty else {
                throw ServerError.invalidParams("\(key) must contain only non-empty strings")
            }
            return string
        }
        return strings
    }

    private static func parseOptionalURL(_ arguments: [String: JSONValue], key: String) throws -> URL? {
        guard let value = try parseOptionalString(arguments, key: key, maxLength: 2_000) else {
            return nil
        }
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            throw ServerError.invalidParams("\(key) must be a valid http or https URL")
        }
        return url
    }

    private static func parseDate(_ arguments: [String: JSONValue], key: String, required: Bool) throws -> Date? {
        guard let raw = arguments[key] else {
            if required {
                throw ServerError.invalidParams("\(key) is required")
            }
            return nil
        }
        guard let string = raw.stringValue else {
            throw ServerError.invalidParams("\(key) must be an ISO 8601 date-time string")
        }
        guard let date = DateCodec.parse(string) else {
            throw ServerError.invalidParams("\(key) must be a valid ISO 8601 date-time string with timezone")
        }
        return date
    }

    private static func validateStartEnd(start: Date, end: Date) throws {
        guard end >= start else {
            throw ServerError.invalidParams("end must be greater than or equal to start")
        }
    }

    private static func validateDateRange(start: Date, end: Date) throws {
        try validateStartEnd(start: start, end: end)
        guard end.timeIntervalSince(start) <= 366 * 24 * 60 * 60 else {
            throw ServerError.invalidParams("Date range must not exceed 366 days")
        }
    }
}

enum DateCodec {
    private static func formatter(withFractionalSeconds: Bool) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = withFractionalSeconds ? [.withInternetDateTime, .withFractionalSeconds] : [.withInternetDateTime]
        return formatter
    }

    static func parse(_ value: String) -> Date? {
        formatter(withFractionalSeconds: true).date(from: value)
            ?? formatter(withFractionalSeconds: false).date(from: value)
    }

    static func format(_ date: Date) -> String {
        formatter(withFractionalSeconds: true).string(from: date)
    }
}
