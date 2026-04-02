import Foundation

enum LyricsProviderTests {
    static func runAll() {
        testParseSingleLine()
        testParseMultipleLines()
        testParseSortsbyTime()
        testParseSkipsEmptyText()
        testParseSkipsMetadataTags()
        testParseMalformedLines()
        testParseEmptyInput()
    }

    static func testParseSingleLine() {
        let raw = "[00:27.93] Listen to the wind blow"
        let lines = LyricsProvider.parseSyncedLyrics(raw)
        TestRunner.assertEqual(lines.count, 1, "parse single line count")
        TestRunner.assert(abs(lines[0].time - 27.93) < 0.01, "parse single line time")
        TestRunner.assertEqual(lines[0].text, "Listen to the wind blow", "parse single line text")
    }

    static func testParseMultipleLines() {
        let raw = """
        [00:27.93] Listen to the wind blow
        [00:30.88] Watch the sun rise
        [01:05.20] Running in the shadows
        """
        let lines = LyricsProvider.parseSyncedLyrics(raw)
        TestRunner.assertEqual(lines.count, 3, "parse multiple lines count")
        TestRunner.assert(abs(lines[0].time - 27.93) < 0.01, "parse line 1 time")
        TestRunner.assert(abs(lines[1].time - 30.88) < 0.01, "parse line 2 time")
        TestRunner.assert(abs(lines[2].time - 65.20) < 0.01, "parse line 3 time")
        TestRunner.assertEqual(lines[2].text, "Running in the shadows", "parse line 3 text")
    }

    static func testParseSortsbyTime() {
        let raw = """
        [01:00.00] Second line
        [00:30.00] First line
        """
        let lines = LyricsProvider.parseSyncedLyrics(raw)
        TestRunner.assertEqual(lines.count, 2, "sort by time count")
        TestRunner.assertEqual(lines[0].text, "First line", "sort by time first")
        TestRunner.assertEqual(lines[1].text, "Second line", "sort by time second")
    }

    static func testParseSkipsEmptyText() {
        let raw = """
        [00:10.00]
        [00:20.00] Actual lyrics
        [00:30.00]
        """
        let lines = LyricsProvider.parseSyncedLyrics(raw)
        TestRunner.assertEqual(lines.count, 1, "skip empty text count")
        TestRunner.assertEqual(lines[0].text, "Actual lyrics", "skip empty text content")
    }

    static func testParseSkipsMetadataTags() {
        let raw = """
        [ti:Song Title]
        [ar:Artist Name]
        [00:10.00] Real lyric line
        """
        // Metadata tags like [ti:Song Title] won't match mm:ss.ff pattern
        let lines = LyricsProvider.parseSyncedLyrics(raw)
        TestRunner.assertEqual(lines.count, 1, "skip metadata count")
        TestRunner.assertEqual(lines[0].text, "Real lyric line", "skip metadata content")
    }

    static func testParseMalformedLines() {
        let raw = """
        [bad] Not a timestamp
        No bracket at all
        [00:10.00] Valid line
        [xx:yy.zz] Invalid numbers
        """
        let lines = LyricsProvider.parseSyncedLyrics(raw)
        TestRunner.assertEqual(lines.count, 1, "malformed lines count")
        TestRunner.assertEqual(lines[0].text, "Valid line", "malformed lines valid content")
    }

    static func testParseEmptyInput() {
        let lines = LyricsProvider.parseSyncedLyrics("")
        TestRunner.assertEqual(lines.count, 0, "empty input count")
    }
}
