import SwiftUI

/// Full-screen capture flow: sweep the room, then mark the points RoomPlan can't see.
struct ScanView: View {
    @EnvironmentObject private var store: ScanStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var controller = CaptureController()
    @State private var markKind: MarkKind = .drain

    var onSaved: (UUID) -> Void

    var body: some View {
        ZStack {
            CaptureContainer(view: controller.containerView)
                .ignoresSafeArea()

            if controller.phase == .marking {
                Image(systemName: "plus")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(.white)
                    .shadow(color: .black, radius: 2)
                    .allowsHitTesting(false)
            }

            VStack {
                topBar
                Spacer()
                switch controller.phase {
                case .scanning: scanningControls
                case .processing: processing
                case .marking: markingControls
                case .failed(let message): failure(message)
                }
            }
            .padding()
        }
        .onAppear { controller.start() }
        .statusBarHidden()
    }

    private var topBar: some View {
        HStack {
            Button("Cancel") {
                controller.cancel()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(.black.opacity(0.55))
            Spacer()
            if !controller.liveItems.isEmpty {
                HStack(spacing: 6) {
                    ForEach(controller.liveItems) { item in
                        Image(systemName: Theme.symbol(item.category))
                    }
                }
                .font(.footnote)
                .foregroundStyle(.white)
                .padding(8)
                .background(.black.opacity(0.55), in: Capsule())
                .accessibilityLabel("Loose items seen: " + controller.liveItems.map(\.category.displayName).joined(separator: ", "))
            }
        }
    }

    private var photoButton: some View {
        Button {
            controller.takePhoto()
        } label: {
            Label("\(controller.photoCount)", systemImage: "camera.fill")
        }
        .buttonStyle(.borderedProminent)
        .tint(.black.opacity(0.55))
        .disabled(controller.photoCount >= CaptureController.maxPhotos)
        .accessibilityLabel("Take reference photo")
    }

    private var scanningControls: some View {
        VStack(spacing: 10) {
            Text("Walk slowly around the room. Sweep every wall from floor to ceiling, and get the toilet, tub, vanity, window and door fully in view.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .padding(10)
                .foregroundStyle(.white)
                .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
            HStack {
                photoButton
                Spacer()
                Button("Done scanning") {
                    controller.finishScanning()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }

    private var processing: some View {
        HStack(spacing: 10) {
            ProgressView().tint(.white)
            Text("Building the room model…")
        }
        .padding()
        .foregroundStyle(.white)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
    }

    private var markingControls: some View {
        VStack(spacing: 10) {
            Text(controller.markError ?? markKind.instruction)
                .font(.footnote)
                .multilineTextAlignment(.center)
                .padding(10)
                .foregroundStyle(controller.markError == nil ? Color.white : Color.yellow)
                .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(MarkKind.allCases) { kind in
                        let count = controller.marks.filter { $0.kind == kind }.count
                        Button {
                            markKind = kind
                            controller.markError = nil
                        } label: {
                            Text(count > 0 ? "\(kind.displayName) (\(count))" : kind.displayName)
                                .font(.footnote.weight(.semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(markKind == kind ? Theme.color(kind) : .black.opacity(0.55))
                    }
                }
            }

            HStack {
                Button {
                    controller.undoMark()
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.borderedProminent)
                .tint(.black.opacity(0.55))
                .disabled(controller.marks.isEmpty)

                photoButton
                Spacer()

                Button("Mark") {
                    controller.addMark(markKind)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Finish") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.green)
            }
        }
    }

    private func failure(_ message: String) -> some View {
        VStack(spacing: 12) {
            Text(message)
                .multilineTextAlignment(.center)
            Button("Close") {
                controller.cancel()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .foregroundStyle(.white)
        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
    }

    private func save() {
        let name = "Bathroom " + Date().formatted(date: .abbreviated, time: .shortened)
        let room = controller.finish(name: name)
        store.save(room)
        dismiss()
        onSaved(room.id)
    }
}

private struct CaptureContainer: UIViewRepresentable {
    let view: UIView

    func makeUIView(context: Context) -> UIView { view }
    func updateUIView(_ uiView: UIView, context: Context) {}
}
