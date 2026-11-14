//
//  UpdateDialogView.swift
//  baplet
//

import SwiftUI

/// The update window: the new version, its release notes, and Install & Restart,
/// Download Manually and Later. While installing it shows a progress bar and the current
/// step; when an in-place install isn't possible it explains why and leaves only the
/// manual download.
struct UpdateDialogView: View {
    @Environment(UpdateService.self) private var updateService
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        Group {
            if let update = updateService.availableUpdate {
                content(for: update)
            } else {
                ContentUnavailableView {
                    Label("Baplet is up to date", systemImage: "checkmark.circle")
                } description: {
                    Text("You're running version \(updateService.currentVersionString).")
                } actions: {
                    Button("Close") { dismissWindow(id: WindowID.update) }
                        .keyboardShortcut(.cancelAction)
                }
                .frame(height: 220)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    /// Header, release notes, status and buttons for one available release.
    private func content(for update: UpdateRelease) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Image("baplet")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text("A new version of Baplet is available")
                        .font(.headline)
                    Text("Baplet \(update.version.description) is available. You have \(updateService.currentVersionString).")
                        .foregroundStyle(.secondary)
                }
            }

            Text("Release Notes")
                .font(.subheadline)
                .fontWeight(.semibold)
            ScrollView {
                ReleaseNotesView(markdown: update.notes)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(height: 220)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 6))

            status

            HStack {
                Button("Later") { dismissWindow(id: WindowID.update) }
                    .keyboardShortcut(.cancelAction)
                    .disabled(updateService.isInstalling)
                Spacer()
                Button("Download Manually") { updateService.downloadManually() }
                    .disabled(updateService.isInstalling)
                Button("Install & Restart") {
                    Task { await updateService.installAndRestart() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(updateService.isInstalling || updateService.installRefusal != nil)
            }
        }
    }

    /// The progress bar and step while installing, the error after a failed install, or
    /// the reason an in-place install isn't possible.
    @ViewBuilder
    private var status: some View {
        switch updateService.installStatus {
        case .running(let step):
            VStack(alignment: .leading, spacing: 4) {
                if let fraction = step.fraction {
                    ProgressView(value: fraction)
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                }
                Text(step.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.red)
        case .idle:
            if let refusal = updateService.installRefusal {
                Label(refusal, systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// One block of release notes: a heading, a list item, a code line or a paragraph.
nonisolated enum ReleaseNotesBlock: Equatable {
    case heading(String)
    case listItem(marker: String, text: String)
    case code(String)
    case paragraph(String)

    /// Splits GitHub-flavoured markdown into blocks line by line. SwiftUI's `Text` renders
    /// only inline markdown, so headings, lists and code fences are recognised here and
    /// everything inside a block is left for inline rendering. Consecutive plain lines join
    /// into one paragraph.
    static func parse(_ markdown: String) -> [ReleaseNotesBlock] {
        var blocks: [ReleaseNotesBlock] = []
        var paragraph: [String] = []
        var inCode = false

        /// Closes the paragraph being collected, if any.
        func flushParagraph() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: " ")))
                paragraph = []
            }
        }

        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                flushParagraph()
                inCode.toggle()
            } else if inCode {
                blocks.append(.code(rawLine))
            } else if line.isEmpty {
                flushParagraph()
            } else if let heading = headingText(line) {
                flushParagraph()
                blocks.append(.heading(heading))
            } else if let item = listItem(line) {
                flushParagraph()
                blocks.append(.listItem(marker: item.marker, text: item.text))
            } else {
                paragraph.append(line)
            }
        }
        flushParagraph()
        return blocks
    }

    /// The text of a `#`–`######` heading line, or nil when the line isn't one.
    private static func headingText(_ line: String) -> String? {
        let hashes = line.prefix { $0 == "#" }
        guard (1...6).contains(hashes.count), line.dropFirst(hashes.count).first == " " else { return nil }
        return line.dropFirst(hashes.count + 1).trimmingCharacters(in: .whitespaces)
    }

    /// The marker ("•" or "1.") and text of a bulleted or numbered list line, or nil.
    private static func listItem(_ line: String) -> (marker: String, text: String)? {
        for bullet in ["- ", "* ", "+ "] where line.hasPrefix(bullet) {
            return ("•", String(line.dropFirst(bullet.count)))
        }
        let digits = line.prefix { $0.isASCII && $0.isNumber }
        if !digits.isEmpty, line.dropFirst(digits.count).hasPrefix(". ") {
            return ("\(digits).", String(line.dropFirst(digits.count + 2)))
        }
        return nil
    }
}

/// Renders a release's markdown body: block structure from `ReleaseNotesBlock`, inline
/// styling (bold, italic, code, links) from `AttributedString`'s markdown parser.
struct ReleaseNotesView: View {
    let markdown: String

    var body: some View {
        let blocks = ReleaseNotesBlock.parse(markdown)
        VStack(alignment: .leading, spacing: 6) {
            if blocks.isEmpty {
                Text("No release notes.")
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .textSelection(.enabled)
    }

    /// The SwiftUI view for one block.
    @ViewBuilder
    private func view(for block: ReleaseNotesBlock) -> some View {
        switch block {
        case .heading(let text):
            Text(Self.inline(text))
                .font(.headline)
                .padding(.top, 4)
        case .listItem(let marker, let text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(marker)
                    .monospacedDigit()
                Text(Self.inline(text))
            }
        case .code(let text):
            Text(text)
                .font(.system(.callout, design: .monospaced))
        case .paragraph(let text):
            Text(Self.inline(text))
        }
    }

    /// Parses inline markdown, falling back to the plain text when it isn't valid markdown.
    private static func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}
