import XCTest
@testable import CopaHUDCore

final class NationStyleTests: XCTestCase {
  func testKnownTrickyNations() {
    XCTAssertEqual(NationStyle.style(for: "Switzerland").code, "SUI")
    XCTAssertEqual(NationStyle.style(for: "Switzerland").flag, "🇨🇭")
    XCTAssertEqual(NationStyle.style(for: "Netherlands").code, "NED")
    XCTAssertEqual(NationStyle.style(for: "Netherlands").flag, "🇳🇱")
    XCTAssertEqual(NationStyle.style(for: "Japan").code, "JPN")
    XCTAssertEqual(NationStyle.style(for: "South Korea").code, "KOR")
    XCTAssertEqual(NationStyle.style(for: "Spain").code, "ESP")
    XCTAssertEqual(NationStyle.style(for: "USA").code, "USA")
    XCTAssertEqual(NationStyle.style(for: "Germany").code, "GER")
    XCTAssertEqual(NationStyle.style(for: "Croatia").code, "CRO")
    XCTAssertEqual(NationStyle.style(for: "Portugal").code, "POR")
    XCTAssertEqual(NationStyle.style(for: "Mexico").code, "MEX")
    XCTAssertEqual(NationStyle.style(for: "Saudi Arabia").code, "KSA")
    XCTAssertEqual(NationStyle.style(for: "South Africa").code, "RSA")
  }

  func testHomeNationFlagsUseTagSequences() {
    XCTAssertEqual(NationStyle.style(for: "England").code, "ENG")
    XCTAssertEqual(NationStyle.style(for: "England").flag, "🏴\u{E0067}\u{E0062}\u{E0065}\u{E006E}\u{E0067}\u{E007F}")
    XCTAssertEqual(NationStyle.style(for: "Wales").code, "WAL")
    XCTAssertEqual(NationStyle.style(for: "Scotland").code, "SCO")
  }

  func testBrazilArgentina() {
    XCTAssertEqual(NationStyle.style(for: "Brazil").code, "BRA")
    XCTAssertEqual(NationStyle.style(for: "Brazil").flag, "🇧🇷")
    XCTAssertEqual(NationStyle.style(for: "Argentina").code, "ARG")
    XCTAssertEqual(NationStyle.style(for: "Argentina").flag, "🇦🇷")
  }

  func testCaseInsensitive() {
    XCTAssertEqual(NationStyle.style(for: "brazil").code, "BRA")
    XCTAssertEqual(NationStyle.style(for: "BRAZIL").code, "BRA")
    XCTAssertEqual(NationStyle.style(for: "  Brazil  ").code, "BRA")
  }

  func testAliases() {
    XCTAssertEqual(NationStyle.style(for: "Korea Republic").code, "KOR")
    XCTAssertEqual(NationStyle.style(for: "United States").code, "USA")
    XCTAssertEqual(NationStyle.style(for: "Côte d'Ivoire").code, "CIV")
    XCTAssertEqual(NationStyle.style(for: "Ivory Coast").code, "CIV")
    XCTAssertEqual(NationStyle.style(for: "Czechia").code, "CZE")
    XCTAssertEqual(NationStyle.style(for: "Czech Republic").code, "CZE")
  }

  func testUnknownFallback() {
    let s = NationStyle.style(for: "Springfield United")
    XCTAssertEqual(s.code, "SPR")
    XCTAssertEqual(s.flag, "🏳️")
  }

  func testShortUnknownFallbackDoesNotCrash() {
    XCTAssertEqual(NationStyle.style(for: "FC").code, "FC")
    XCTAssertEqual(NationStyle.style(for: "").code, "")
    XCTAssertEqual(NationStyle.style(for: "").flag, "🏳️")
  }

  func testCoversAtLeast48Nations() {
    XCTAssertGreaterThanOrEqual(NationStyle.nationCount, 48)
  }
}
