import Foundation
import Testing
@testable import tunedIn

struct SupabaseEventRepositoryContractTests {
  @Test
  func phaseThreeCapabilitiesAddTheSocialLoopWithoutDiaries() {
    let capabilities = EventRepositoryCapabilities.phase3Social

    #expect(capabilities.contains(.discovery))
    #expect(capabilities.contains(.plans))
    #expect(capabilities.contains(.attendance))
    #expect(capabilities.contains(.activityFeed))
    #expect(capabilities.contains(.conversation))
    #expect(capabilities.contains(.invitations))
    #expect(!capabilities.contains(.diaries))
  }

  @Test
  func phaseTwoCapabilitiesExposeDiscoveryPlansAndAttendanceOnly() {
    let repository = PhaseTwoEventRepositoryDouble()

    #expect(repository.capabilities == .phase2Attendance)
    #expect(repository.capabilities.contains(.discovery))
    #expect(repository.capabilities.contains(.plans))
    #expect(repository.capabilities.contains(.attendance))
    #expect(!repository.capabilities.contains(.conversation))
    #expect(!repository.capabilities.contains(.invitations))
    #expect(!repository.capabilities.contains(.diaries))
  }

  @Test
  func searchAndDetailParametersUseExactRPCContractKeys() throws {
    let eventID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    let search = try encodedObject(
      SearchCatalogEventsParameters(query: "Mitski", filters: ["phase": "upcoming"], limit: 25)
    )
    let detail = try encodedObject(CatalogEventIDParameters(eventID: eventID))

    #expect(Set(search.keys) == ["p_query", "p_filters", "p_limit"])
    #expect(search["p_query"] as? String == "Mitski")
    #expect(search["p_filters"] as? [String: String] == ["phase": "upcoming"])
    #expect(search["p_limit"] as? Int == 25)
    #expect(Set(detail.keys) == ["p_event_id"])
    #expect(detail["p_event_id"] as? String == eventID.uuidString)
  }

  @Test
  func attendanceAndPlansParametersUseExactRPCContractKeys() throws {
    let eventID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    let otherEventID = UUID(uuidString: "10000000-0000-0000-0000-000000000002")!
    let summaries = try encodedObject(
      CatalogEventSocialSummariesParameters(eventIDs: [eventID, otherEventID])
    )
    let attendees = try encodedObject(ListCatalogEventAttendeesParameters(eventID: eventID))
    let plans = try encodedObject(CatalogEventPageParameters(limit: 25))
    let attendance = try encodedObject(SetCatalogEventAttendanceParameters(
      eventID: eventID,
      status: .going,
      audience: .friends
    ))
    let cleared = try encodedObject(SetCatalogEventAttendanceParameters(
      eventID: eventID,
      status: nil,
      audience: .community
    ))

    #expect(Set(summaries.keys) == ["p_event_ids"])
    #expect((summaries["p_event_ids"] as? [String]) == [eventID.uuidString, otherEventID.uuidString])
    #expect(Set(attendees.keys) == ["p_event_id", "p_scope", "p_limit"])
    #expect(attendees["p_scope"] as? String == "all")
    #expect(Set(plans.keys) == ["p_limit"])
    #expect(plans["p_limit"] as? Int == 25)
    #expect(Set(attendance.keys) == ["p_event_id", "p_status", "p_audience"])
    #expect(attendance["p_status"] as? String == "going")
    #expect(attendance["p_audience"] as? String == "friends")
    #expect(Set(cleared.keys) == ["p_event_id", "p_audience"])
  }
}

struct SupabaseEventSocialContractTests {
  @Test
  func conversationAndInvitationParametersUseExactRPCContractKeys() throws {
    let eventID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    let postID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
    let friendID = UUID(uuidString: "30000000-0000-0000-0000-000000000001")!
    let invitationID = UUID(uuidString: "40000000-0000-0000-0000-000000000001")!
    let posts = try encodedObject(ListCatalogEventPostsParameters(eventID: eventID))
    let create = try encodedObject(CreateCatalogEventPostParameters(
      eventID: eventID,
      parentPostID: postID,
      body: "Can’t wait",
      audience: .friends
    ))
    let send = try encodedObject(SendCatalogEventInvitationsParameters(
      eventID: eventID,
      recipientIDs: [friendID]
    ))
    let respond = try encodedObject(RespondCatalogEventInvitationParameters(
      invitationID: invitationID,
      response: .accepted,
      audience: .friends
    ))

    #expect(Set(posts.keys) == ["p_event_id", "p_scope", "p_limit"])
    #expect(posts["p_scope"] as? String == "all")
    #expect(Set(create.keys) == ["p_event_id", "p_parent_post_id", "p_body", "p_audience"])
    #expect(create["p_parent_post_id"] as? String == postID.uuidString)
    #expect(create["p_audience"] as? String == "friends")
    #expect(Set(send.keys) == ["p_event_id", "p_recipient_ids"])
    #expect(send["p_recipient_ids"] as? [String] == [friendID.uuidString])
    #expect(Set(respond.keys) == ["p_invitation_id", "p_response", "p_audience"])
    #expect(respond["p_response"] as? String == "accepted")
  }

  @Test
  func conversationRecordPreservesReplyAndDeletionState() throws {
    let data = Data(
      #"""
      {
        "id":"50000000-0000-0000-0000-000000000001",
        "parent_post_id":"50000000-0000-0000-0000-000000000000",
        "author_id":"60000000-0000-0000-0000-000000000001",
        "author_username":"morgan",
        "author_display_name":"Morgan",
        "author_relationship":"friends",
        "author_avatar_object_path":null,
        "author_avatar_version":0,
        "body":"Post deleted",
        "audience":"friends",
        "created_at":"2026-07-16T20:00:00Z",
        "is_deleted":true
      }
      """#.utf8
    )
    let record = try JSONDecoder().decode(CatalogEventPostRPCRecord.self, from: data)
    let post = try EventPost(databaseRecord: record)

    #expect(post.parentPostID == UUID(uuidString: "50000000-0000-0000-0000-000000000000"))
    #expect(post.author.relationship == .friends)
    #expect(post.isDeleted)
  }

  @Test
  func invitationRecordCarriesACompleteEventCard() throws {
    let data = Data(
      #"""
      {
        "invitation_id":"70000000-0000-0000-0000-000000000001",
        "event_id":"50000000-0000-0000-0000-000000000001",
        "event":{
          "event_id":"50000000-0000-0000-0000-000000000001",
          "artists":[{
            "catalog_artist_id":"20000000-0000-0000-0000-000000000001",
            "display_name":"Mitski",
            "position":0,
            "is_headliner":true
          }],
          "catalog_place_id":"30000000-0000-0000-0000-000000000001",
          "catalog_area_id":"40000000-0000-0000-0000-000000000001",
          "catalog_tour_id":null,
          "venue_name":"The Anthem",
          "area_name":"Washington, D.C.",
          "event_date":"2026-09-17",
          "starts_at":"2026-09-17T23:30:00Z",
          "time_zone_identifier":"America/New_York",
          "memory_unlock_at":"2026-09-18T08:00:00Z",
          "lifecycle":"scheduled",
          "listing":"unlisted",
          "integrity":"community_added",
          "row_state":"active",
          "source_label":"Community made"
        },
        "sender_id":"60000000-0000-0000-0000-000000000001",
        "sender_username":"morgan",
        "sender_display_name":"Morgan",
        "sender_relationship":"friends",
        "sender_avatar_object_path":null,
        "sender_avatar_version":0,
        "created_at":"2026-07-16T20:00:00Z"
      }
      """#.utf8
    )
    let record = try JSONDecoder().decode(CatalogEventInvitationRPCRecord.self, from: data)
    let summary = try CommunityEventSummary(databaseRecord: record.event)
    let invitation = try EventInvitation(databaseRecord: record, event: summary)

    #expect(invitation.event.id == record.eventID)
    #expect(invitation.event.listing == .unlisted)
    #expect(invitation.sender.relationship == .friends)
  }

  private func encodedObject(_ value: some Encodable) throws -> [String: Any] {
    let data = try JSONEncoder().encode(value)
    return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
  }
}

extension SupabaseEventRepositoryContractTests {
  @Test
  func creationParametersUseCatalogIDsAndVenueLocalDate() throws {
    let artistID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
    let placeID = UUID(uuidString: "30000000-0000-0000-0000-000000000001")!
    let areaID = UUID(uuidString: "40000000-0000-0000-0000-000000000001")!
    let instant = try #require(CommunityEventDateCoding.dateTime(from: "2026-07-17T02:30:00Z"))
    let input = CommunityEventCreationInput(
      artists: [artist(id: artistID, name: "Mitski")],
      place: place(id: placeID, areaID: areaID),
      tour: nil,
      eventDate: instant,
      startsAt: nil,
      timeZoneIdentifier: "America/New_York",
      listing: .listed
    )

    let object = try encodedObject(CreateCatalogEventParameters(input: input))
    let duplicateLookup = try encodedObject(FindEventDuplicateCandidatesParameters(input: input))
    let artists = try #require(object["p_artists"] as? [[String: Any]])

    #expect(Set(object.keys) == [
      "p_artists", "p_catalog_place_id", "p_event_date", "p_time_zone_identifier", "p_listing"
    ])
    #expect(object["p_catalog_place_id"] as? String == placeID.uuidString)
    #expect(object["p_event_date"] as? String == "2026-07-16")
    #expect(object["p_time_zone_identifier"] as? String == "America/New_York")
    #expect(object["p_listing"] as? String == "listed")
    #expect(artists.count == 1)
    #expect(artists.first?["catalog_artist_id"] as? String == artistID.uuidString)
    #expect(artists.first?["is_primary"] as? Bool == true)
    #expect(Set(duplicateLookup.keys) == [
      "p_artists", "p_catalog_place_id", "p_event_date", "p_time_zone_identifier",
      "p_listing", "p_limit"
    ])
    #expect(duplicateLookup["p_limit"] as? Int == 5)
  }

  @Test
  func cancellationConfirmationAndReportsUseBoundedRPCInputs() throws {
    let eventID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    let confirmation = try encodedObject(ConfirmCancelledPerformanceParameters(
      eventID: eventID,
      audience: .privateOnly
    ))
    let report = try encodedObject(ReportCatalogEventParameters(
      eventID: eventID,
      reason: .sensitiveLocation,
      note: "  Please review this location.  "
    ))

    #expect(Set(confirmation.keys) == ["p_event_id", "p_audience"])
    #expect(confirmation["p_audience"] as? String == "private")
    #expect(Set(report.keys) == ["p_event_id", "p_reason", "p_note"])
    #expect(report["p_reason"] as? String == "sensitive_location")
    #expect(report["p_note"] as? String == "Please review this location.")
  }

  @Test
  func eventRecordMapsBackendSnapshotsWithoutProviderData() throws {
    let data = Data(
      #"""
      {
        "event_id":"50000000-0000-0000-0000-000000000001",
        "artists":[
          {
            "catalog_artist_id":"20000000-0000-0000-0000-000000000001",
            "display_name":"Mitski",
            "position":0,
            "is_headliner":true
          }
        ],
        "catalog_place_id":"30000000-0000-0000-0000-000000000001",
        "catalog_area_id":"40000000-0000-0000-0000-000000000001",
        "catalog_tour_id":null,
        "venue_name":"The Anthem",
        "area_name":"Washington, D.C.",
        "event_date":"2026-09-17",
        "starts_at":"2026-09-17T23:30:00Z",
        "time_zone_identifier":"America/New_York",
        "memory_unlock_at":"2026-09-18T08:00:00Z",
        "lifecycle":"scheduled",
        "listing":"listed",
        "integrity":"community_added",
        "row_state":"active",
        "source_label":"Community made"
      }
      """#.utf8
    )
    let record = try JSONDecoder().decode(CatalogEventRPCRecord.self, from: data)
    let summary = try CommunityEventSummary(databaseRecord: record)

    #expect(summary.id == UUID(uuidString: "50000000-0000-0000-0000-000000000001"))
    #expect(summary.title == "Mitski")
    #expect(summary.venueName == "The Anthem")
    #expect(summary.areaName == "Washington, D.C.")
    #expect(summary.timeZoneIdentifier == "America/New_York")
    #expect(summary.sourceLabel == "Community made")
    #expect(summary.currentUserAttendance == nil)
    #expect(summary.friendPreviews.isEmpty)
    #expect(summary.publicGoingCount == 0)
    #expect(summary.diaryCount == 0)
    #expect(summary.averageDiaryScore == nil)
  }

  @Test
  func viewerSpecificSocialRecordsEnrichEventAndAttendeeModels() throws {
    let eventData = Data(
      #"""
      {
        "event_id":"50000000-0000-0000-0000-000000000001",
        "artists":[{
          "catalog_artist_id":"20000000-0000-0000-0000-000000000001",
          "display_name":"Mitski",
          "position":0,
          "is_headliner":true
        }],
        "catalog_place_id":"30000000-0000-0000-0000-000000000001",
        "catalog_area_id":"40000000-0000-0000-0000-000000000001",
        "catalog_tour_id":null,
        "venue_name":"The Anthem",
        "area_name":"Washington, D.C.",
        "event_date":"2026-09-17",
        "starts_at":"2026-09-17T23:30:00Z",
        "time_zone_identifier":"America/New_York",
        "memory_unlock_at":"2026-09-18T08:00:00Z",
        "lifecycle":"scheduled",
        "listing":"listed",
        "integrity":"community_added",
        "row_state":"active",
        "source_label":"Community made"
      }
      """#.utf8
    )
    let socialData = Data(
      #"""
      {
        "event_id":"50000000-0000-0000-0000-000000000001",
        "current_user_status":"going",
        "current_user_audience":"friends",
        "friend_previews":[{
          "profile_id":"60000000-0000-0000-0000-000000000001",
          "username":"morgan",
          "display_name":"Morgan",
          "relationship":"friends",
          "avatar_object_path":null,
          "avatar_version":0,
          "status":"going"
        }],
        "community_going_count":7,
        "community_went_count":0
      }
      """#.utf8
    )
    let attendeeData = Data(
      #"""
      {
        "id":"60000000-0000-0000-0000-000000000001",
        "username":"morgan",
        "display_name":"Morgan",
        "relationship":"friends",
        "avatar_object_path":null,
        "avatar_version":0,
        "status":"going",
        "audience":"community",
        "updated_at":"2026-07-16T20:00:00Z",
        "next_cursor":{
          "updated_at":"2026-07-16T20:00:00Z",
          "profile_id":"60000000-0000-0000-0000-000000000001"
        }
      }
      """#.utf8
    )
    let record = try JSONDecoder().decode(CatalogEventRPCRecord.self, from: eventData)
    let social = try JSONDecoder().decode(CatalogEventSocialSummaryRPCRecord.self, from: socialData)
    let attendeeRecord = try JSONDecoder().decode(CatalogEventAttendeeRPCRecord.self, from: attendeeData)
    let summary = try CommunityEventSummary(databaseRecord: record, socialRecord: social)
    let attendee = try EventAttendance(databaseRecord: attendeeRecord)

    #expect(summary.currentUserAttendance == .going)
    #expect(summary.currentUserAudience == .friends)
    #expect(summary.friendPreviews.map(\.profile.username) == ["morgan"])
    #expect(summary.publicGoingCount == 7)
    #expect(attendee.profile.relationship == .friends)
    #expect(attendee.audience == .community)
    #expect(attendeeRecord.nextCursor?.profileID == attendee.id)
  }

  @Test
  func changingVenueTimeZonePreservesTheEnteredWallClockTime() throws {
    let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))
    let newYork = try #require(TimeZone(identifier: "America/New_York"))
    let original = try #require(CommunityEventDateCoding.dateTime(from: "2026-09-18T02:30:00Z"))

    let shifted = CommunityEventDateCoding.preservingWallClockTime(
      original,
      from: losAngeles,
      to: newYork
    )

    #expect(CommunityEventDateCoding.dateTimeString(shifted) == "2026-09-17T23:30:00.000Z")
  }

  private func encodedObject(_ value: some Encodable) throws -> [String: Any] {
    let data = try JSONEncoder().encode(value)
    return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
  }

  private func artist(id: UUID, name: String) -> CatalogArtist {
    CatalogArtist(
      id: id,
      origin: .musicBrainz,
      musicBrainzID: UUID(),
      displayName: name,
      sortName: name,
      disambiguation: nil,
      subtitle: nil,
      artistType: "Person",
      areaID: nil,
      areaName: nil
    )
  }

  private func place(id: UUID, areaID: UUID) -> CatalogPlace {
    CatalogPlace(
      id: id,
      origin: .musicBrainz,
      musicBrainzID: UUID(),
      displayName: "The Anthem",
      sortName: "The Anthem",
      disambiguation: nil,
      subtitle: "Washington, D.C.",
      placeType: "Venue",
      address: nil,
      areaID: areaID,
      areaName: "Washington, D.C."
    )
  }
}

private struct PhaseTwoEventRepositoryDouble: EventRepository {
  let capabilities = EventRepositoryCapabilities.phase2Attendance

  func searchEvents(query _: String, viewerID _: UUID) async throws -> [CommunityEventSummary] {
    []
  }

  func eventDetail(id _: UUID, viewerID _: UUID) async throws -> CommunityEventDetail {
    throw CommunityEventError.eventUnavailable
  }

  func createEvent(
    _ input: CommunityEventCreationInput,
    creatorID _: UUID
  ) async throws -> CommunityEventDetail {
    throw CommunityEventError.invalidEvent(input.artists.isEmpty ? "Artist required" : "Test only")
  }
}
