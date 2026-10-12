import SwiftUI

enum SessionRowFeedback: Equatable {
    case permissionDenied
    case notFound
}

struct SessionRowView: View {
    let session: Session
    let now: Date
    let feedback: SessionRowFeedback?
    let onSelect: (Session) -> Void
    let onGrantAccess: () -> Void

    @State private var isHovering = false

    private var canFocus: Bool {
        session.isFocusable
    }

    private var focusHint: String {
        canFocus ? "Jump to this agent" : "Background session"
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 5) {
            Button {
                onSelect(session)
            } label: {
                cardContent
            }
            .buttonStyle(NotchRowButtonStyle(isEnabled: canFocus))
            .disabled(!canFocus)
            .help(focusHint)

            if feedback == .permissionDenied {
                Button(action: onGrantAccess) {
                    Label("Grant Automation access", systemImage: "gearshape")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .tracking(NotchDesign.tracking(forSize: 10))
                        .foregroundStyle(DisplayStatus.needsMe.color)
                }
                .buttonStyle(.plain)
                .help("Open Automation privacy settings")
            } else if feedback == .notFound {
                Text("Terminal window not found")
                    .font(.system(size: 10, design: .monospaced))
                    .tracking(NotchDesign.tracking(forSize: 10))
                    .foregroundStyle(NotchDesign.textQuaternary)
            }
        }
        .opacity(canFocus ? 1 : 0.55)
    }

    private var cardContent: some View {
        HStack(alignment: .top, spacing: 10) {
            AgentSprite(status: session.displayStatus, size: 18)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                titleLine
                    .lineLimit(1)
                    .truncationMode(.tail)

                if let prompt = session.prompt,
                   !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("You: \(prompt)")
                        .font(.system(size: 11, design: .monospaced))
                        .tracking(NotchDesign.tracking(forSize: 11))
                        .foregroundStyle(NotchDesign.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                activityLine
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailingMetadata
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isHovering && canFocus ? NotchDesign.rowFillHover : NotchDesign.rowFill)
        .clipShape(.rect(cornerRadius: 12))
        .contentShape(.rect)
        .onHover { hovering in
            isHovering = canFocus && hovering
        }
    }

    private var titleLine: Text {
        let project = Text(session.project)
            .font(.system(size: 13, weight: .bold, design: .monospaced))
            .tracking(NotchDesign.tracking(forSize: 13))
            .foregroundColor(NotchDesign.textPrimary)

        guard let task = session.task, !task.isEmpty else {
            return project
        }

        return project
            + Text(" · ")
                .font(.system(size: 13, design: .monospaced))
                .tracking(NotchDesign.tracking(forSize: 13))
                .foregroundColor(NotchDesign.textQuaternary)
            + Text(task)
                .font(.system(size: 13, design: .monospaced))
                .tracking(NotchDesign.tracking(forSize: 13))
                .foregroundColor(NotchDesign.textTertiary)
    }

    @ViewBuilder
    private var activityLine: some View {
        if session.displayStatus == .working,
           let toolLine = session.toolLine,
           !toolLine.isEmpty {
            highlightedToolLine(toolLine)
                .lineLimit(1)
                .truncationMode(.tail)
        } else if session.displayStatus == .done {
            Text("Done — click to jump")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(DisplayStatus.done.color)
                .lineLimit(1)
        }
    }

    private func highlightedToolLine(_ line: String) -> Text {
        let parts = line.split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
        let tool = parts.first.map(String.init) ?? line
        let detail = parts.count > 1 ? " " + String(parts[1]) : ""

        return Text(tool)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundColor(Color(red: 110 / 255, green: 180 / 255, blue: 255 / 255))
            + Text(detail)
                .font(.system(size: 11, design: .monospaced))
                .tracking(NotchDesign.tracking(forSize: 11))
                .foregroundColor(NotchDesign.textTertiary)
    }

    private var trailingMetadata: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 4) {
                chip(
                    SessionChipStyle.agentLabel(session.agent),
                    tint: SessionChipStyle.agentTint(session.agent)
                )

                if let model = session.model, !model.isEmpty {
                    chip(SessionChipStyle.modelLabel(model))
                }

                if let terminal = session.terminal?.termProgram, !terminal.isEmpty {
                    chip(SessionChipStyle.terminalLabel(terminal))
                }

                chip(session.elapsed(at: now))
            }

            Circle()
                .fill(session.displayStatus.color)
                .frame(width: 6, height: 6)
                .accessibilityLabel(Text(session.displayStatus.label))
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func chip(_ label: String, tint: Color = NotchDesign.textTertiary) -> some View {
        Text(label)
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .tracking(NotchDesign.tracking(forSize: 9))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.primary.opacity(0.06))
            .clipShape(.capsule)
    }
}
