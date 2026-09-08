import SwiftUI

/// Named gym setups. The default one is what the AI generates and modifies
/// for; the others are offered by "Somewhere else" on the dashboard.
struct EditEquipmentView: View {
    @Environment(AppDependencies.self) private var dependencies

    @State private var setups: [GymSetup] = []
    @State private var editing: GymSetup?
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                ForEach(setups) { setup in
                    Button {
                        editing = setup
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(setup.name)
                                    .foregroundStyle(.primary)
                                Text(setup.equipment.isEmpty
                                     ? "No equipment"
                                     : setup.equipment.map(\.displayName).joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            if setup.isDefault {
                                Image(systemName: "star.fill")
                                    .foregroundStyle(Color.accentColor)
                                    .accessibilityLabel("Default gym")
                            }
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if setups.count > 1 {
                            Button("Delete", role: .destructive) {
                                Task { await remove(setup) }
                            }
                        }
                        if !setup.isDefault {
                            Button("Make Default") {
                                Task { await makeDefault(setup) }
                            }
                            .tint(Color.accentColor)
                        }
                    }
                }
            } header: {
                Text("Gyms")
            } footer: {
                Text("Your default gym is what new programs and AI changes are built for. \"Somewhere else\" on the dashboard adapts today's workout to another gym.")
            }

            Section {
                Button {
                    editing = GymSetup(id: UUID().uuidString, name: "", equipment: [], isDefault: false)
                } label: {
                    Label("Add Gym", systemImage: "plus.circle")
                }
            }
        }
        .navigationTitle("Equipment")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(isSaving)
        .onAppear { setups = dependencies.authService.currentUser?.profile.effectiveGymSetups ?? [] }
        .sheet(item: $editing) { setup in
            GymSetupEditorView(setup: setup, isNew: !setups.contains { $0.id == setup.id }) { saved in
                Task { await upsert(saved) }
            }
        }
        .alert("Couldn't Save", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func upsert(_ saved: GymSetup) async {
        var next = setups
        if let index = next.firstIndex(where: { $0.id == saved.id }) {
            next[index] = saved
        } else {
            next.append(saved)
        }
        if saved.isDefault {
            for index in next.indices where next[index].id != saved.id { next[index].isDefault = false }
        }
        await persist(next)
    }

    private func remove(_ setup: GymSetup) async {
        var next = setups.filter { $0.id != setup.id }
        if !next.contains(where: \.isDefault), !next.isEmpty { next[0].isDefault = true }
        await persist(next)
    }

    private func makeDefault(_ setup: GymSetup) async {
        var next = setups
        for index in next.indices { next[index].isDefault = next[index].id == setup.id }
        await persist(next)
    }

    private func persist(_ next: [GymSetup]) async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await dependencies.memoryService.saveGymSetups(next)
            setups = dependencies.authService.currentUser?.profile.effectiveGymSetups ?? next
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct GymSetupEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var selection: Set<Equipment>
    @State private var isDefault: Bool
    private let setup: GymSetup
    private let isNew: Bool
    private let onSave: (GymSetup) -> Void

    init(setup: GymSetup, isNew: Bool, onSave: @escaping (GymSetup) -> Void) {
        self.setup = setup
        self.isNew = isNew
        self.onSave = onSave
        _name = State(initialValue: setup.name)
        _selection = State(initialValue: Set(setup.equipment))
        _isDefault = State(initialValue: setup.isDefault)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !selection.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Gym name (e.g. Home, Work, Travel)", text: $name)
                            .textFieldStyle(.roundedBorder)
                        Toggle("Default gym", isOn: $isDefault)
                            .disabled(setup.isDefault)
                    }
                    .padding(.horizontal)

                    EquipmentPickerGrid(selection: $selection)
                }
                .padding(.vertical)
            }
            .navigationTitle(isNew ? "New Gym" : "Edit Gym")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        onSave(GymSetup(
                            id: setup.id,
                            name: name.trimmingCharacters(in: .whitespaces),
                            equipment: Equipment.allCases.filter { selection.contains($0) },
                            isDefault: isDefault
                        ))
                        dismiss()
                    }
                    .font(.body.weight(.semibold))
                    .disabled(!canSave)
                }
            }
        }
    }
}
