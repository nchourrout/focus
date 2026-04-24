import Testing
@testable import Focus

@Suite struct SpotifySanitizerTests {
    @Test func escapeIsUnchangedForPlainStrings() {
        #expect(escapeAppleScript("spotify:playlist:abc") == "spotify:playlist:abc")
    }

    @Test func escapeEscapesQuotesAndBackslashes() {
        #expect(escapeAppleScript(#"a"b\c"#) == #"a\"b\\c"#)
    }

    @Test func sanitizerRejectsNewlineInjection() {
        #expect(sanitizeAppleScriptString("spotify:playlist:abc\ndisplay dialog \"x\"") == nil)
        #expect(sanitizeAppleScriptString("with\rreturn") == nil)
        #expect(sanitizeAppleScriptString("tab\tin\tmiddle") == nil)
    }

    @Test func sanitizerAcceptsTypicalURIs() {
        #expect(sanitizeAppleScriptString("spotify:playlist:37i9dQZF1DX0XUsuxWHRQd") != nil)
    }
}
