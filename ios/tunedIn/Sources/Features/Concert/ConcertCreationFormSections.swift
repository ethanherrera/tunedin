import SwiftUI

extension ConcertCreationView {
  var introductionSection: some View {
    Section {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Text("tunedIn")
            .font(.subheadline.weight(.black))
            .foregroundStyle(TunedInDesign.accent)

          Spacer()

          TunedInPrivacyBadge()
        }

        Text("Keep the night.")
          .font(.system(size: 38, weight: .bold, design: .serif))
          .foregroundStyle(.white)

        Text("The show is still ringing. Catch the feeling before it fades.")
          .font(.subheadline)
          .foregroundStyle(TunedInDesign.mutedText)
      }
      .padding(.top, 18)
      .padding(.bottom, 6)
      .listRowBackground(TunedInDesign.pageBackground)
      .listRowInsets(EdgeInsets(top: 0, leading: 24, bottom: 0, trailing: 24))
      .listRowSeparator(.hidden)
    }
  }

  var quickCaptureSection: some View {
    Section {
      TunedInTicketCard {
        Text("The quick capture")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.white.opacity(0.82))
          .textCase(.uppercase)

        VStack(alignment: .leading, spacing: 6) {
          Text("Who did you see?")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white)

          TextField(
            "",
            text: artistNameBinding(for: draft.artists[0].id),
            prompt: Text("Artist").foregroundStyle(.white.opacity(0.54))
          )
          .font(.title2.weight(.semibold))
          .foregroundStyle(.white)
          .tint(.white)
          .textInputAutocapitalization(.words)
          .submitLabel(.next)
          .accessibilityLabel("Primary artist")

          if draft.hasAttemptedSave, !ConcertInput.isValidRequiredText(
            draft.artists[0].name,
            maximumLength: 160
          ) {
            validationLabel("Enter the artist you saw.")
          }
        }

        Divider().overlay(.white.opacity(0.24))

        VStack(alignment: .leading, spacing: 6) {
          Text("Where was it?")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white)

          TextField(
            "",
            text: $draft.venueName,
            prompt: Text("Venue").foregroundStyle(.white.opacity(0.54))
          )
          .font(.title3.weight(.medium))
          .foregroundStyle(.white)
          .tint(.white)
          .textContentType(.location)
          .textInputAutocapitalization(.words)
          .submitLabel(.done)
          .accessibilityLabel("Venue")

          if draft.hasAttemptedSave, !ConcertInput.isValidRequiredText(
            draft.venueName,
            maximumLength: 160
          ) {
            validationLabel("Enter the venue.")
          }
        }

        Divider().overlay(.white.opacity(0.24))

        HStack {
          Label("When", systemImage: "calendar")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white)
          Spacer()
          DatePicker("Concert date", selection: $draft.concertDate, displayedComponents: .date)
            .datePickerStyle(.compact)
            .labelsHidden()
            .tint(.white)
        }
      }
      .listRowBackground(TunedInDesign.pageBackground)
      .listRowInsets(EdgeInsets(top: 14, leading: 20, bottom: 0, trailing: 20))
      .listRowSeparator(.hidden)
    }
  }

  var personalizationSection: some View {
    Section {
      Button {
        withAnimation(.snappy) {
          isShowingDetails.toggle()
        }
      } label: {
        HStack(spacing: 14) {
          Image(systemName: "sparkles")
            .font(.title3)
            .foregroundStyle(TunedInDesign.accent)
            .frame(width: 34, height: 34)
            .background(TunedInDesign.accentTint, in: Circle())

          VStack(alignment: .leading, spacing: 2) {
            Text(isShowingDetails ? "Make it yours" : "Add details")
              .font(.headline)
              .foregroundStyle(.white)
            Text(isShowingDetails ? "Lineup, setlist, time, and more" : "Only if you feel like it")
              .font(.caption)
              .foregroundStyle(TunedInDesign.mutedText)
          }

          Spacer()

          Image(systemName: isShowingDetails ? "chevron.up" : "chevron.down")
            .font(.caption.weight(.bold))
            .foregroundStyle(TunedInDesign.mutedText)
        }
        .padding(.vertical, 7)
      }
      .buttonStyle(.plain)
      .listRowBackground(TunedInDesign.pageBackground)
      .listRowInsets(EdgeInsets(top: 16, leading: 24, bottom: 6, trailing: 24))
      .listRowSeparator(.hidden)

      if isShowingDetails {
        lineupDetailsCard
        contextDetailsCard
        setlistDetailsCard
      }
    }
  }

  private var lineupDetailsCard: some View {
    TunedInFormCard {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 3) {
          Text("Lineup")
            .font(.headline)
            .foregroundStyle(.white)
          Text("Choose one headliner. The order is the bill.")
            .font(.caption)
            .foregroundStyle(TunedInDesign.mutedText)
        }

        Spacer()

        Text("\(draft.artists.count)/10")
          .font(.caption.monospacedDigit())
          .foregroundStyle(TunedInDesign.mutedText)
      }

      ForEach(draft.artists.dropFirst()) { artist in
        HStack(spacing: 10) {
          TextField("Another artist", text: artistNameBinding(for: artist.id))
            .accessibilityLabel("Artist name")

          Button {
            draft.makePrimary(artist.id)
          } label: {
            Text(artist.isPrimary ? "Headliner" : "Make headliner")
              .font(.caption.weight(.semibold))
          }
          .buttonStyle(.bordered)
          .tint(artist.isPrimary ? TunedInDesign.accent : .secondary)
          .accessibilityLabel(artist.isPrimary ? "Headliner" : "Make this artist the headliner")
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
          Button(role: .destructive) {
            draft.removeArtist(artist.id)
          } label: {
            Label("Remove", systemImage: "trash")
          }
        }
      }
      .onMove { source, destination in
        let adjustedSource = IndexSet(source.map { $0 + 1 })
        draft.moveArtists(from: adjustedSource, to: destination + 1)
      }

      Button {
        draft.addArtist()
      } label: {
        Label("Add another artist", systemImage: "plus")
      }
      .disabled(draft.artists.count == 10)
    }
    .listRowBackground(TunedInDesign.pageBackground)
    .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 0, trailing: 20))
    .listRowSeparator(.hidden)
  }

  private var contextDetailsCard: some View {
    TunedInFormCard {
      Text("The context")
        .font(.headline)
        .foregroundStyle(.white)

      TextField("City (optional)", text: $draft.city)
        .textContentType(.addressCity)
        .textInputAutocapitalization(.words)
        .accessibilityLabel("City, optional")

      if draft.hasAttemptedSave, !ConcertInput.isValidOptionalText(draft.city, maximumLength: 100) {
        validationLabel("City can be up to 100 characters.")
      }

      DisclosureGroup("Tour (optional)", isExpanded: $draft.isTourExpanded) {
        TextField("Tour name", text: $draft.tour)
          .textInputAutocapitalization(.words)
          .accessibilityLabel("Tour name, optional")
          .padding(.top, 8)
      }

      if draft.hasAttemptedSave, !ConcertInput.isValidOptionalText(draft.tour, maximumLength: 160) {
        validationLabel("Tour can be up to 160 characters.")
      }

      Toggle("Add start time", isOn: $draft.hasStartTime)

      if draft.hasStartTime {
        DatePicker("Start time", selection: $draft.startTime, displayedComponents: .hourAndMinute)

        Picker("Venue time zone", selection: $draft.venueTimeZoneIdentifier) {
          ForEach(TimeZone.knownTimeZoneIdentifiers.sorted(), id: \.self) { identifier in
            Text(identifier).tag(identifier)
          }
        }
        .pickerStyle(.navigationLink)

        Text("The time is saved in the venue’s time zone.")
          .font(.caption)
          .foregroundStyle(TunedInDesign.mutedText)
      }
    }
    .listRowBackground(TunedInDesign.pageBackground)
    .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 0, trailing: 20))
    .listRowSeparator(.hidden)
  }

  private var setlistDetailsCard: some View {
    TunedInFormCard {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 3) {
          Text("Setlist")
            .font(.headline)
            .foregroundStyle(.white)
          Text("Add every song, or leave it as a feeling.")
            .font(.caption)
            .foregroundStyle(TunedInDesign.mutedText)
        }

        Spacer()

        Text("\(draft.setlist.count)/50")
          .font(.caption.monospacedDigit())
          .foregroundStyle(TunedInDesign.mutedText)
      }

      ForEach(draft.setlist) { item in
        TextField("Song title", text: setlistTitleBinding(for: item.id))
          .accessibilityLabel("Setlist song title")
          .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
              draft.removeSetlistItem(item.id)
            } label: {
              Label("Remove", systemImage: "trash")
            }
          }
      }
      .onMove { source, destination in
        draft.moveSetlist(from: source, to: destination)
      }

      Button {
        draft.addSetlistItem()
      } label: {
        Label("Add a song", systemImage: "plus")
      }
      .disabled(draft.setlist.count == 50)
    }
    .listRowBackground(TunedInDesign.pageBackground)
    .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20))
    .listRowSeparator(.hidden)
  }

  func validationLabel(_ message: String) -> some View {
    Label(message, systemImage: "exclamationmark.circle.fill")
      .font(.caption)
      .foregroundStyle(.red)
  }

  func artistNameBinding(for id: UUID) -> Binding<String> {
    Binding(
      get: { draft.artists.first(where: { $0.id == id })?.name ?? "" },
      set: { value in
        guard let index = draft.artists.firstIndex(where: { $0.id == id }) else { return }
        draft.artists[index].name = value
      }
    )
  }

  func setlistTitleBinding(for id: UUID) -> Binding<String> {
    Binding(
      get: { draft.setlist.first(where: { $0.id == id })?.title ?? "" },
      set: { value in
        guard let index = draft.setlist.firstIndex(where: { $0.id == id }) else { return }
        draft.setlist[index].title = value
      }
    )
  }
}
