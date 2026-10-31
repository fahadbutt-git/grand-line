import XCTest
@testable import QueryKit

final class CompilerTests: XCTestCase {
    func testPlainWordMatchesNameOrContentIgnoringCaseAndAccents() {
        XCTAssertTrue(matches("cornea", [Key.name: "Cornea notes.docx", Key.content: ""]))
        XCTAssertTrue(matches("cornea", [Key.name: "a.docx", Key.content: "Anterior CORNEA cases"]))
        XCTAssertTrue(matches("cafe", [Key.name: "Café menu.pdf", Key.content: ""]))
        XCTAssertFalse(matches("cornea", [Key.name: "a.docx", Key.content: "glaucoma"]))
    }

    func testPlainWordPredicateFormat() {
        XCTAssertEqual(
            Fixture.compile("endo").predicate.predicateFormat,
            "kMDItemFSName CONTAINS[cd] \"endo\" OR kMDItemTextContent CONTAINS[cd] \"endo\""
        )
    }

    func testPrefixUsesSpotlightWildcardEquality() {
        let format = Fixture.compile("endo*").predicate.predicateFormat
        XCTAssertEqual(format, "kMDItemFSName ==[cd] \"endo*\" OR kMDItemTextContent CONTAINS[cd] \"endo\"")
        XCTAssertEqual(Fixture.compile("name:en?do*").predicate.predicateFormat, "kMDItemFSName ==[cd] \"endo*\"")
    }

    func testAndOrNotEvaluate() {
        let attributes: [String: Any] = [Key.name: "cornea draft.docx", Key.content: ""]
        XCTAssertTrue(matches("cornea OR glaucoma", attributes))
        XCTAssertFalse(matches("cornea glaucoma", attributes))
        XCTAssertFalse(matches("cornea -draft", attributes))
        XCTAssertTrue(matches("cornea NOT (final OR submitted)", attributes))
    }

    func testPhraseMatchesContent() {
        XCTAssertTrue(matches("\"anterior chamber\"", [Key.name: "a.pdf", Key.content: "cells in the anterior chamber"]))
        XCTAssertFalse(matches("\"anterior chamber\"", [Key.name: "a.pdf", Key.content: "anterior segment chamber"]))
    }

    func testNameFilterIgnoresContent() {
        XCTAssertTrue(matches("name:protocol", [Key.name: "Study Protocol v2.docx", Key.content: ""]))
        XCTAssertFalse(matches("name:protocol", [Key.name: "notes.docx", Key.content: "protocol"]))
    }

    func testTextFilterIgnoresName() {
        XCTAssertTrue(matches("text:hypopyon", [Key.name: "a.pdf", Key.content: "small hypopyon"]))
        XCTAssertFalse(matches("text:hypopyon", [Key.name: "hypopyon.pdf", Key.content: ""]))
    }

    func testKindMapsToContentTypes() {
        XCTAssertEqual(Fixture.compile("kind:pdf").predicate.predicateFormat, "kMDItemContentTypeTree == \"com.adobe.pdf\"")
        XCTAssertTrue(matches("kind:doc", [Key.types: "org.openxmlformats.wordprocessingml.document"]))
        XCTAssertTrue(matches("kind:doc", [Key.types: "com.apple.iwork.pages.sffpages"]))
        XCTAssertTrue(matches("kind:sheet", [Key.types: "public.comma-separated-values-text"]))
        XCTAssertTrue(matches("kind:slides", [Key.types: "com.apple.iwork.keynote.sffkey"]))
        XCTAssertFalse(matches("kind:doc", [Key.types: "com.adobe.pdf"]))
    }

    func testEveryKindHasContentTypes() {
        for kind in FileKind.allCases {
            XCTAssertFalse(kind.contentTypes.isEmpty, kind.rawValue)
            XCTAssertEqual(root("kind:\(kind.rawValue)"), Node.term(.kind(kind)))
        }
        XCTAssertEqual(FileKind.markdown.contentTypes, ["net.daringfireball.markdown"])
        XCTAssertEqual(FileKind.email.contentTypes, ["com.apple.mail.emlx"])
        XCTAssertEqual(FileKind.app.contentTypes, ["com.apple.application-bundle"])
    }

    func testExtension() {
        XCTAssertTrue(matches("ext:docx", [Key.name: "Paper.DOCX"]))
        XCTAssertTrue(matches("ext:.docx", [Key.name: "Paper.docx"]))
        XCTAssertFalse(matches("ext:doc", [Key.name: "Paper.docx"]))
        XCTAssertTrue(matches("docx:", [Key.name: "Paper.docx"]))
    }

    func testFromTagAuthor() {
        XCTAssertTrue(matches("from:TriNetX.com", [Key.whereFroms: "https://live.trinetx.com/export/1"]))
        XCTAssertFalse(matches("from:trinetx.com", [Key.whereFroms: "https://mail.google.com"]))
        XCTAssertTrue(matches("tag:urgent", [Key.tags: "Urgent"]))
        XCTAssertFalse(matches("tag:urgent", [Key.tags: "Not urgent"]))
        XCTAssertTrue(matches("author:smith", [Key.authors: "Jane Smith"]))
        XCTAssertEqual(Fixture.compile("tag:proj*").predicate.predicateFormat, "kMDItemUserTags ==[cd] \"proj*\"")
    }

    func testSizeUnitsAreThousandBased() {
        XCTAssertEqual(root("size:100b"), Node.term(.size(.equal(100))))
        XCTAssertEqual(root("size:1.5kb"), Node.term(.size(.equal(1_500))))
        XCTAssertEqual(root("size:>=5MB"), Node.term(.size(.greaterOrEqual(5_000_000))))
        XCTAssertEqual(root("size:<2gb"), Node.term(.size(.less(2_000_000_000))))
        XCTAssertEqual(root("size:2048"), Node.term(.size(.equal(2_048))))
    }

    func testSizeComparisonsEvaluate() {
        XCTAssertTrue(matches("size:>5mb", [Key.size: 6_000_000]))
        XCTAssertFalse(matches("size:>5mb", [Key.size: 5_000_000]))
        XCTAssertTrue(matches("size:<=5mb", [Key.size: 5_000_000]))
        XCTAssertTrue(matches("size:1mb..5mb", [Key.size: 5_000_000]))
        XCTAssertTrue(matches("size:5mb..1mb", [Key.size: 1_000_000]))
        XCTAssertFalse(matches("size:1mb..5mb", [Key.size: 5_000_001]))
    }

    func testPages() {
        XCTAssertTrue(matches("pages:<15", [Key.pages: 14]))
        XCTAssertFalse(matches("pages:<15", [Key.pages: 15]))
        XCTAssertTrue(matches("pages:=3", [Key.pages: 3]))
        XCTAssertTrue(matches("pages:10..20", [Key.pages: 20]))
        XCTAssertFalse(matches("pages:>=10", [Key.pages: 9]))
    }

    func testAbsoluteFolderBecomesScope() {
        let query = Fixture.compile("in:~/Documents/Research/")
        XCTAssertEqual(query.scopes, ["/Users/me/Documents/Research"])
        XCTAssertTrue(query.postFilter("/Users/me/Documents/Research/a.pdf"))
        XCTAssertFalse(query.postFilter("/Users/me/Documents/ResearchOld/a.pdf"))
        XCTAssertEqual(query.predicate.predicateFormat, "kMDItemFSName == \"*\"")
        XCTAssertEqual(Fixture.compile("in:/Volumes/Data").scopes, ["/Volumes/Data"])
    }

    func testBareFolderIsPostFilter() {
        let query = Fixture.compile("in:downloads cornea")
        XCTAssertEqual(query.scopes, [])
        XCTAssertTrue(query.postFilter("/Users/me/Downloads/scan.pdf"))
        XCTAssertFalse(query.postFilter("/Users/me/Downloads2/scan.pdf"))
        XCTAssertTrue(query.predicate.evaluate(with: [Key.name: "cornea.pdf", Key.content: ""]))
    }

    func testFolderListsAndNegation() {
        let either = Fixture.compile("in:Downloads,Desktop")
        XCTAssertTrue(either.postFilter("/Users/me/Desktop/a"))
        XCTAssertTrue(either.postFilter("/Users/me/Downloads/a"))
        XCTAssertFalse(either.postFilter("/Users/me/Documents/a"))

        let excluded = Fixture.compile("-in:Downloads")
        XCTAssertFalse(excluded.postFilter("/Users/me/Downloads/a"))
        XCTAssertTrue(excluded.postFilter("/Users/me/Desktop/a"))

        let both = Fixture.compile("in:~/A,~/B")
        XCTAssertEqual(both.scopes, ["/Users/me/A", "/Users/me/B"])
    }

    func testProjAliasIsFolder() {
        let query = Fixture.compile("proj:Glaucoma")
        XCTAssertTrue(query.postFilter("/Users/me/Drive/01 Research/_Active/Glaucoma/a.R"))
        XCTAssertFalse(query.postFilter("/Users/me/Drive/01 Research/_Active/Cornea/a.R"))
    }

    func testDriveAndLocal() {
        let drive = Fixture.compile("drive:")
        XCTAssertEqual(drive.scopes, ["/Users/me/Library/CloudStorage"])
        XCTAssertTrue(drive.postFilter("/Users/me/Library/CloudStorage/GoogleDrive-you@example.com/My Drive/a.pdf"))
        XCTAssertFalse(drive.postFilter("/Users/me/Library/CloudStorage/Dropbox/a.pdf"))

        let local = Fixture.compile("local:")
        XCTAssertEqual(local.scopes, ["/Users/me"])
        XCTAssertTrue(local.postFilter("/Users/me/Documents/a.pdf"))
        XCTAssertFalse(local.postFilter("/Users/me/Library/CloudStorage/GoogleDrive-x/a.pdf"))
        XCTAssertFalse(local.postFilter("/Volumes/USB/a.pdf"))
    }

    func testSortPassesThrough() {
        XCTAssertEqual(Fixture.compile("x sort:name").sort, .name)
        XCTAssertNil(Fixture.compile("x").sort)
        XCTAssertEqual(SortKey.modified.attribute, "kMDItemContentModificationDate")
        XCTAssertFalse(SortKey.modified.ascending)
        XCTAssertTrue(SortKey.name.ascending)
    }
}
