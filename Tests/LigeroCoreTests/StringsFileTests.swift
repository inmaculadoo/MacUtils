import XCTest
@testable import LigeroCore

final class StringsFileTests: XCTestCase {
    func testParsesCommentsAndEscapes() throws {
        let text = """
        /* block
           comment */
        "a" = "uno";
        // line comment
        "b.c" = "dos \\"comillas\\"\\nlínea";
        "d"="sin espacios";
        """
        let t = try StringsFile.parse(text)
        XCTAssertEqual(t["a"], "uno")
        XCTAssertEqual(t["b.c"], "dos \"comillas\"\nlínea")
        XCTAssertEqual(t["d"], "sin espacios")
        XCTAssertEqual(t.count, 3)
    }

    func testRejectsDuplicatesAndSyntaxErrors() {
        XCTAssertThrowsError(try StringsFile.parse(#""a" = "1"; "a" = "2";"#))
        XCTAssertThrowsError(try StringsFile.parse(#""a" = "1""#))
        XCTAssertThrowsError(try StringsFile.parse(#""a" "1";"#))
        XCTAssertThrowsError(try StringsFile.parse(#""a" = "1"; /* open"#))
    }

    func testFormatSpecifiers() {
        XCTAssertEqual(StringsFile.formatSpecifiers(in: "%@ y %ld al 100%%"), ["%@", "%ld"])
        XCTAssertEqual(StringsFile.formatSpecifiers(in: "%2$@ %1$@"), ["%@", "%@"])
        XCTAssertEqual(StringsFile.formatSpecifiers(in: "nada"), [])
    }
}
