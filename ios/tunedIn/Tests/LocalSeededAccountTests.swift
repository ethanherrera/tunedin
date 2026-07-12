import Testing
@testable import tunedIn

struct LocalSeededAccountTests {
  @Test
  func seededAccountsHaveUniqueLocalEmailAddresses() {
    let accounts = LocalSeededAccount.allCases

    #expect(accounts.count == 16)
    #expect(Set(accounts.map(\.email)).count == accounts.count)
    #expect(LocalSeededAccount.listener.email == "listener@tunedin.local")
    #expect(LocalSeededAccount.newcomer.email == "newcomer@tunedin.local")
  }
}
