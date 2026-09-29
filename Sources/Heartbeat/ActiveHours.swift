import Foundation

struct ActiveHours {
    let startHour: Int
    let startMinute: Int
    let endHour: Int
    let endMinute: Int

    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        guard let hour = components.hour, let minute = components.minute else { return false }
        let minutesNow = hour * 60 + minute
        let startMinutes = startHour * 60 + startMinute
        let endMinutes = endHour * 60 + endMinute
        return minutesNow >= startMinutes && minutesNow < endMinutes
    }
}
