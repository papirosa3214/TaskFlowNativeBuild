import Foundation
import XCTest
#if canImport(TaskFlow)
@testable import TaskFlow
#endif

final class TaskCodeChangesTests: XCTestCase {
    private let json = """
    {"task_id":"t1","branch":"roles/t1","state":"branch","base":"aaa","head":"bbb",
     "totals":{"files":2,"additions":2,"deletions":1},
     "files":[
      {"path":"a.swift","old_path":null,"status":"modified","additions":1,"deletions":1,"binary":false,"truncated":false,
       "hunks":[
        {"header":"@@ -1,3 +1,3 @@","lines":[
          {"kind":"context","old":1,"new":1,"text":"let a = 1"},
          {"kind":"deleted","old":2,"new":null,"text":"let b = 2"},
          {"kind":"added","old":null,"new":2,"text":"let b = 3"}]},
        {"header":"@@ -40,1 +40,1 @@","lines":[
          {"kind":"context","old":40,"new":40,"text":"}"}]}]},
      {"path":"new.txt","old_path":null,"status":"added","additions":1,"deletions":0,"binary":false,"truncated":false,"hunks":[]},
      {"path":"x.bin","old_path":null,"status":"weird","additions":0,"deletions":0,"binary":true,"truncated":false,"hunks":[]}]}
    """

    private func decode() throws -> TaskCodeChanges {
        try JSONDecoder().decode(TaskCodeChanges.self, from: Data(json.utf8))
    }

    @objc func testDecodesServerAnswer() throws {
        let changes = try decode()
        XCTAssertEqual(changes.state, .branch)
        XCTAssertEqual(changes.totals.files, 2)
        XCTAssertEqual(changes.files.map(\.status), [.modified, .added, .unknown])
        XCTAssertEqual(changes.files[0].hunks[0].lines[1].kind, .deleted)
        XCTAssertNil(changes.files[0].hunks[0].lines[1].new)
        XCTAssertEqual(changes.summary, "2 файла · +2 −1")
    }

    /// Между кусками правки — строка «N строк без изменений».
    @objc func testGapBetweenHunks() throws {
        let rows = try decode().files[0].displayRows
        XCTAssertEqual(rows.count, 5)
        if case .gap(let count) = rows[3] { XCTAssertEqual(count, 37) } else { XCTFail("ожидался пропуск") }
    }

    /// Комментарий называет файл, строку и сам код — роль найдёт место без поиска.
    @objc func testCommentMessageNamesFileLineAndCode() throws {
        let file = try decode().files[0]
        let line = file.hunks[0].lines[2]
        let comments = [CodeReviewComment(path: file.path, line: line, text: "верни как было")]
        let text = CodeReviewComment.message(comments)
        XCTAssertTrue(text.contains("`a.swift`, строка 2 (добавлена)"))
        XCTAssertTrue(text.contains("`let b = 3`"))
        XCTAssertTrue(text.contains("верни как было"))
    }

    @objc func testRussianPlurals() {
        XCTAssertEqual(TaskCodeChanges.filesWord(1), "1 файл")
        XCTAssertEqual(TaskCodeChanges.filesWord(3), "3 файла")
        XCTAssertEqual(TaskCodeChanges.filesWord(5), "5 файлов")
        XCTAssertEqual(TaskCodeChanges.filesWord(11), "11 файлов")
        XCTAssertEqual(TaskCodeChanges.filesWord(21), "21 файл")
        XCTAssertEqual(TaskCodeChanges.linesWord(1), "1 строка")
        XCTAssertEqual(TaskCodeChanges.linesWord(37), "37 строк")
    }
}
