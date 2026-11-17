import SwiftUI
import DigbyDesign
import DigbyDownloadCore

/// File names built from blocks: click a part to add it, drag parts into order, choose what goes between
/// them, and see the exact name as you go. Typing a template stays possible under "Edit as Text".
struct FileNameBuilder: View {
    @Environment(AppModel.self) private var model
    @State private var editingText = false
    @State private var dragging: NameParts.Token?

    var parts: NameParts? { NameParts(template: model.nameTemplate) }

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 12) {
            preview
            if let p = parts {
                arrangement(p)
                addRow(p)
                HStack(spacing: 8) {
                    Text("Between parts").font(.callout).foregroundStyle(.secondary)
                    let applies = p.parts.dropFirst().contains { $0.wrap == .none }
                    ForEach(NameParts.separators, id: \.value) { s in
                        PillButton(s.value == " " ? s.name : "\(s.name)  \(s.value.trimmingCharacters(in: .whitespaces))",
                                   selected: p.separator == s.value, enabled: applies,
                                   help: applies ? nil : "Used between plain parts; a part in brackets always follows a space. Add another plain part to choose.") {
                            var q = p; q.separator = s.value; set(q)
                        }
                    }
                    Spacer()
                }
            } else {
                InfoRow("This name has text of your own, so it’s shown as text. Pick a ready-made arrangement to use the blocks again.",
                        systemImage: "character.cursor.ibeam", tint: .secondary)
            }
            HStack(spacing: 10) {
                Menu("Ready-made") {
                    ForEach(NameParts.presets, id: \.name) { pr in Button(pr.name) { set(pr.parts) } }
                }
                .fixedSize()
                Button(editingText || parts == nil ? "Hide Text" : "Edit as Text…") { editingText.toggle() }
                    .buttonStyle(.link).disabled(parts == nil)
                Spacer()
            }
            if editingText || parts == nil {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("File names", text: $model.nameTemplate).font(.body.monospaced()).textFieldStyle(.roundedBorder)
                    Text("Use {title} {uploader} {date} {resolution} {site} {id}, with any text of your own.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("Digby never overwrites a file: if the name is taken, it adds a number. Playlists are always numbered in order.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    // MARK: Pieces

    var preview: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc").foregroundStyle(Brand.accent)
            (Text(previewName).fontWeight(.medium) + Text(".mp4").foregroundColor(.secondary))
                .lineLimit(2).textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .font(.callout)
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
        .accessibilityLabel("Example file name: \(previewName).mp4")
    }

    var previewName: String {
        FileNamer.render(model.nameTemplate, media: SampleMedia.video,
                         plan: FormatSelector.select(FormatCatalogue(SampleMedia.video), Choices(), playback: model.playback).plan)
    }

    func arrangement(_ p: NameParts) -> some View {
        FlowLayout(spacing: 6) {
            ForEach(Array(p.parts.enumerated()), id: \.element.id) { i, part in
                if i > 0 { Text(gapLabel(p, part)).font(.callout.monospaced()).foregroundStyle(.tertiary).padding(.top, 4) }
                PartChip(part: part, index: i, count: p.parts.count, dragging: dragging == part.token,
                         change: { new in var q = p; q.parts[i] = new; set(q) },
                         move: { by in move(p, from: i, to: i + by) },
                         remove: { var q = p; q.parts.remove(at: i); set(q) })
                    .onDrag { dragging = part.token; return NSItemProvider(object: part.token.rawValue as NSString) }
                    .onDrop(of: [.text], delegate: PartDrop(target: part.token, parts: p, dragging: $dragging, set: set))
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("File name parts, in order")
    }

    func addRow(_ p: NameParts) -> some View {
        let unused = NameParts.Token.allCases.filter { t in !p.parts.contains { $0.token == t } }
        return HStack(spacing: 6) {
            Text("Add").font(.callout).foregroundStyle(.secondary)
            if unused.isEmpty { Text("Every part is in use").font(.callout).foregroundStyle(.tertiary) }
            ForEach(unused, id: \.self) { t in
                Button { var q = p; q.parts.append(.init(t, t == .resolution || t == .id ? .round : .none)); set(q) } label: {
                    Label(t.label, systemImage: "plus").font(.callout).lineLimit(1).fixedSize()
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Capsule().strokeBorder(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain).help(t.help)
            }
            Spacer(minLength: 0)
        }
    }

    func gapLabel(_ p: NameParts, _ next: NameParts.Part) -> String {
        let g = next.wrap == .none ? p.separator : (p.separator == "_" ? "_" : " ")
        return g == " " ? "␣" : g.trimmingCharacters(in: .whitespaces)
    }

    func move(_ p: NameParts, from: Int, to: Int) {
        guard p.parts.indices.contains(to) else { return }
        var q = p; q.parts.swapAt(from, to); set(q)
    }

    func set(_ p: NameParts) {
        guard !p.parts.isEmpty else { return }       // a name always has at least one part
        withAnimation(.easeOut(duration: 0.15)) { model.nameTemplate = p.template }
    }
}

/// One part of the name: drag it to reorder, click for brackets or to move it, × to remove.
private struct PartChip: View {
    var part: NameParts.Part
    var index: Int
    var count: Int
    var dragging: Bool
    var change: (NameParts.Part) -> Void
    var move: (Int) -> Void
    var remove: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "line.3.horizontal").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            Menu {
                Picker("Written", selection: Binding(get: { part.wrap }, set: { var p = part; p.wrap = $0; change(p) })) {
                    ForEach(NameParts.Wrap.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.inline)
                Divider()
                Button("Move Left") { move(-1) }.disabled(index == 0)
                Button("Move Right") { move(1) }.disabled(index == count - 1)
                Divider()
                Button("Remove") { remove() }.disabled(count == 1)
            } label: {
                Text(label).font(.callout.weight(.medium)).lineLimit(1).foregroundStyle(Brand.accent)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            if count > 1 {
                Button(action: remove) { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).frame(width: 14, height: 14) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).opacity(hover ? 1 : 0.5)
                    .help("Remove \(part.token.label)").accessibilityLabel("Remove \(part.token.label)")
            }
        }
        .padding(.leading, 8).padding(.trailing, count > 1 ? 5 : 10).padding(.vertical, 5)
        .background(Capsule().fill(Brand.accent.opacity(hover ? 0.2 : 0.13)))
        .overlay(Capsule().strokeBorder(Brand.accent.opacity(0.45), lineWidth: 0.5))
        .foregroundStyle(Brand.accent)
        .opacity(dragging ? 0.4 : 1)
        .onHover { hover = $0 }
        .help("\(part.token.help). Drag to reorder; click for brackets.")
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(part.token.label), part \(index + 1) of \(count)")
    }

    var label: String {
        switch part.wrap { case .none: part.token.label; case .round: "(\(part.token.label))"; case .square: "[\(part.token.label)]" }
    }
}

/// Reorders live while a part is dragged over another.
private struct PartDrop: DropDelegate {
    var target: NameParts.Token
    var parts: NameParts
    @Binding var dragging: NameParts.Token?
    var set: (NameParts) -> Void

    func dropEntered(info: DropInfo) {
        guard let d = dragging, d != target,
              let from = parts.parts.firstIndex(where: { $0.token == d }),
              let to = parts.parts.firstIndex(where: { $0.token == target }) else { return }
        var q = parts
        q.parts.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        set(q)
    }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool { dragging = nil; return true }
}
