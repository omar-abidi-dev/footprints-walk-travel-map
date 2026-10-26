import SwiftUI
import PhotosUI

/// Picks a photo, downsizes it off the main thread and extracts its representative color.
struct PhotoPickerCard: View {
    @Binding var photoData: Data?
    @Binding var colorHex: String?
    var prompt = "Add a photo"

    @State private var item: PhotosPickerItem?
    @State private var loading = false

    var body: some View {
        PhotosPicker(selection: $item, matching: .images) {
            ZStack {
                if let photoData, let image = UIImage(data: photoData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 200)
                        .frame(maxWidth: .infinity)
                        .clipped()
                        .overlay(alignment: .bottomLeading) {
                            HStack(spacing: 8) {
                                if let c = Color(hexString: colorHex) {
                                    Circle().fill(c).frame(width: 14, height: 14).overlay(Circle().stroke(.white, lineWidth: 2))
                                    Text("Map color").font(.caption.weight(.semibold))
                                }
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .glassEffect(.regular, in: .capsule)
                            .padding(12)
                        }
                        .overlay(alignment: .topTrailing) {
                            Image(systemName: "arrow.triangle.2.circlepath.camera.fill")
                                .font(.subheadline)
                                .padding(10)
                                .glassEffect(.regular, in: .circle)
                                .padding(12)
                        }
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: loading ? "hourglass" : "photo.badge.plus.fill")
                            .font(.title)
                            .foregroundStyle(Theme.sunrise)
                            .symbolEffect(.pulse, isActive: loading)
                        Text(prompt).font(.headline)
                        Text("Its colors tint this footprint on your map")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 140)
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                            .foregroundStyle(.tertiary)
                    )
                }
            }
            .clipShape(.rect(cornerRadius: 22, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if photoData != nil {
                Button("Remove photo", systemImage: "trash", role: .destructive) {
                    photoData = nil
                    colorHex = nil
                }
            }
        }
        .task(id: item) {
            guard let item else { return }
            loading = true
            defer { loading = false }
            guard let raw = try? await item.loadTransferable(type: Data.self) else { return }
            let prepared = await Task.detached(priority: .userInitiated) { ImageTools.prepare(raw) }.value
            if let prepared {
                withAnimation {
                    photoData = prepared.jpeg
                    colorHex = prepared.colorHex
                }
            }
        }
    }
}
