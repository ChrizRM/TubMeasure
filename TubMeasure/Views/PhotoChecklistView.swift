import PhotosUI
import SwiftUI

/// Every photo the office form asks for, with what's been taken or skipped.
struct PhotoChecklistView: View {
    @EnvironmentObject private var store: ScanStore
    let roomID: UUID

    var body: some View {
        if let room = store.room(roomID) {
            let r = SurveyResolver(room: room)
            let progress = r.photoProgress
            List {
                Section {
                    ForEach(SurveyForm.photos) { item in
                        NavigationLink(value: Route.photo(roomID, item.id)) {
                            PhotoChecklistRow(room: room, item: item, done: r.photoDone(item))
                        }
                    }
                } header: {
                    Text("\(progress.done) of \(progress.total) required")
                } footer: {
                    Text("During a scan, the camera button files photos straight into this list. After marking points, it takes snapshots stamped with the measurements.")
                }
            }
            .navigationTitle("Photos")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct PhotoChecklistRow: View {
    let room: RoomModel
    let item: PhotoItem
    let done: Bool

    var body: some View {
        let photos = room.survey.photos[item.id] ?? []
        let skip = room.survey.photoSkips[item.id] ?? ""
        HStack(spacing: 12) {
            Image(systemName: done ? (photos.isEmpty ? "minus.circle.fill" : "checkmark.circle.fill") : "circle")
                .foregroundStyle(done ? (photos.isEmpty ? Color.orange : Color.green) : Color.secondary)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline)
                if !photos.isEmpty {
                    Text("\(photos.count) photo\(photos.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if !skip.isEmpty {
                    Text("Skipped: \(skip)")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if !item.required {
                    Text("Optional")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let first = photos.first {
                Thumbnail(jobID: room.id, fileName: first.fileName)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }
}

/// One checklist photo: take or pick photos, add a note, or record why it was skipped.
struct PhotoItemView: View {
    @EnvironmentObject private var store: ScanStore
    let roomID: UUID
    let itemID: String
    @State private var showCamera = false
    @State private var picked: [PhotosPickerItem] = []
    @State private var viewing: SurveyPhoto?

    private var item: PhotoItem? { SurveyForm.photos.first { $0.id == itemID } }

    var body: some View {
        if let room = store.room(roomID), let item {
            let photos = room.survey.photos[itemID] ?? []
            List {
                if let hint = item.hint {
                    Section {
                        Text(hint)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Photos") {
                    if photos.isEmpty {
                        Text("No photos yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                            ForEach(photos) { photo in
                                Thumbnail(jobID: roomID, fileName: photo.fileName)
                                    .frame(height: 96)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .onTapGesture { viewing = photo }
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            remove(photo)
                                        } label: {
                                            Label("Delete photo", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    Button {
                        showCamera = true
                    } label: {
                        Label("Take photo", systemImage: "camera")
                    }
                    .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                    PhotosPicker(selection: $picked, maxSelectionCount: 10, matching: .images) {
                        Label("Choose from library", systemImage: "photo.on.rectangle")
                    }
                }
                Section {
                    TextField("e.g. 24\" doorway", text: binding(\.photoNotes), axis: .vertical)
                } header: {
                    Text("Note")
                } footer: {
                    Text("Printed under the photos in the PDF.")
                }
                Section {
                    TextField("Reason", text: binding(\.photoSkips))
                    HStack {
                        ForEach(["Requested no photos", "Not applicable"], id: \.self) { reason in
                            Button(reason) {
                                store.update(roomID) { $0.survey.photoSkips[itemID] = reason }
                            }
                            .buttonStyle(.bordered)
                            .font(.caption)
                        }
                    }
                } header: {
                    Text("Can't take this photo?")
                } footer: {
                    Text("A reason counts the item as done. It is printed in place of the photo.")
                }
            }
            .navigationTitle(item.title)
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { image in
                    add(image)
                }
                .ignoresSafeArea()
            }
            .sheet(item: $viewing) { photo in
                PhotoViewer(jobID: roomID, fileName: photo.fileName)
            }
            .onChange(of: picked) { _, items in
                guard !items.isEmpty else { return }
                Task {
                    for pickedItem in items {
                        if let data = try? await pickedItem.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                            add(image)
                        }
                    }
                    picked = []
                }
            }
        }
    }

    private func binding(_ key: WritableKeyPath<Survey, [String: String]>) -> Binding<String> {
        Binding(
            get: { store.room(roomID)?.survey[keyPath: key][itemID] ?? "" },
            set: { value in
                store.update(roomID) { $0.survey[keyPath: key][itemID] = value.isEmpty ? nil : value }
            }
        )
    }

    private func add(_ image: UIImage) {
        guard let file = PhotoFiles.save(image, jobID: roomID, photoID: itemID) else { return }
        store.update(roomID) { $0.survey.photos[itemID, default: []].append(SurveyPhoto(fileName: file)) }
    }

    private func remove(_ photo: SurveyPhoto) {
        PhotoFiles.delete(jobID: roomID, fileName: photo.fileName)
        store.update(roomID) { $0.survey.photos[itemID]?.removeAll { $0.id == photo.id } }
    }
}

/// Loads a small version of a saved photo off the main thread.
struct Thumbnail: View {
    let jobID: UUID
    let fileName: String
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.gray.opacity(0.15)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
        }
        .task(id: fileName) {
            let url = PhotoFiles.url(jobID: jobID, fileName: fileName)
            image = await Task.detached(priority: .userInitiated) {
                UIImage(contentsOfFile: url.path)?.preparingThumbnail(of: CGSize(width: 240, height: 240))
            }.value
        }
    }
}

private struct PhotoViewer: View {
    @Environment(\.dismiss) private var dismiss
    let jobID: UUID
    let fileName: String

    var body: some View {
        NavigationStack {
            Group {
                if let image = PhotoFiles.image(jobID: jobID, fileName: fileName) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    Text("Photo not found.")
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// The system camera, returning one photo.
struct CameraPicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    var onImage: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker

        init(_ parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImage(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
