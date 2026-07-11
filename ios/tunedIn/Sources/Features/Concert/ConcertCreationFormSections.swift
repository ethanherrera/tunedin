import SwiftUI

extension ConcertCreationView {
  var essentialsSection: some View {
    Section {
      TunedInFormCard {
        Text("The essentials")
          .font(.headline)

        VStack(alignment: .leading, spacing: 8) {
          Text("Venue")
            .font(.subheadline.weight(.medium))
          TextField("Where was the show?", text: $draft.venueName)
            .textContentType(.location)
            .submitLabel(.next)
            .accessibilityLabel("Venue")

          if draft.hasAttemptedSave, !ConcertInput.isValidRequiredText(draft.venueName, maximumLength: 160) {
            validationLabel("Enter a venue name of up to 160 characters.")
          }
        }

        Divider()

        DatePicker("Concert date", selection: $draft.concertDate, displayedComponents: .date)
          .datePickerStyle(.compact)
      }
      .listRowBackground(Color.clear)
      .listRowSeparator(.hidden)
    }
  }

  var lineupSection: some View {
    Section {
      TunedInFormCard {
        HStack(alignment: .firstTextBaseline) {
          VStack(alignment: .leading, spacing: 3) {
            Text("Lineup")
              .font(.headline)
            Text("Choose one headliner. Order reflects the bill.")
              .font(.caption)
              .foregroundStyle(.secondary)
          }

          Spacer()

          Text("\(draft.artists.count)/10")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }

        ForEach(draft.artists) { artist in
          VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
              TextField("Artist", text: artistNameBinding(for: artist.id))
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

            if draft.hasAttemptedSave, !ConcertInput.isValidRequiredText(artist.name, maximumLength: 160) {
              validationLabel("Enter an artist name of up to 160 characters.")
            }
          }
          .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if draft.artists.count > 1 {
              Button(role: .destructive) {
                draft.removeArtist(artist.id)
              } label: {
                Label("Remove", systemImage: "trash")
              }
            }
          }
        }
        .onMove { source, destination in
          draft.moveArtists(from: source, to: destination)
        }

        Button {
          draft.addArtist()
        } label: {
          Label("Add artist", systemImage: "plus")
        }
        .disabled(draft.artists.count == 10)
      }
      .listRowBackground(Color.clear)
      .listRowSeparator(.hidden)
    }
  }

  var detailsSection: some View {
    Section {
      TunedInFormCard {
        Text("Details")
          .font(.headline)

        TextField("City (optional)", text: $draft.city)
          .textContentType(.addressCity)
          .accessibilityLabel("City, optional")

        if draft.hasAttemptedSave, !ConcertInput.isValidOptionalText(draft.city, maximumLength: 100) {
          validationLabel("City can be up to 100 characters.")
        }

        DisclosureGroup("Tour (optional)", isExpanded: $draft.isTourExpanded) {
          TextField("Tour name", text: $draft.tour)
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
        }
      }
      .listRowBackground(Color.clear)
      .listRowSeparator(.hidden)
    } footer: {
      if draft.hasStartTime {
        Text("The app saves the ticket’s venue-local date and time zone, then stores the start time as UTC.")
      }
    }
  }

  var setlistSection: some View {
    Section {
      TunedInFormCard {
        HStack(alignment: .firstTextBaseline) {
          VStack(alignment: .leading, spacing: 3) {
            Text("Setlist")
              .font(.headline)
            Text("Optional — drag to reorder.")
              .font(.caption)
              .foregroundStyle(.secondary)
          }

          Spacer()

          Text("\(draft.setlist.count)/50")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
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
          Label("Add song", systemImage: "plus")
        }
        .disabled(draft.setlist.count == 50)
      }
      .listRowBackground(Color.clear)
      .listRowSeparator(.hidden)
    }
  }

  var visibilitySection: some View {
    Section {
      TunedInFormCard {
        Label("Private", systemImage: "lock.fill")
          .font(.headline)
          .foregroundStyle(TunedInDesign.accent)

        Text("Only you can see this concert. Sharing and collaborators come later.")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      .listRowBackground(Color.clear)
      .listRowSeparator(.hidden)
    }
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
