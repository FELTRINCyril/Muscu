import SwiftUI
import SwiftData
import PhotosUI

/// Photos de progression : privées, stockées hors de la base, exclues des
/// exports par défaut et supprimables une par une.
struct ProgressPhotosView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ProgressPhoto.takenAt, order: .reverse) private var photos: [ProgressPhoto]

    @State private var pickedItem: PhotosPickerItem?
    @State private var errorMessage: String?
    @State private var pendingDeletion: ProgressPhoto?
    @State private var isImporting = false

    private var activePhotos: [ProgressPhoto] {
        photos.filter { $0.deletedAt == nil }
    }

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 8)]

    var body: some View {
        List {
            Section {
                // Le libellé du sélecteur reste FIXE : sa vue est construite
                // dans une fermeture isolée, où lire un état de la vue
                // déclenche un avertissement de concurrence. L'état d'avancement
                // est affiché sur sa propre ligne.
                PhotosPicker(selection: $pickedItem, matching: .images, photoLibrary: .shared()) {
                    Label("Ajouter une photo", systemImage: "camera")
                }
                .disabled(isImporting)
                .accessibilityIdentifier("photos.add")

                if isImporting {
                    HStack {
                        ProgressView()
                        Text("Ajout en cours…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("photos.error")
                }
            } footer: {
                Text("Les photos restent sur cet appareil : elles ne partent ni dans l’export, ni dans la synchronisation, ni dans la sauvegarde iCloud. Les envoyer ailleurs demanderait votre accord explicite, qui n’existe pas encore.")
            }

            Section {
                if activePhotos.isEmpty {
                    Text("Aucune photo.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("photos.empty")
                } else {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(activePhotos, id: \.id) { photo in
                            thumbnail(photo)
                        }
                    }
                }
            } header: {
                Text("Photos")
            } footer: {
                if !activePhotos.isEmpty {
                    Text("\(activePhotos.count) photo(s), \(Self.formatBytes(activePhotos.reduce(0) { $0 + $1.byteCount })) sur l’appareil.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Photos de progression")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: pickedItem) { _, item in
            guard let item else { return }
            Task { await add(item) }
        }
        .confirmationDialog(
            "Supprimer définitivement cette photo ?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Supprimer", role: .destructive) {
                if let photo = pendingDeletion {
                    ProgressPhotoStore.delete(photo, in: modelContext)
                }
                pendingDeletion = nil
            }
            Button("Annuler", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("Le fichier est effacé de l’appareil en même temps que la fiche.")
        }
    }

    private func thumbnail(_ photo: ProgressPhoto) -> some View {
        VStack(spacing: 4) {
            Group {
                if let data = PhotoStore.data(for: photo.assetName), let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    // Le fichier a disparu : on le dit au lieu d'afficher un
                    // cadre vide sans explication.
                    ZStack {
                        Theme.card
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .frame(width: 100, height: 100)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(photo.takenAt.formatted(date: .abbreviated, time: .omitted))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Photo du \(photo.takenAt.formatted(date: .long, time: .omitted))")
        .accessibilityAction(named: "Supprimer") { pendingDeletion = photo }
        .contextMenu {
            Button(role: .destructive) { pendingDeletion = photo } label: {
                Label("Supprimer", systemImage: "trash")
            }
        }
    }

    private func add(_ item: PhotosPickerItem) async {
        isImporting = true
        errorMessage = nil
        defer {
            isImporting = false
            pickedItem = nil
        }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                errorMessage = "Cette image n’a pas pu être lue."
                return
            }
            try ProgressPhotoStore.add(imageData: data, in: modelContext)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    static func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
