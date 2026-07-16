import Foundation
import Testing
@testable import tunedIn

struct SupabaseEventDiaryContractTests {
  @Test
  func phaseFourCapabilitiesAddPersonalMemories() {
    let capabilities = EventRepositoryCapabilities.phase4Memories

    #expect(capabilities.contains(.discovery))
    #expect(capabilities.contains(.plans))
    #expect(capabilities.contains(.attendance))
    #expect(capabilities.contains(.conversation))
    #expect(capabilities.contains(.invitations))
    #expect(capabilities.contains(.diaries))
  }

  @Test
  func diaryAndProfileParametersUseExactRPCContractKeys() throws {
    let eventID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    let profileID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
    let diaries = try encodedObject(ListCatalogEventDiariesParameters(eventID: eventID))
    let save = try encodedObject(UpsertCatalogEventDiaryParameters(
      eventID: eventID,
      input: EventDiaryInput(
        score: 9.5,
        performanceScore: 9,
        note: "  What a closer.  ",
        audience: .friends
      )
    ))
    let profile = try encodedObject(CatalogEventProfileHistoryParameters(profileID: profileID))
    let going = try encodedObject(CatalogEventProfileAttendanceParameters(
      profileID: profileID,
      state: .going
    ))
    let draft = try encodedObject(UpsertCatalogEventDiaryParameters(
      eventID: eventID,
      input: EventDiaryInput(
        score: nil,
        performanceScore: nil,
        note: nil,
        audience: .friends
      ),
      publish: false
    ))

    #expect(Set(diaries.keys) == ["p_event_id", "p_scope", "p_limit"])
    #expect(diaries["p_event_id"] as? String == eventID.uuidString)
    #expect(diaries["p_scope"] as? String == "all")
    #expect(diaries["p_limit"] as? Int == 30)
    #expect(Set(save.keys) == [
      "p_event_id", "p_overall_score", "p_performance_score", "p_review_body", "p_audience", "p_publish"
    ])
    #expect(save["p_overall_score"] as? Double == 9.5)
    #expect(save["p_performance_score"] as? Double == 9)
    #expect(save["p_review_body"] as? String == "What a closer.")
    #expect(save["p_audience"] as? String == "friends")
    #expect(save["p_publish"] as? Bool == true)
    #expect(Set(profile.keys) == ["p_profile_id", "p_limit"])
    #expect(profile["p_profile_id"] as? String == profileID.uuidString)
    #expect(Set(going.keys) == ["p_profile_id", "p_state", "p_limit"])
    #expect(going["p_state"] as? String == "going")
    #expect(draft["p_publish"] as? Bool == false)
  }

  @Test
  func diaryRecordPreservesScoresContentCountsAndAudience() throws {
    let record = try JSONDecoder().decode(CatalogEventDiaryRPCRecord.self, from: Data(diaryJSON.utf8))
    let diary = try EventDiaryPreview(databaseRecord: record)

    #expect(diary.id == UUID(uuidString: "30000000-0000-0000-0000-000000000001"))
    #expect(diary.author.relationship == .friends)
    #expect(diary.score == 9.5)
    #expect(diary.performanceScore == 9)
    #expect(diary.note == "What a closer.")
    #expect(diary.photoCount == 4)
    #expect(diary.videoCount == 1)
    #expect(diary.commentCount == 3)
    #expect(diary.audience == .friends)
  }

  @Test
  func profileHistoryAndSummaryRecordsMapWentAndDiarySections() throws {
    let historyData = Data(
      """
      {
        "history_kind":"diary",
        "event":\(eventJSON),
        "diary":\(diaryJSON),
        "occurred_at":"2026-07-16T20:00:00Z"
      }
      """.utf8
    )
    let history = try JSONDecoder().decode(CatalogEventProfileHistoryRPCRecord.self, from: historyData)
    let summaryRecord = try JSONDecoder().decode(
      CatalogEventDiarySummaryRPCRecord.self,
      from: Data(
        #"{"event_id":"50000000-0000-0000-0000-000000000001","diary_count":2,"average_score":9.25}"#.utf8
      )
    )
    let event = try CommunityEventSummary(databaseRecord: history.event, diaryRecord: summaryRecord)

    #expect(history.historyKind == "diary")
    #expect(history.diary?.overallScore == 9.5)
    #expect(history.occurredAt == "2026-07-16T20:00:00Z")
    #expect(summaryRecord.averageScore == 9.25)
    #expect(event.diaryCount == 2)
    #expect(event.averageDiaryScore == 9.25)
  }

  @Test
  func activityAndProfileAttendanceCarryDiaryAndGoingDestinations() throws {
    let activityData = Data(
      """
      {
        "activity_id":"90000000-0000-0000-0000-000000000001",
        "action":"diary_published",
        "actor_id":"20000000-0000-0000-0000-000000000001",
        "actor_username":"morgan",
        "actor_display_name":"Morgan",
        "actor_relationship":"friends",
        "actor_avatar_object_path":null,
        "actor_avatar_version":2,
        "subject_id":"30000000-0000-0000-0000-000000000001",
        "diary":\(diaryJSON),
        "event":\(eventJSON),
        "occurred_at":"2026-07-16T20:00:00Z"
      }
      """.utf8
    )
    let attendanceData = Data(
      """
      {
        "attendance_id":"91000000-0000-0000-0000-000000000001",
        "event":\(eventJSON),
        "status":"going",
        "audience":"friends",
        "occurred_at":"2026-07-16T20:00:00Z"
      }
      """.utf8
    )
    let activityRecord = try JSONDecoder().decode(CatalogEventActivityRPCRecord.self, from: activityData)
    let attendance = try JSONDecoder().decode(
      CatalogEventProfileAttendanceRPCRecord.self,
      from: attendanceData
    )
    let event = try CommunityEventSummary(databaseRecord: activityRecord.event)
    let activity = try EventActivity(databaseRecord: activityRecord, event: event)

    #expect(activity.diary?.id == activityRecord.subjectID)
    #expect(activity.diary?.photoCount == 4)
    #expect(attendance.status == .going)
    #expect(attendance.event.eventID == event.id)
  }

  private var diaryJSON: String {
    #"""
    {
      "diary_id":"30000000-0000-0000-0000-000000000001",
      "author_id":"20000000-0000-0000-0000-000000000001",
      "author_username":"morgan",
      "author_display_name":"Morgan",
      "author_relationship":"friends",
      "author_avatar_object_path":null,
      "author_avatar_version":2,
      "overall_score":9.5,
      "performance_score":9.0,
      "review_body":"What a closer.",
      "photo_count":4,
      "video_count":1,
      "comment_count":3,
      "audience":"friends",
      "published_at":"2026-07-16T20:00:00Z"
    }
    """#
  }

  private var eventJSON: String {
    #"""
    {
      "event_id":"50000000-0000-0000-0000-000000000001",
      "artists":[{
        "catalog_artist_id":"60000000-0000-0000-0000-000000000001",
        "display_name":"Mitski",
        "position":0,
        "is_headliner":true
      }],
      "catalog_place_id":"70000000-0000-0000-0000-000000000001",
      "catalog_area_id":"80000000-0000-0000-0000-000000000001",
      "catalog_tour_id":null,
      "venue_name":"The Anthem",
      "area_name":"Washington, D.C.",
      "event_date":"2026-07-15",
      "starts_at":"2026-07-15T23:30:00Z",
      "time_zone_identifier":"America/New_York",
      "memory_unlock_at":"2026-07-16T08:00:00Z",
      "lifecycle":"completed",
      "listing":"listed",
      "integrity":"community_added",
      "row_state":"active",
      "source_label":"Community made"
    }
    """#
  }

  private func encodedObject(_ value: some Encodable) throws -> [String: Any] {
    let data = try JSONEncoder().encode(value)
    return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
  }
}
