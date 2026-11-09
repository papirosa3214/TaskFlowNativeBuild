import XCTest

/// Ссылка в ответе роли: иконка хоста и короткая подпись.
///
/// Владелец 10.11.2026: «вид нужен и визуал отображения всяких ссылок».
/// Правила — чистые, поэтому проверяются здесь, без телефона и без
/// симулятора: сборка вью этого не доказывает.
final class ChatLinkPresentationTests: XCTestCase {
    private func present(_ href: String, _ text: String = "") -> ChatLinkPresentation.Presentation? {
        ChatLinkPresentation.presentation(href: href, text: text)
    }

    @objc func testGitHubPullRequestGetsRepoAndNumber() {
        let link = present("https://github.com/papirosa3214/New-Todoist/pull/42")
        XCTAssertEqual(link?.label, "papirosa3214/New-Todoist#42")
        XCTAssertEqual(link?.icon, .asset("link-github"))
        XCTAssertEqual(link?.kind, .external(host: "github.com"))
    }

    @objc func testGitHubIssueGetsNumber() {
        let link = present("https://github.com/o/r/issues/7")
        XCTAssertEqual(link?.label, "o/r#7")
    }

    @objc func testGitHubBlobGetsFileName() {
        let link = present("https://github.com/o/r/blob/main/Sources/Chat/Feed/ChatFeedVirtualList.swift")
        XCTAssertEqual(link?.label, "o/ChatFeedVirtualList.swift")
    }

    @objc func testGitLabMergeRequestHasItsOwnIcon() {
        let link = present("https://gitlab.com/group/project/-/merge_requests/9")
        XCTAssertEqual(link?.label, "group/project")
        XCTAssertEqual(link?.icon, .asset("link-gitlab"))
    }

    @objc func testWWWIsDropped() {
        let link = present("https://www.bitbucket.org/team/repo")
        XCTAssertEqual(link?.kind, .external(host: "bitbucket.org"))
        XCTAssertEqual(link?.label, "team/repo")
        XCTAssertEqual(link?.icon, .asset("link-bitbucket"))
    }

    @objc func testUnknownHostGetsShortTailAndArrowIcon() {
        let link = present("https://docs.example.com/guide/install/linux/ubuntu")
        XCTAssertEqual(link?.label, "docs.example.com/…/ubuntu")
        XCTAssertEqual(link?.icon, .symbol("arrow.up.right.square"))
    }

    @objc func testHostOnlyURLShowsHostAndPath() {
        let link = present("https://example.com/readme")
        XCTAssertEqual(link?.label, "example.com/readme")
    }

    @objc func testOwnLabelIsKept() {
        let link = present("https://github.com/o/r/pull/1", "наш пул-реквест")
        XCTAssertEqual(link?.label, "наш пул-реквест")
    }

    @objc func testURLAsLabelIsReplaced() {
        let link = present("https://github.com/o/r/pull/1", "https://github.com/o/r/pull/1")
        XCTAssertEqual(link?.label, "o/r#1")
    }

    @objc func testFileWithLineShowsNameAndLine() {
        let link = present("Sources/Chat/Feed/ChatFeedVirtualList.swift:42")
        XCTAssertEqual(link?.label, "ChatFeedVirtualList.swift:42")
        XCTAssertEqual(link?.kind, .file(path: "Sources/Chat/Feed/ChatFeedVirtualList.swift", line: 42))
        XCTAssertEqual(link?.icon, .asset("file-swift"))
    }

    @objc func testFileWithLineAndColumnKeepsLine() {
        let link = present("Sources/App/App.swift:12:8")
        XCTAssertEqual(link?.label, "App.swift:12")
        XCTAssertEqual(link?.kind, .file(path: "Sources/App/App.swift", line: 12))
    }

    @objc func testFileURLIsAFile() {
        let link = present("file:///Users/max/Проекты/TaskFlow/README.md")
        XCTAssertEqual(link?.label, "README.md")
        if case .file = link?.kind {} else { XCTFail("ожидали файл, а не адрес") }
    }

    @objc func testTaskFlowThreadHasBubbleIcon() {
        let link = present("taskflow://chats/room-1")
        XCTAssertEqual(link?.kind, .thread)
        XCTAssertEqual(link?.icon, .symbol("bubble.left"))
    }

    @objc func testPlainWordIsNotALink() {
        XCTAssertNil(present("просто текст"))
        XCTAssertNil(present("Sources"))
    }

    @objc func testEmptyIsNothing() {
        XCTAssertNil(present(""))
        XCTAssertNil(present("   "))
    }

    @objc func testSwiftFileGetsSwiftIcon() {
        let link = present("Sources/App/App.swift:12")
        XCTAssertEqual(link?.icon, .asset("file-swift"))
        XCTAssertEqual(link?.tint, .swift)
        XCTAssertEqual(link?.label, "App.swift:12")
    }

    @objc func testPythonFileGetsPythonIcon() {
        let link = present("server/tools/run.py")
        XCTAssertEqual(link?.icon, .asset("file-python"))
        XCTAssertEqual(link?.tint, .python)
    }

    @objc func testTypeScriptJsonMarkdown() {
        XCTAssertEqual(present("src/lib/roleContractV1.ts")?.icon, .asset("file-typescript"))
        XCTAssertEqual(present("package.json")?.icon, .asset("file-npm"))
        XCTAssertEqual(present("docs/AGENT-CYCLE.md")?.icon, .asset("file-markdown"))
    }

    @objc func testDocumentsAndMediaGetTheirIcons() {
        XCTAssertEqual(present("/tmp/отчёт-42.pdf")?.icon, .asset("file-default"))
        XCTAssertEqual(present("~/Desktop/screen-2026-11-10.png")?.icon, .asset("file-image"))
        XCTAssertEqual(present("~/Screen/demo.mp4")?.icon, .asset("file-video"))
        XCTAssertEqual(present("config/settings.yaml")?.icon, .asset("file-yml"))
    }

    @objc func testKnownBasenameWinsOverExtension() {
        // package.json — иконка npm, а не общий JSON.
        XCTAssertEqual(present("package.json")?.icon, .asset("file-npm"))
        XCTAssertEqual(present("Dockerfile")?.icon, .asset("file-docker"))
    }

    @objc func testUnknownExtensionFallsBackToDefault() {
        XCTAssertEqual(present("config/settings.qwerty")?.icon, .asset("file-default"))
    }

    @objc func testExternalLinkHasNoTint() {
        XCTAssertNil(present("https://github.com/o/r")?.tint)
    }

    @objc func testMailtoIsNotShownAsLink() {
        XCTAssertNil(present("mailto:max@example.com"))
    }

    @objc func testAzureDevOpsHasItsOwnIcon() {
        let link = present("https://dev.azure.com/org/project/_git/repo")
        XCTAssertEqual(link?.icon, .asset("link-azure-devops"))
    }
}
