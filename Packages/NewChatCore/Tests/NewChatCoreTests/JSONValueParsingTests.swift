import XCTest
@testable import NewChatCore

final class JSONValueParsingTests: XCTestCase {
    func testScalarsObjectsAndArrays() throws {
        let value = try JSONValue.parse(#"""
        {"a":1,"b":-2.5,"c":true,"d":null,"e":"text","f":[1,"two",{"g":false}],"empty":{},"none":[]}
        """#)

        XCTAssertEqual(value["a"]?.intValue, 1)
        XCTAssertEqual(value["a"]?.doubleValue, 1)
        XCTAssertEqual(value["b"]?.doubleValue, -2.5)
        XCTAssertNil(value["b"]?.intValue)
        XCTAssertEqual(value["c"]?.boolValue, true)
        XCTAssertTrue(value["d"]?.isNull == true)
        XCTAssertEqual(value["e"]?.stringValue, "text")
        XCTAssertEqual(value["f"]?.arrayValue?.count, 3)
        XCTAssertEqual(value["f"]?.arrayValue?[2]["g"]?.boolValue, false)
        XCTAssertEqual(value["empty"]?.objectValue?.isEmpty, true)
        XCTAssertEqual(value["none"]?.arrayValue?.isEmpty, true)
        XCTAssertNil(value["missing"])
    }

    func testStringEscapesAndSurrogatePairs() throws {
        let value = try JSONValue.parse(#"{"s":"quote\" slash\\ tab\t newline\n unicode\u00e9 emoji\ud83d\ude00"}"#)
        let text = try XCTUnwrap(value["s"]?.stringValue)

        XCTAssertTrue(text.contains("quote\""))
        XCTAssertTrue(text.contains("slash\\"))
        XCTAssertTrue(text.contains("tab\t"))
        XCTAssertTrue(text.contains("newline\n"))
        XCTAssertTrue(text.contains("unicode\u{e9}"))
        XCTAssertTrue(text.contains("emoji\u{1F600}"))
    }

    func testMalformedInputThrows() {
        XCTAssertThrowsError(try JSONValue.parse(#"{"a":}"#))
        XCTAssertThrowsError(try JSONValue.parse(#"{"a":1"#))
        XCTAssertThrowsError(try JSONValue.parse(#"{"a":1}} "#))
        XCTAssertThrowsError(try JSONValue.parse(#""unterminated"#))
        XCTAssertThrowsError(try JSONValue.parse(#"[1,2,]"#))
        XCTAssertThrowsError(try JSONValue.parse(""))
    }

    /// Дерево Pi — цепочка \`children\`, по два контейнера на запись.
    /// \`JSONDecoder\` на Darwin отказывается разбирать глубже 512 контейнеров,
    /// а на глубокой цепочке ещё и рвёт стек; свой парсер обязан тянуть дальше.
    func testDeepSessionTreeBeyondJSONDecoderLimits() throws {
        let body = Self.sessionSnapshotJSON(entries: 1200)

        // Тот же документ для стороннего парсера неподъёмный — это и был дефект.
        XCTAssertThrowsError(try JSONSerialization.jsonObject(with: Data(body.utf8)))

        let snapshot = try XCTUnwrap(SessionSnapshot(json: try JSONValue.parse(body)))

        XCTAssertEqual(snapshot.id, "deep")
        XCTAssertEqual(snapshot.entries.count, 1200)
        XCTAssertEqual(snapshot.tree.count, 1)

        var node = try XCTUnwrap(snapshot.tree.first)
        var depth = 0
        while let child = node["children"]?.arrayValue?.first, child["entry"] != nil {
            node = child
            depth += 1
        }
        // 1200 записей плюс лист в конце цепочки.
        XCTAssertEqual(depth, 1200)
        XCTAssertEqual(node["entry"]?["id"]?.stringValue, "leaf")
    }

    static func sessionSnapshotJSON(entries: Int) -> String {
        let tree: String
        if entries > 0 {
            let prefixes = (1...entries).map { index in
                #"{"entry":{"id":"e"# + String(index) + #""},"children":["#
            }.joined()
            tree = prefixes + #"{"entry":{"id":"leaf"},"children":[]}"# + String(repeating: "]}", count: entries)
        } else {
            tree = #"{"entry":{"id":"leaf"},"children":[]}"#
        }
        let items = (0..<entries).map { index in
            #"{"type":"message","id":"e"# + String(index) + #""}"#
        }.joined(separator: ",")
        return #"{"id":"deep","cwd":"/project","entries":["# + items + #"],"tree":["# + tree + "]}"
    }
}
