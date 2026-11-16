import Testing
@testable import clippy

@Suite("TextFilter")
struct TextFilterTests {
    @Test(arguments: ["", " ", "\n\t", "\u{200B}", "\u{FEFF}", "  \u{200B}\u{200D} \n", "\u{00AD}"])
    func emptyLookingTextIsIgnored(_ s: String) { #expect(!TextFilter.isMeaningful(s)) }

    @Test(arguments: ["a", "  hello  ", "\u{200B}x", "😀"])
    func visibleTextIsKept(_ s: String) { #expect(TextFilter.isMeaningful(s)) }

    @Test func singleURL() {
        #expect(TextFilter.isSingleURL("https://example.com/cat.png"))
        #expect(!TextFilter.isSingleURL("look at https://example.com"))
        #expect(!TextFilter.isSingleURL("hello"))
    }
}

@Suite("SecretFilter")
struct SecretFilterTests {
    @Test(arguments: [
        "Tr0ub4dor&3",
        "P@ssw0rd2024",
        "hunter2!X",
        "ghp_" + String(repeating: "a1B2", count: 9),
        "github_pat_" + String(repeating: "Ab3_", count: 12),
        "sk-proj-" + String(repeating: "xY9", count: 10),
        "AKIAIOSFODNN7EXAMPLE",
        "xoxb-123456789012-abcdefghij",
        "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U",
        "-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNzaC1rZXktdjEAAAA\n-----END OPENSSH PRIVATE KEY-----",
        "k8Jd2mQ9xLp4Wz7Rv3Nb",          // long random token, no symbols
    ])
    func secretsAreSkipped(_ s: String) { #expect(SecretFilter.looksLikeSecret(s)) }

    @Test(arguments: [
        "hello world",
        "password",
        "https://example.com/a?b=C1&d=2",
        "www.Example2.com/page",
        "allen@example.com",
        "/usr/local/bin",
        "~/Desktop/Notes2.txt",
        "12345678",
        "2024-11-16",
        "The meeting is at 3pm, room B2!",
        "let x = foo(1)",
        "Report_2024.pdf",
        "user_id2",
        "iPhone15",
        "camelCaseName",
        "https://youtu.be/dQw4w9WgXcQ",
    ])
    func normalTextIsKept(_ s: String) { #expect(!SecretFilter.looksLikeSecret(s)) }
}

@Suite("YouTube")
struct YouTubeTests {
    @Test(arguments: [
        "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
        "https://youtube.com/watch?v=dQw4w9WgXcQ&t=42s",
        "https://www.youtube.com/watch?list=PL123&v=dQw4w9WgXcQ",
        "https://m.youtube.com/watch?v=dQw4w9WgXcQ",
        "https://music.youtube.com/watch?v=dQw4w9WgXcQ&feature=share",
        "https://youtu.be/dQw4w9WgXcQ",
        "https://youtu.be/dQw4w9WgXcQ?si=abc123",
        "https://www.youtube.com/shorts/dQw4w9WgXcQ",
        "https://www.youtube.com/embed/dQw4w9WgXcQ",
        "https://www.youtube.com/live/dQw4w9WgXcQ",
        "  https://youtu.be/dQw4w9WgXcQ  \n",
    ])
    func recognisesVideoLinks(_ url: String) { #expect(YouTube.videoID(from: url) == "dQw4w9WgXcQ") }

    @Test(arguments: [
        "https://www.youtube.com/",
        "https://www.youtube.com/@somechannel",
        "https://www.youtube.com/playlist?list=PL123",
        "https://www.youtube.com/watch?v=short",
        "https://vimeo.com/123456",
        "https://notyoutube.com/watch?v=dQw4w9WgXcQ",
        "watch this https://youtu.be/dQw4w9WgXcQ",
        "dQw4w9WgXcQ",
    ])
    func ignoresEverythingElse(_ s: String) { #expect(YouTube.videoID(from: s) == nil) }
}
