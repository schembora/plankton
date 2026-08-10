//
//  PlaybackTimeline.swift
//  Plankton
//
//  Where playback is, and where it can be moved to.
//

import SwiftUI

/// The bottom row of the player.
///
/// This is where live and recorded playback actually differ: one has a position
/// you can move to and the other has only a present moment. Keeping that in a
/// view of its own leaves the chrome around it — visibility, transport, the
/// track pickers — with nothing to branch on, and gives each side somewhere to
/// grow without crowding the other.
struct PlaybackTimeline: View {

    @Bindable var session: PlaybackSession

    /// Fires as a drag begins and ends. The timeline owns what scrubbing means;
    /// whoever contains it owns whether the controls should still be showing.
    let onScrubbingChanged: (Bool) -> Void

    var body: some View {
        if session.isLive {
            liveMarker
        } else {
            scrubber
        }
    }

    /// Stands in for the timeline on a live channel: says where you are rather
    /// than offering a position to move to, which is the honest thing to show
    /// when there is nowhere to move.
    private var liveMarker: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)

            Text("LIVE")
                .font(.caption.weight(.semibold))

            Spacer(minLength: 0)
        }
        .foregroundStyle(.secondary)
    }

    private var scrubber: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(
                    // The engine's clock can overshoot the reported duration by
                    // a frame or two at the end of a file; the slider must not
                    // be handed a value outside its own range.
                    get: { min(session.position, session.duration ?? 1) },
                    set: { session.scrub(to: $0) }
                ),
                // A track needs a positive range even before the duration is
                // known, or the slider renders as a dead line.
                in: 0...(session.duration ?? 1),
                onEditingChanged: scrubbingChanged
            )
            .disabled(session.duration == nil)

            HStack {
                Text(Self.timeText(session.position))
                Spacer()
                if let duration = session.duration {
                    Text("-" + Self.timeText(duration - session.position))
                }
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .tint(.white)
    }

    private func scrubbingChanged(_ isScrubbing: Bool) {
        session.isScrubbing = isScrubbing

        // Seeking on release rather than throughout: engines stutter when asked
        // to move on every frame of a drag, for a preview nobody watches.
        if !isScrubbing {
            session.seek(to: session.position)
        }
        onScrubbingChanged(isScrubbing)
    }

    /// e.g. "1:04:12", or "4:07" for anything under an hour.
    static func timeText(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }

        let total = Int(seconds.rounded())
        let (hours, minutes, remainder) = (total / 3600, (total % 3600) / 60, total % 60)

        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, remainder)
            : String(format: "%d:%02d", minutes, remainder)
    }
}
