import Foundation

let iterations = 1000
let date = Date()
let calendar = Calendar.current
let timeFormatter = DateFormatter()
timeFormatter.timeStyle = .short
timeFormatter.dateStyle = .none

let fullFormatter = DateFormatter()
fullFormatter.dateStyle = .short
fullFormatter.timeStyle = .short

let start1 = Date()
for _ in 0..<iterations {
    _ = calendar.dateComponents([.year, .month, .day, .weekday], from: date)
    _ = calendar.isDateInYesterday(date)
    _ = calendar.isDateInToday(date)
    _ = timeFormatter.string(from: date)
    _ = fullFormatter.string(from: date)
}
let end1 = Date()
print("Expensive operations took: \(end1.timeIntervalSince(start1)) seconds")

let start2 = Date()
for _ in 0..<iterations {
    // string match only
    _ = "hello world".localizedCaseInsensitiveContains("world")
}
let end2 = Date()
print("String match only took: \(end2.timeIntervalSince(start2)) seconds")
