import Foundation

enum RFC3339 {
    /// Reads the RFC 3339 text that Go writes for a time value.
    /// It has an optional fraction of up to nine digits, and `Z` or an offset.
    static func date(from text: String) -> Date? {
        var text = text
        return text.withUTF8 { date(from: $0) }
    }

    private static func date(from bytes: UnsafeBufferPointer<UInt8>) -> Date? {
        func number(_ start: Int, _ count: Int) -> Int? {
            var value = 0
            for index in start..<start + count {
                let digit = Int(bytes[index]) - 48
                guard (0...9).contains(digit) else { return nil }
                value = value * 10 + digit
            }
            return value
        }

        // 2026-11-17T12:30:45
        guard bytes.count >= 20, bytes[4] == 45, bytes[7] == 45, bytes[10] == 84, bytes[13] == 58, bytes[16] == 58,
            let year = number(0, 4), let month = number(5, 2), let day = number(8, 2),
            let hour = number(11, 2), let minute = number(14, 2), let second = number(17, 2),
            (1...12).contains(month), (1...31).contains(day), hour < 24, minute < 60, second < 60
        else { return nil }

        var index = 19
        var fraction = 0.0
        if bytes[index] == 46 {
            index += 1
            var digits = 0
            var value = 0
            while index < bytes.count, (48...57).contains(bytes[index]) {
                // Nine digits are a nanosecond; later ones change nothing a Double can keep.
                if digits < 9 {
                    value = value * 10 + Int(bytes[index]) - 48
                    digits += 1
                }
                index += 1
            }
            guard digits > 0 else { return nil }
            fraction =
                Double(value)
                / [1, 10, 100, 1_000, 10_000, 100_000, 1_000_000, 10_000_000, 100_000_000, 1_000_000_000][digits]
        }

        // Z, or +hh:mm and -hh:mm.
        var offset = 0
        if index == bytes.count - 1, bytes[index] == 90 {
            index += 1
        } else if index == bytes.count - 6, bytes[index] == 43 || bytes[index] == 45, bytes[index + 3] == 58,
            let offsetHour = number(index + 1, 2), let offsetMinute = number(index + 4, 2)
        {
            offset = (offsetHour * 3600 + offsetMinute * 60) * (bytes[index] == 45 ? -1 : 1)
            index = bytes.count
        }
        guard index == bytes.count else { return nil }

        // Days since 1970-01-01 by the proleptic Gregorian calendar.
        let shifted = month <= 2 ? year - 1 : year
        let era = shifted / 400
        let yearOfEra = shifted - era * 400
        let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        let days = era * 146_097 + dayOfEra - 719_468
        let seconds = days * 86_400 + hour * 3600 + minute * 60 + second - offset
        return Date(timeIntervalSince1970: Double(seconds) + fraction)
    }
}
