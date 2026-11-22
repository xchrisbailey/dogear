import DogearCore
import Foundation
import Testing

/// The Library's bookshelf and cassette rack: what a spine says, its size and color, how shelves
/// fill, and how reels show a Position.
struct ShelvingTests {
    func book(_ id: Int, _ title: String) -> Book {
        Book(id: id, title: title, authors: [], files: [], primaryFileID: nil, ebookCover: nil, audiobookCover: nil)
    }

    @Test(arguments: [
        ("The Odyssey", "Odyssey"),
        ("A Tale of Two Cities", "Tale of Two Cities"),
        ("An Ideal Husband", "Ideal Husband"),
        ("Moby-Dick; or, The Whale", "Moby-Dick"),
        ("Frankenstein: The Modern Prometheus", "Frankenstein"),
        ("Dune - Deluxe Edition", "Dune"),
        ("Emma", "Emma"),
        ("Anathem", "Anathem"),
        ("  Walden  ", "Walden"),
    ])
    func aSpineCarriesTheMainTitleOnly(title: String, onSpine: String) {
        #expect(Spine.title(for: title) == onSpine)
    }

    /// Cutting must never leave a spine blank.
    @Test(arguments: [("The", "The"), ("A", "A"), (": A Memoir", ": A Memoir"), ("The: Poems", "The")])
    func aTitleThatIsOnlyAnArticleOrSubtitleIsKept(title: String, onSpine: String) {
        #expect(Spine.title(for: title) == onSpine)
    }

    @Test func aBookKeepsItsShapeAndBooksDiffer() {
        let spines = (1 ... 200).map { Spine(book: book($0, "Book \($0)")) }

        #expect(Spine(book: book(42, "Book 42")) == spines[41])
        #expect(spines.allSatisfy { Spine.thicknesses.contains($0.thickness) })
        #expect(spines.allSatisfy { Spine.heights.contains($0.height) })
        #expect(spines.allSatisfy { Spine.fontSizes.contains($0.fontSize) })
        #expect(Set(spines.map(\.thickness)).count > 10)
        #expect(Set(spines.map(\.height)).count > 10)
        #expect(Set(spines.map(\.fallbackColor)).count == SpineColor.palette.count)
    }

    func book(_ id: Int, files: [BookFile]) -> Book {
        Book(id: id, title: "Book", authors: [], files: files, primaryFileID: nil, ebookCover: nil, audiobookCover: nil)
    }

    @Test func aBiggerEbookFileMakesAThickerSpine() {
        let sizes = [40, 150, 400, 1200, 5000, 30000, 900_000]
        let spines = sizes.map { Spine(book: book(7, files: [BookFile(id: 1, format: .epub, isSupported: true, sizeKB: $0)])) }

        #expect(zip(spines, spines.dropFirst()).allSatisfy { $0.thickness <= $1.thickness })
        #expect(spines.first?.thickness == Spine.thicknesses.lowerBound)
        #expect(spines.last?.thickness == Spine.thicknesses.upperBound)
        #expect(Set(spines.map(\.thickness)).count >= 5)
        // Height still comes from the Book, not its file.
        #expect(Set(spines.map(\.height)).count == 1)
    }

    @Test func thicknessComesFromTheEbookNotTheAudiobook() {
        let epub = BookFile(id: 1, format: .epub, isSupported: true, sizeKB: 400)
        let pdf = BookFile(id: 2, format: .pdf, isSupported: true, sizeKB: 20000)
        let audiobook = BookFile(id: 3, format: .audiobook, isSupported: true, sizeKB: 640_000)
        let alone = Spine(book: book(7, files: [epub]))

        #expect(Spine(book: book(7, files: [audiobook, pdf, epub])).thickness == alone.thickness)
        #expect(Spine(book: book(7, files: [pdf])).thickness > alone.thickness)
    }

    @Test func aBookOfUnknownSizeKeepsTheThicknessFromItsID() {
        let unsized = BookFile(id: 1, format: .epub, isSupported: true)
        let audiobook = BookFile(id: 3, format: .audiobook, isSupported: true, sizeKB: 640_000)

        #expect(Spine(book: book(42, files: [unsized, audiobook])) == Spine(book: book(42, files: [])))
    }

    @Test func thickerSpinesCarryBiggerType() {
        let spines = (1 ... 2000).map { Spine(book: book($0, "Book")) }.sorted { $0.thickness < $1.thickness }

        #expect(zip(spines, spines.dropFirst()).allSatisfy { $0.fontSize <= $1.fontSize })
        #expect(spines.first?.fontSize == Spine.fontSizes.lowerBound)
        #expect(spines.last?.fontSize == Spine.fontSizes.upperBound)
    }

    @Test func letteringIsReadableOnAnyCoverColor() {
        for red in stride(from: 0.0, through: 1.0, by: 0.125) {
            for green in stride(from: 0.0, through: 1.0, by: 0.125) {
                for blue in stride(from: 0.0, through: 1.0, by: 0.125) {
                    let shelved = SpineColor(red: red, green: green, blue: blue).shelved
                    #expect(shelved.spine.contrast(with: shelved.lettering) >= SpineColor.readableContrast)
                }
            }
        }
    }

    @Test func darkCoversKeepTheirColorAndLightOnesGetInk() {
        let oxblood = SpineColor.palette[0]
        let cream = SpineColor(red: 0.85, green: 0.81, blue: 0.72)

        #expect(oxblood.shelved.spine == oxblood)
        #expect(oxblood.shelved.lettering == .foil)
        #expect(cream.shelved.spine == cream)
        #expect(cream.shelved.lettering == .ink)
        #expect(SpineColor.palette.allSatisfy { $0.shelved.spine == $0 })
    }

    @Test func aCoverReadsAsItsMainColorNotItsWhiteType() throws {
        // A red cover, a third of it white lettering.
        let red: [UInt8] = [200, 30, 40, 255]
        let white: [UInt8] = [255, 255, 255, 255]
        let pixels = (0 ..< 300).flatMap { $0 % 3 == 0 ? white : red }

        let color = try #require(SpineColor.dominant(ofRGBA: pixels))

        #expect(abs(color.red - 200.0 / 255) < 0.01)
        #expect(abs(color.green - 30.0 / 255) < 0.01)
        #expect(abs(color.blue - 40.0 / 255) < 0.01)
    }

    @Test func aCoverWithNoVisiblePixelsHasNoColor() {
        #expect(SpineColor.dominant(ofRGBA: []) == nil)
        #expect(SpineColor.dominant(ofRGBA: [10, 20, 30, 0]) == nil)
    }

    @Test func shelvesFillLeftToRightAndWrap() {
        // 30 + 2 + 30 + 2 + 30 = 94 fits in 100; a fourth doesn't.
        let shelves = Shelves.fill(thicknesses: [30, 30, 30, 30, 40, 40, 30], shelfWidth: 100, spacing: 2)

        #expect(shelves == [0 ..< 3, 3 ..< 5, 5 ..< 7])
    }

    @Test func aSpineWiderThanTheShelfGetsItsOwn() {
        #expect(Shelves.fill(thicknesses: [30, 120, 30], shelfWidth: 100, spacing: 2) == [0 ..< 1, 1 ..< 2, 2 ..< 3])
        #expect(Shelves.fill(thicknesses: [], shelfWidth: 100, spacing: 2).isEmpty)
    }

    @Test func reelsMoveTapeFromLeftToRightAsTheBookPlays() {
        let unplayed = TapeReels(throughBook: 0, hub: 10, full: 30)
        let halfway = TapeReels(throughBook: 0.5, hub: 10, full: 30)
        let finished = TapeReels(throughBook: 1, hub: 10, full: 30)

        #expect(unplayed.supply == 30)
        #expect(unplayed.takeUp == 10)
        #expect(halfway.supply == halfway.takeUp)
        #expect(finished.supply == 10)
        #expect(finished.takeUp == 30)
    }

    /// Equal listening time winds equal tape area, so the radius grows fastest on an empty reel.
    @Test func tapeAreaNotRadiusFollowsTime() {
        let quarter = TapeReels(throughBook: 0.25, hub: 10, full: 30)

        // hub² + ¼(full² − hub²) = 100 + 200.
        #expect(abs(quarter.takeUp * quarter.takeUp - 300) < 0.0001)
        #expect(quarter.takeUp - 10 > (30 - 10) * 0.25)
    }

    @Test func reelsClampAPositionOutsideTheBook() {
        #expect(TapeReels(throughBook: -1, hub: 10, full: 30) == TapeReels(throughBook: 0, hub: 10, full: 30))
        #expect(TapeReels(throughBook: 2, hub: 10, full: 30) == TapeReels(throughBook: 1, hub: 10, full: 30))
    }
}
