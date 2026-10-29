import ActivityKit
import KGCore
import KGDesign
import SwiftUI
import WidgetKit

/// The ride on the lock screen and in the Dynamic Island (plan X2, screen 14). Minutes and progress count
/// down by themselves with timer texts (X2.4); tapping opens the journey (X2.7).
struct TripLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TripActivityAttributes.self) { context in
            LockScreenView(context: context)
                .activityBackgroundTint(KGColor.surface)
                .widgetURL(URL(string: "konstanzgo://journey"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    KGLineBadge(context.attributes.line, size: .medium)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: Date.now...max(.now, context.state.arrival), countsDown: true)
                        .kgFont(.minutes).monospacedDigit().foregroundStyle(KGColor.white)
                        .frame(maxWidth: 70, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(verbatim: context.attributes.target).kgFont(.bodyStrong).foregroundStyle(KGColor.white)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Noch \(context.state.stopsLeft) Haltestellen · jetzt \(context.state.currentStop)")
                            .kgFont(.caption.weighted(KGFont.semiBold)).foregroundStyle(KGColor.white.opacity(0.8))
                        ProgressView(timerInterval: context.state.start...max(context.state.start, context.state.arrival),
                                     countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                            .tint(KGColor.coral)
                    }
                }
            } compactLeading: {
                Text(verbatim: context.attributes.line).kgFont(.badge).foregroundStyle(KGColor.lineFill)
            } compactTrailing: {
                Text(timerInterval: Date.now...max(.now, context.state.arrival), countsDown: true)
                    .monospacedDigit().frame(maxWidth: 44).foregroundStyle(KGColor.white)
            } minimal: {
                Text(verbatim: context.attributes.line).kgFont(.badge).foregroundStyle(KGColor.lineFill)
            }
            .widgetURL(URL(string: "konstanzgo://journey"))
        }
    }
}

/// Lock screen: "Sternenplatz → Universität", badge, big minutes, "Noch 4 Haltestellen", "Ankunft 14:35",
/// progress bar (X2.2).
private struct LockScreenView: View {
    let context: ActivityViewContext<TripActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                SeeriLogo(size: 32)
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: context.attributes.boarding).kgFont(.caption.weighted(KGFont.semiBold))
                        .foregroundStyle(KGColor.ink2)
                    HStack(spacing: 6) {
                        KGLineBadge(context.attributes.line, size: .small)
                        Text(verbatim: context.attributes.target).kgFont(.bodyStrong).foregroundStyle(KGColor.ink)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Text(timerInterval: Date.now...max(.now, context.state.arrival), countsDown: true)
                    .kgFont(.bigMinutes(30)).monospacedDigit().foregroundStyle(KGColor.ink)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 110, alignment: .trailing)
            }
            HStack {
                Text("Noch \(context.state.stopsLeft) Haltestellen").kgFont(.footnote).foregroundStyle(KGColor.ink2)
                Spacer()
                Text("Ankunft \(context.state.arrival, style: .time)").kgFont(.footnote).foregroundStyle(KGColor.ink2)
            }
            ProgressView(timerInterval: context.state.start...max(context.state.start, context.state.arrival),
                         countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                .tint(KGColor.coral)
        }
        .padding(16)
    }
}
