import SwiftUI


// MARK: - Reusable Loading View

/// Consistent loading state used across all views
struct LoadingStateView: View {
    var message: String = "Loading..."
    var compact: Bool = false

    var body: some View {
        if compact {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.regular)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Reusable Empty State View

/// Consistent empty state used across all views
struct EmptyStateView: View {
    var icon: String
    var title: String
    var message: String
    var actionLabel: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .frame(maxWidth: 300)
            }

            if let actionLabel, let action {
                Button(actionLabel, action: action)
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Status Badge

/// Consistent status badge (Online, Active, Stopped, etc.)
struct StatusBadge: View {
    var label: String
    var color: Color

    var body: some View {
        Text(label)
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(Capsule())
            .accessibilityLabel("Status: \(label)")
    }
}



// MARK: - Toast / Action Feedback

/// Observable toast state that manages its own lifecycle.
/// Drop into any view with `@State private var toast = ToastState()`.
/// Then call `toast.show(...)` and display with `ToastBanner(toast: toast)`.
@Observable
final class ToastState {
    var message: String = ""
    var isError: Bool = false
    var isVisible: Bool = false

    private var dismissTask: Task<Void, Never>?

    /// Show a success or error message. Auto-dismisses after `duration` seconds.
    @MainActor
    func show(_ message: String, isError: Bool = false, duration: Double = 4) {
        dismissTask?.cancel()
        self.message = message
        self.isError = isError
        withAnimation(.spring(duration: 0.3)) { isVisible = true }
        dismissTask = Task {
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(duration: 0.3)) { isVisible = false }
        }
    }

    /// Dismiss immediately.
    @MainActor
    func dismiss() {
        dismissTask?.cancel()
        withAnimation(.spring(duration: 0.3)) { isVisible = false }
    }
}

/// Inline result banner — place anywhere in your view hierarchy.
/// Renders only when toast is visible; animates in/out automatically.
///
/// Usage:
/// ```swift
/// @State private var toast = ToastState()
///
/// var body: some View {
///     VStack {
///         // ... content ...
///         ToastBanner(toast: toast)
///     }
/// }
/// ```
struct ToastBanner: View {
    var toast: ToastState
    var style: ToastBannerStyle = .inline

    enum ToastBannerStyle {
        case inline   // Appears in-flow inside a ScrollView / VStack
        case overlay  // Positioned at the bottom of the screen
    }

    var body: some View {
        if toast.isVisible {
            HStack(spacing: 8) {
                Image(systemName: toast.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.callout.bold())
                Text(toast.message)
                    .font(.callout)
                    .lineLimit(2)
                Spacer()
                Button {
                    toast.dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2.bold())
                        .foregroundStyle(toast.isError ? Color.red : Color.green)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
            .foregroundStyle(toast.isError ? Color.red : Color.green)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(toast.isError ? Color.red.opacity(0.12) : Color.green.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        (toast.isError ? Color.red : Color.green).opacity(0.25),
                        lineWidth: 1
                    )
            )
            .transition(.move(edge: style == .overlay ? .bottom : .top).combined(with: .opacity))
        }
    }
}

/// View modifier to overlay a toast at the bottom of a view.
extension View {
    func toastOverlay(_ toast: ToastState) -> some View {
        self.overlay(alignment: .bottom) {
            ToastBanner(toast: toast, style: .overlay)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
                .allowsHitTesting(toast.isVisible)
                .animation(.spring(duration: 0.35), value: toast.isVisible)
        }
    }
}



// MARK: - Blocking Progress Overlay

/// A full-screen blocking overlay that prevents all user interaction while
/// an operation is in progress. Uses native macOS `.ultraThinMaterial` and
/// semantic colors so it looks correct in both Light and Dark mode.
///
/// Usage:
/// ```swift
/// .blockingOverlay(isPresented: $isBusy, message: "Deleting agent…")
/// ```
struct BlockingProgressOverlay: View {
    var message: String

    var body: some View {
        ZStack {
            // Scrim — system-aware dimming
            Color(nsColor: .black).opacity(0.25)
                .ignoresSafeArea()

            // Centered pill
            VStack(spacing: 10) {
                ProgressView()
                    .controlSize(.regular)
                Text(message)
                    .font(.system(.body, weight: .medium))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        }
    }
}

extension View {
    /// Presents a full-window blocking progress indicator.
    /// While visible the entire view tree is non-interactive.
    func blockingOverlay(isPresented: Bool, message: String = "Please wait…") -> some View {
        self
            .overlay {
                if isPresented {
                    BlockingProgressOverlay(message: message)
                        .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                }
            }
            .allowsHitTesting(!isPresented)
    }
}

// MARK: - Section Header

/// Consistent GroupBox label used across all dashboard pages.
///
/// Usage:
/// ```swift
/// GroupBox {
///     // content
/// } label: {
///     SectionHeader("Fallback Models", count: 3, description: "Tried in order")
/// }
/// ```
struct SectionHeader: View {
    let title: String
    var count: Int? = nil
    var description: String? = nil

    init(_ title: String, count: Int? = nil, description: String? = nil) {
        self.title = title
        self.count = count
        self.description = description
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            if let count {
                Text("·")
                    .foregroundStyle(.secondary)
                Text("\(count)")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let description {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Connection Indicator

/// Small colored dot + label showing gateway/offline status.
struct ConnectionBadge: View {
    var isConnected: Bool
    var connectedLabel: String = "Gateway"
    var offlineLabel: String = "Offline"

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isConnected ? Color.green : Color.orange)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Text(isConnected ? connectedLabel : offlineLabel)
                .font(.caption2)
                .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Connection status: \(isConnected ? connectedLabel : offlineLabel)")
    }
}

// MARK: - Copyable Text

/// Monospaced text that copies to clipboard on click, with a tooltip.
///
/// Usage:
/// ```swift
/// CopyableText(deviceId, preview: "\(deviceId.prefix(16))...")
/// ```
struct CopyableText: View {
    let fullText: String
    let displayText: String
    var font: Font = .system(.caption2, design: .monospaced)
    var color: Color = Color(nsColor: .tertiaryLabelColor)

    init(_ fullText: String, preview: String? = nil) {
        self.fullText = fullText
        self.displayText = preview ?? fullText
    }

    var body: some View {
        Text(displayText)
            .font(font)
            .foregroundStyle(color)
            .help("Click to copy: \(fullText)")
            .onTapGesture {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(fullText, forType: .string)
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Click to copy to clipboard")
    }
}
