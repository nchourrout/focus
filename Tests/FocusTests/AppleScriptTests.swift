import Testing
@testable import Focus

@Suite struct AppleScriptTests {
    @Test func escapeIsUnchangedForPlainStrings() {
        #expect(escapeAppleScript("plain string") == "plain string")
    }

    @Test func escapeEscapesQuotesAndBackslashes() {
        #expect(escapeAppleScript(#"a"b\c"#) == #"a\"b\\c"#)
    }

    @Test func sanitizerRejectsControlCharacters() {
        #expect(sanitizeAppleScriptString("multi\nline") == nil)
        #expect(sanitizeAppleScriptString("with\rreturn") == nil)
        #expect(sanitizeAppleScriptString("tab\tin\tmiddle") == nil)
    }

    @Test func sanitizerAcceptsTypicalText() {
        #expect(sanitizeAppleScriptString("Pomodoro complete") == "Pomodoro complete")
    }
}
