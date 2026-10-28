import SwiftUI

/// One wheel column (screen 19): rows 30 pt high, five visible, snapping. The middle row is 20 Bold black,
/// its neighbours 17 grey, the outer ones 15 light grey. Swiping or VoiceOver's adjust gestures change it,
/// with a selection tick.
public struct KGWheel<Value: Hashable>: View {
    @Binding var selection: Value
    let values: [Value]
    let label: (Value) -> String
    let accessibilityTitle: Text
    @State private var position: Value?

    public static var rowHeight: CGFloat { 30 }

    public init(selection: Binding<Value>, values: [Value], accessibilityTitle: Text,
                label: @escaping (Value) -> String) {
        _selection = selection
        self.values = values
        self.label = label
        self.accessibilityTitle = accessibilityTitle
    }

    public var body: some View {
        let row = Self.rowHeight
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(values, id: \.self) { value in
                    let distance = distanceFromSelection(value)
                    Text(verbatim: label(value))
                        .kgFont(style(distance))
                        .monospacedDigit()
                        .foregroundStyle(distance == 0 ? KGColor.ink : distance == 1 ? KGColor.ink2 : KGColor.ink4)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(maxWidth: .infinity, minHeight: row, maxHeight: row)
                        .contentShape(.rect)
                        .onTapGesture { withAnimation(KGMotion.slide) { position = value } }
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $position, anchor: .center)
        .contentMargins(.vertical, row * 2, for: .scrollContent)
        .frame(height: row * 5)
        .onAppear { position = selection }
        .onChange(of: position) { _, new in
            if let new, new != selection { selection = new }
        }
        .onChange(of: selection) { _, new in
            if position != new { withAnimation(KGMotion.slide) { position = new } }
        }
        .sensoryFeedback(KGHaptic.selection, trigger: selection)
        .accessibilityElement()
        .accessibilityLabel(accessibilityTitle)
        .accessibilityValue(Text(verbatim: label(selection)))
        .accessibilityAdjustableAction { direction in
            guard let index = values.firstIndex(of: selection) else { return }
            switch direction {
            case .increment: if index + 1 < values.count { selection = values[index + 1] }
            case .decrement: if index > 0 { selection = values[index - 1] }
            @unknown default: break
            }
        }
    }

    private func distanceFromSelection(_ value: Value) -> Int {
        guard let center = values.firstIndex(of: position ?? selection),
              let index = values.firstIndex(of: value) else { return 2 }
        return abs(index - center)
    }

    private func style(_ distance: Int) -> KGTextStyle {
        switch distance {
        case 0: .bodyStrong.sized(20)
        case 1: .bodyMedium.weighted(KGFont.regular)
        default: .callout.weighted(KGFont.regular)
        }
    }
}

/// Day, hour and 5-minute wheels side by side over one grey selection band (B31, screen 19). The day column
/// shows "Heute" for today and "Do 29. Okt." for the others.
public struct KGTimeWheel: View {
    @Binding var date: Date
    let today: Date
    let days: Int
    let calendar: Calendar

    /// `days` days starting `today` minus two (the design shows two days back for context; past times are
    /// the screen's job to refuse).
    public init(date: Binding<Date>, today: Date, days: Int = 14, calendar: Calendar = .kgKonstanz) {
        _date = date
        self.today = today
        self.days = days
        self.calendar = calendar
    }

    public var body: some View {
        let row = KGWheel<Int>.rowHeight
        HStack(spacing: 0) {
            KGWheel(selection: dayBinding, values: Array(-2..<days), accessibilityTitle: Text("Tag", bundle: .module)) {
                dayLabel($0)
            }
            .frame(maxWidth: .infinity)
            .layoutPriority(2)
            KGWheel(selection: hourBinding, values: Array(0..<24),
                    accessibilityTitle: Text("Stunde", bundle: .module)) {
                String(format: "%02d", $0)
            }
            .frame(maxWidth: .infinity)
            KGWheel(selection: minuteBinding, values: Array(stride(from: 0, to: 60, by: 5)),
                    accessibilityTitle: Text("Minute", bundle: .module)) {
                String(format: "%02d", $0)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, KGSpace.small)
        .background {
            RoundedRectangle(cornerRadius: KGRadius.compact, style: .continuous)
                .fill(KGColor.pressed)
                .frame(height: row + 6)
        }
    }

    private var startOfToday: Date { calendar.startOfDay(for: today) }

    /// The chosen moment as wheel positions: days from today, hour, minute rounded down to 5.
    private struct Parts {
        var day: Int
        var hour: Int
        var minute: Int
    }

    private var parts: Parts {
        let day = calendar.dateComponents([.day], from: startOfToday, to: calendar.startOfDay(for: date)).day ?? 0
        let time = calendar.dateComponents([.hour, .minute], from: date)
        return Parts(day: day, hour: time.hour ?? 0, minute: ((time.minute ?? 0) / 5) * 5)
    }

    private func set(day: Int? = nil, hour: Int? = nil, minute: Int? = nil) {
        let current = parts
        guard let base = calendar.date(byAdding: .day, value: day ?? current.day, to: startOfToday),
              let result = calendar.date(bySettingHour: hour ?? current.hour, minute: minute ?? current.minute,
                                         second: 0, of: base) else { return }
        date = result
    }

    private var dayBinding: Binding<Int> { Binding { parts.day } set: { set(day: $0) } }
    private var hourBinding: Binding<Int> { Binding { parts.hour } set: { set(hour: $0) } }
    private var minuteBinding: Binding<Int> { Binding { parts.minute } set: { set(minute: $0) } }

    private func dayLabel(_ offset: Int) -> String {
        if offset == 0 { return String(localized: "Heute", bundle: .module) }
        guard let day = calendar.date(byAdding: .day, value: offset, to: startOfToday) else { return "" }
        return KGStrings.shortDay(day, calendar: calendar)
    }
}

extension Calendar {
    /// Gregorian calendar in Konstanz time, Monday first.
    public static var kgKonstanz: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current
        calendar.firstWeekday = 2
        return calendar
    }
}

extension KGStrings {
    /// "Do 29. Okt." in German, "Thu 29 Oct" in English.
    public static func shortDay(_ date: Date, calendar: Calendar = .kgKonstanz, locale: Locale = .current) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .omitted, locale: locale, calendar: calendar,
                                     timeZone: calendar.timeZone)
        style = style.weekday(.abbreviated).day().month(.abbreviated)
        return date.formatted(style).replacingOccurrences(of: ",", with: "")
    }
}

#Preview("Time wheel") {
    @Previewable @State var date = Date(timeIntervalSinceReferenceDate: 815_000_000)
    KGTimeWheel(date: $date, today: Date(timeIntervalSinceReferenceDate: 815_000_000))
        .padding()
}
