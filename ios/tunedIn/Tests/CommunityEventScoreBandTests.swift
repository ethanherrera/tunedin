import Testing
@testable import tunedIn

struct CommunityEventScoreBandTests {
  @Test
  func mapsTenPointScoresToStableSemanticBands() {
    #expect(CommunityEventScoreBand(score: 0.5) == .red)
    #expect(CommunityEventScoreBand(score: 4.5) == .red)
    #expect(CommunityEventScoreBand(score: 5) == .yellow)
    #expect(CommunityEventScoreBand(score: 7.5) == .yellow)
    #expect(CommunityEventScoreBand(score: 8) == .green)
    #expect(CommunityEventScoreBand(score: 10) == .green)
  }
}
