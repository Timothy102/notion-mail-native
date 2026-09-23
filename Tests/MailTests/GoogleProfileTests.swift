import Foundation
@testable import MailCore
import XCTest

final class GoogleProfileTests: XCTestCase {
    func testParsesUserinfoAndSizesPicture() throws {
        let json = #"{"id":"1","name":"Tim Cvetko","given_name":"Tim","picture":"https://lh3.googleusercontent.com/a/ACg8ocK_x-Y=s96-c"}"#
        let info = try JSONDecoder().decode(GoogleUserinfo.self, from: Data(json.utf8))
        XCTAssertEqual(info.name, "Tim Cvetko")
        XCTAssertEqual(GoogleUserinfo.sizedPicture(try XCTUnwrap(info.picture))?.absoluteString,
                       "https://lh3.googleusercontent.com/a/ACg8ocK_x-Y=s256-c")
    }

    func testSizesPictureWithoutSizeOption() {
        XCTAssertEqual(GoogleUserinfo.sizedPicture("https://lh3.googleusercontent.com/a/ACg8ocK", size: 128)?.absoluteString,
                       "https://lh3.googleusercontent.com/a/ACg8ocK=s128-c")
        XCTAssertNil(GoogleUserinfo.sizedPicture("http://example.com/a.jpg"))
    }

    func testMissingFieldsDecode() throws {
        let info = try JSONDecoder().decode(GoogleUserinfo.self, from: Data(#"{"id":"1"}"#.utf8))
        XCTAssertNil(info.name)
        XCTAssertNil(info.picture)
    }
}
