import SwiftUI

/// The front door. People come first — no feed, no counters that reward coming
/// back, no engagement score. The counts that are here describe a collection.
struct HomeView: View {
    @Binding var selectedPersonId: UUID?

    @EnvironmentObject private var library: Library
    @State private var addingPerson = false
    #if DEBUG
    @AppStorage(AppConfig.mockDefaultsKey) private var useMockVoices = false
    #endif

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                masthead

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        identity
                        hero

                        if let problem = library.storageError {
                            ErrorNote(message: problem).padding(.top, 16)
                        }
                        #if DEBUG
                        if useMockVoices { mockModeBanner.padding(.top, 16) }
                        #endif
                        if !AppConfig.isConfigured {
                            notConfiguredNote.padding(.top, 16)
                        }

                        people
                    }
                    .padding(.horizontal, Theme.Metric.screenPadding)
                    .padding(.bottom, Theme.Space.xl)
                }
            }
            .background(Theme.Palette.paper)
            .navigationDestination(for: Person.self) { person in
                PersonView(personId: person.id)
            }
            .sheet(isPresented: $addingPerson) { AddPersonView() }
        }
    }

    // MARK: Pieces

    private var masthead: some View {
        HStack {
            Text("جدّتي")
                .font(Theme.Font.display(22))
                .foregroundStyle(Theme.Palette.ink)
                .environment(\.layoutDirection, .rightToLeft)
            Spacer()
            #if DEBUG
            debugMenu
            #endif
            GlobeButton()
        }
        .padding(.horizontal, Theme.Metric.screenPadding)
        .frame(height: Theme.Metric.appBar)
        .background(Theme.Palette.paper)
    }

    /// Bilingual in both locales. The app is called جدّتي whichever language the
    /// interface is in, so the name never gets translated away.
    private var identity: some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: L("A family archive"))
            HStack(alignment: .firstTextBaseline) {
                Text("Jaddati")
                    .font(Theme.Font.display(37))
                    .tracking(-1.3)
                    .foregroundStyle(Theme.Palette.ink)
                Spacer(minLength: Theme.Space.s)
                Text("جدّتي")
                    .font(Theme.Font.display(28))
                    .foregroundStyle(Theme.Palette.wine)
                    .environment(\.layoutDirection, .rightToLeft)
            }
            SubText(text: L("A place for a familiar voice."))
        }
        .padding(.top, 8)
    }

    private var hero: some View {
        HeroCard {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: "circle.dotted.circle")
                    .font(.system(size: 19))
                    .foregroundStyle(Color(hex: 0xF8EFE4).opacity(0.85))
                    .padding(.bottom, 26)

                Text(L("The recordings you have. The words you choose."))
                    .font(Theme.Font.display(28))
                    .tracking(-0.5)
                    .lineSpacing(2)
                    .foregroundStyle(Color(hex: 0xF8EFE4))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 260, alignment: .leading)

                Color(hex: 0xF8EFE4).opacity(0.18)
                    .frame(height: 1)
                    .padding(.vertical, 16)

                HStack(spacing: 7) {
                    Image(systemName: "checkmark.seal")
                        .font(.system(size: 12))
                    Text(L("Original and recreated. Always distinct."))
                        .font(.system(size: 11))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Color(hex: 0xF8EFE4).opacity(0.8))
            }
        }
        .padding(.top, 21)
    }

    @ViewBuilder private var people: some View {
        if library.people.isEmpty {
            EmptyHint(icon: "waveform",
                      title: L("No people yet"),
                      message: L("Start with a name. Add a recording when you are ready."))
            addButton
        } else {
            SectionLabel(text: L("People you keep here"))
                .padding(.top, 26)

            ForEach(library.people) { person in
                NavigationLink(value: person) {
                    PersonCard(person: person,
                               photo: library.photoURL(for: person),
                               originals: library.assets(for: person, source: .original).count,
                               saved: library.assets(for: person, source: .generated)
                                   .filter { $0.isSaved }.count)
                }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture().onEnded { selectedPersonId = person.id })
            }

            addButton.padding(.top, 4)
        }
    }

    private var addButton: some View {
        Button { addingPerson = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                Text(L("Add someone"))
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Theme.Palette.wine)
            .frame(maxWidth: .infinity, minHeight: Theme.Metric.buttonHeight)
            .background(
                RoundedRectangle(cornerRadius: Theme.Metric.buttonRadius, style: .continuous)
                    .stroke(Theme.Palette.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    #if DEBUG
    @ViewBuilder private var debugMenu: some View {
        Menu {
            Toggle("Offline test mode", isOn: $useMockVoices)
        } label: {
            Image(systemName: "ladybug")
                .foregroundStyle(Theme.Palette.inkSoft)
                .frame(width: 36, height: 36)
        }
    }

    /// Loud on purpose. A test mode that looks like the real thing is how a
    /// cached file ends up presented as live generation.
    private var mockModeBanner: some View {
        Panel {
            VStack(alignment: .leading, spacing: 4) {
                Text("OFFLINE TEST MODE")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(Theme.Palette.danger)
                Text("Nothing reaches the voice service. Generated audio is a placeholder tone, not a voice. Turn this off before demonstrating.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    #endif

    private var notConfiguredNote: some View {
        Panel {
            VStack(alignment: .leading, spacing: 6) {
                Text(L("Voice service not connected"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.Palette.ink)
                SubText(text: L("Connect a voice service to create a voice or new audio. Original recordings remain available."))
            }
        }
    }
}

struct PersonCard: View {
    let person: Person
    let photo: URL?
    let originals: Int
    let saved: Int

    var body: some View {
        HStack(spacing: 13) {
            PersonAvatar(name: person.name, imageURL: photo, size: 54)

            VStack(alignment: .leading, spacing: 3) {
                BidiText(value: person.name,
                         font: Theme.Font.display(22),
                         colour: Theme.Palette.ink,
                         lineLimit: 1)
                Text(collection)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Palette.inkSoft)
                status
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color(hex: 0x958578))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: Theme.Metric.cardRadius, style: .continuous)
                .fill(Color(hex: 0xFFFAF4))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Metric.cardRadius, style: .continuous)
                .stroke(Theme.Palette.hairline, lineWidth: 1)
        )
        .padding(.vertical, 5)
    }

    /// Describes a collection, never a streak.
    private var collection: String {
        var parts: [String] = []
        if originals > 0 { parts.append(Counts.originals(originals)) }
        if saved > 0 { parts.append(Counts.savedClips(saved)) }
        if parts.isEmpty { return person.relationship.isEmpty ? L("No recordings yet") : person.relationship }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var status: some View {
        if person.voiceIsUnavailableHere {
            Text(L("Test voice · No real voice was created."))
                .font(.system(size: 12))
                .foregroundStyle(Theme.Palette.danger)
        } else if person.hasVoice {
            HStack(spacing: 6) {
                Circle().fill(Theme.Palette.sage).frame(width: 5, height: 5)
                Text(L("Recreated voice ready"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Palette.sage)
            }
        } else {
            Text(L("No recreated voice yet"))
                .font(.system(size: 12))
                .foregroundStyle(Theme.Palette.inkSoft)
        }
    }
}

/// Creating a profile is two fields. Nothing here needs an account.
struct AddPersonView: View {
    @EnvironmentObject private var library: Library
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var relationship = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Palette.paper.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 0) {
                    Text(L("Add a person"))
                        .font(Theme.Font.display(28))
                        .foregroundStyle(Theme.Palette.ink)
                        .padding(.bottom, 13)
                    SubText(text: L("Start with a name. Add a recording when you are ready."))

                    Field(title: L("Name"), text: $name, placeholder: "جدّتي")
                    Field(title: L("Relationship"), text: $relationship,
                          placeholder: L("Grandmother"))

                    Spacer()

                    Button(L("Add someone")) {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        library.add(Person(name: trimmed, relationship: relationship))
                        dismiss()
                    }
                    .buttonStyle(PrimaryButtonStyle(
                        enabled: !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(Theme.Metric.screenPadding)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancel")) { dismiss() }
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
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(Theme.Palette.inkSoft)
            TextField(placeholder, text: $text)
                .font(.system(size: 16))
                .foregroundStyle(Theme.Palette.ink)
                .textInputAutocapitalization(.words)
                .padding(.horizontal, 14)
                .frame(minHeight: 50)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Metric.buttonRadius, style: .continuous)
                        .fill(Color(hex: 0xFFFAF4))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Metric.buttonRadius, style: .continuous)
                        .stroke(Theme.Palette.hairline, lineWidth: 1)
                )
        }
        .padding(.top, 18)
    }
}
