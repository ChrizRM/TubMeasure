import SwiftUI

/// The measurement form, in the office form's order. Scan values fill in by themselves;
/// typing an answer overrides the scan.
struct FormView: View {
    @EnvironmentObject private var store: ScanStore
    let roomID: UUID
    @State private var copied = false

    var body: some View {
        if let room = store.room(roomID) {
            let r = SurveyResolver(room: room)
            List {
                Section {
                    Label("Filled from the scan", systemImage: "viewfinder")
                        .foregroundStyle(.blue)
                        .font(.footnote)
                    Text("Type or pick an answer to replace a scan value. Long-press an answer to copy it.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(r.visibleFields) { field in
                    FieldRow(field: field, answer: r.answer(field),
                             manual: room.survey.answers[field.id] ?? "") { value in
                        store.update(roomID) { $0.survey.answers[field.id] = value.isEmpty ? nil : value }
                    }
                }
            }
            .navigationTitle("Measurements")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        UIPasteboard.general.string = r.formText()
                        copied = true
                    } label: {
                        Label(copied ? "Copied" : "Copy all", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                }
            }
        }
    }
}

private struct FieldRow: View {
    let field: SurveyField
    let answer: ResolvedAnswer
    let manual: String
    let set: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Text(field.title)
                    .font(.subheadline)
                Spacer(minLength: 8)
                if answer.value == nil {
                    Image(systemName: "circle")
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: answer.source == .scan ? "viewfinder" : "checkmark.circle.fill")
                        .foregroundStyle(answer.source == .scan ? .blue : .green)
                }
            }
            editor
            if let hint = field.hint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let detail = answer.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(answer.source == .scan ? .blue : .secondary)
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            if let value = answer.value {
                Button {
                    UIPasteboard.general.string = value
                } label: {
                    Label("Copy \"\(value)\"", systemImage: "doc.on.doc")
                }
            }
            if !manual.isEmpty {
                Button(role: .destructive) {
                    set("")
                } label: {
                    Label("Clear my answer", systemImage: "xmark.circle")
                }
            }
        }
    }

    @ViewBuilder private var editor: some View {
        switch field.input {
        case .yesNo:
            Picker(field.title, selection: pickerBinding) {
                Text(SurveyForm.yes).tag(SurveyForm.yes)
                Text(SurveyForm.no).tag(SurveyForm.no)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        case .choice(let options):
            Picker(field.title, selection: pickerBinding) {
                if answer.value == nil { Text("Choose…").tag("") }
                ForEach(options, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        case .text:
            TextField(answer.source == .scan ? answer.value ?? "" : "Type answer", text: textBinding, axis: .vertical)
                .textFieldStyle(.roundedBorder)
        case .inches, .feet:
            HStack {
                TextField(answer.source == .scan ? answer.value ?? "" : "0", text: textBinding)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 140)
                Text(field.input == .feet ? "ft" : "in")
                    .foregroundStyle(.secondary)
            }
        case .dimensions(let labels):
            DimensionsEditor(labels: labels, manual: manual, scan: answer.source == .scan ? answer.value : nil, set: set)
        }
    }

    private var pickerBinding: Binding<String> {
        Binding(get: { answer.value ?? "" }, set: { set($0) })
    }

    private var textBinding: Binding<String> {
        Binding(get: { manual }, set: { set($0) })
    }
}

/// Edits "LxWxH" style answers as separate boxes.
private struct DimensionsEditor: View {
    let labels: [String]
    let manual: String
    let scan: String?
    let set: (String) -> Void

    private func parts(_ s: String?) -> [String] {
        let p = (s ?? "").split(separator: "x", omittingEmptySubsequences: false).map(String.init)
        return labels.indices.map { $0 < p.count ? p[$0] : "" }
    }

    var body: some View {
        let current = parts(manual)
        let placeholder = parts(scan)
        HStack(spacing: 6) {
            ForEach(labels.indices, id: \.self) { i in
                VStack(alignment: .leading, spacing: 2) {
                    TextField(placeholder[i].isEmpty ? "0" : placeholder[i], text: Binding(
                        get: { current[i] },
                        set: { value in
                            var updated = parts(manual)
                            updated[i] = value.filter { $0.isNumber || $0 == "." }
                            set(updated.allSatisfy(\.isEmpty) ? "" : updated.joined(separator: "x"))
                        }
                    ))
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    Text(labels[i])
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if i < labels.count - 1 {
                    Text("×").foregroundStyle(.secondary)
                }
            }
            Text("in").foregroundStyle(.secondary)
        }
    }
}
