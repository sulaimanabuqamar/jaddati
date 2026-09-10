import SwiftUI

/// The front door. One job: get you to a voice you want to hear.
/// No dashboard, no counters, no grid of features.
struct HomeView: View {
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var player: AudioPlayer
    @State private var addingPerson = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Palette.ivory.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.m) {
                        masthead

                        if let problem = library.storageError {
                            ErrorNote(message: problem)
                        }

                        if library.people.isEmpty {
                            EmptyHint(
                                icon: "waveform",
                                title: "No one here yet",
                                message: "Add someone whose voice you have a recording of, and Jaddati will keep it for you."
                            )
                            Button("Add someone") { addingPerson = true }
                                .buttonStyle(PrimaryButtonStyle())
                        } else {
                            ForEach(library.people) { person in
                                NavigationLink(value: person) {
                                    PersonCard(person: person,
                                               originals: library.assets(for: person, source: .original).count,
                                               memories: library.assets(for: person, source: .generated).count)
                                }
                                .buttonStyle(.plain)
                            }

                            Button("Add someone else") { addingPerson = true }
                                .buttonStyle(QuietButtonStyle())
                                .padding(.top, Theme.Space.xs)
                        }

                        if !AppConfig.isConfigured {
                            notConfiguredNote
                        }
                    }
                    .padding(Theme.Space.m)
                    .padding(.bottom, Theme.Space.xl)
                }
            }
            .navigationDestination(for: Person.self) { person in
                PersonView(personId: person.id)
            }
            .sheet(isPresented: $addingPerson) {
                AddPersonView()
            }
        }
    }

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("جدّتي")
                .font(Theme.Font.display(40))
                .foregroundStyle(Theme.Palette.forest)
                .environment(\.layoutDirection, .rightToLeft)
            Text("Jaddati")
                .font(Theme.Font.displayMedium(20))
                .foregroundStyle(Theme.Palette.ink)
            Text("a familiar voice, whenever you need it")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
        }
        .padding(.top, Theme.Space.s)
        .padding(.bottom, Theme.Space.xs)
    }

    /// Honest about the build's state rather than failing mysteriously later.
    private var notConfiguredNote: some View {
        Panel {
            VStack(alignment: .leading, spacing: 6) {
                Text("Voices are not set up on this build")
                    .font(Theme.Font.label)
                    .foregroundStyle(Theme.Palette.ink)
                Text("Saved audio still plays. Creating a new voice or new speech needs the key in Secrets.plist.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct PersonCard: View {
    let person: Person
    let originals: Int
    let memories: Int

    var body: some View {
        Panel {
            HStack(spacing: Theme.Space.s) {
                Circle()
                    .fill(Theme.Palette.forest.opacity(0.10))
                    .frame(width: 52, height: 52)
                    .overlay(
                        Text(initials)
                            .font(Theme.Font.displayMedium(20))
                            .foregroundStyle(Theme.Palette.forest)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(person.name)
                        .font(Theme.Font.heading)
                        .foregroundStyle(Theme.Palette.ink)
                    Text(subtitle)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.inkSoft)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Palette.hairline)
            }
        }
    }

    private var initials: String {
        let first = person.name.trimmingCharacters(in: .whitespaces).first
        return first.map { String($0) } ?? "؟"
    }

    private var subtitle: String {
        if !person.hasVoice {
            return originals == 0 ? "No recordings yet" : "Voice not created yet"
        }
        var parts: [String] = []
        if originals > 0 { parts.append("\(originals) original\(originals == 1 ? "" : "s")") }
        if memories > 0 { parts.append("\(memories) memor\(memories == 1 ? "y" : "ies")") }
        return parts.isEmpty ? "Voice ready" : parts.joined(separator: " · ")
    }
}

/// Creating a profile is deliberately two fields. Nothing here needs an account.
struct AddPersonView: View {
    @EnvironmentObject private var library: Library
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var relationship = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Palette.ivory.ignoresSafeArea()
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    Text("Who is this?")
                        .font(Theme.Font.title)
                        .foregroundStyle(Theme.Palette.ink)

                    Panel {
                        VStack(alignment: .leading, spacing: Theme.Space.s) {
                            Field(title: "What you call them", text: $name, placeholder: "Jaddati")
                            Divider().overlay(Theme.Palette.hairline)
                            Field(title: "Relationship (optional)", text: $relationship, placeholder: "Grandmother")
                        }
                    }

                    Text("You can add their recordings on the next screen.")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.inkSoft)

                    Spacer()

                    Button("Add") {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        library.add(Person(name: trimmed, relationship: relationship))
                        dismiss()
                    }
                    .buttonStyle(PrimaryButtonStyle(
                        enabled: !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(Theme.Space.m)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

struct Field: View {
    let title: String
    @Binding var text: String
    let placeholder: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
            TextField(placeholder, text: $text)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Palette.ink)
                .textInputAutocapitalization(.words)
        }
    }
}
