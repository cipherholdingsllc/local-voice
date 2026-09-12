import Foundation

@main
enum PauseContinuationProve {
    static func expect(_ cond: Bool, _ message: String) {
        if !cond {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }

    static func expectEqual(_ got: String, _ want: String, _ label: String) {
        expect(got == want, "\(label)\n  got:  \(got)\n  want: \(want)")
    }

    static func main() {
        let glued = DictationCohesion.polish(
            "Yeah, I mean if you think about itThere should be a little bit more than a little bit."
        )
        expectEqual(
            glued,
            "Yeah, I mean if you think about it... there should be a little bit more than a little bit.",
            "glued continuation"
        )
        expect(!glued.contains("itThere"), "glued token survived")
        expect(!glued.contains("\u{2014}"), "em-dash in glued polish")

        let falsePeriod = DictationCohesion.polish(
            "Yeah, I mean if you think about it. There should be a little bit more."
        )
        expect(falsePeriod.contains("it... there"), "false period: \(falsePeriod)")
        expect(!falsePeriod.contains("it. There"), "period survived: \(falsePeriod)")

        expectEqual(
            DictationCohesion.polish("I went home. There was a cat."),
            "I went home. There was a cat.",
            "complete sentence"
        )
        expectEqual(
            DictationCohesion.polish("What about it? There is more."),
            "What about it? There is more.",
            "question mark"
        )
        expectEqual(
            DictationCohesion.polish("Look at it! There it is."),
            "Look at it! There it is.",
            "exclamation"
        )

        let ellipsis = DictationCohesion.polish("think about it... There should be more")
        expect(ellipsis.contains("it... there"), "ellipsis join: \(ellipsis)")
        expect(!ellipsis.contains("it...."), "quad dot: \(ellipsis)")
        expect(!ellipsis.contains("it... ,"), "ellipsis comma: \(ellipsis)")

        let commaJoin = DictationCohesion.polish("I wanted to And then I stopped")
        expect(commaJoin.lowercased().contains("to, and then"), "comma join: \(commaJoin)")

        let contrast = DictationCohesion.polish("I would rather There was another path")
        expect(contrast.contains("\u{2013}"), "en-dash missing: \(contrast)")
        expect(!contrast.contains("\u{2014}"), "em-dash in contrast")

        let raw = "Yeah, I mean if you think about it. There should be more"
        let once = PauseContinuation.repair(raw)
        expectEqual(PauseContinuation.repair(once), once, "repair idempotent")
        expectEqual(
            DictationCohesion.polish(DictationCohesion.polish(raw)),
            DictationCohesion.polish(raw),
            "polish idempotent"
        )

        expectEqual(PauseContinuation.repair(""), "", "empty")
        expectEqual(PauseContinuation.repair("Cipher"), "Cipher", "single word")
        expectEqual(
            PauseContinuation.repair("alpha \u{2014} beta"),
            "alpha \u{2013} beta",
            "em to en"
        )
        expectEqual(
            DictationCohesion.recapitalizeSentences(
                "yeah, think about it... there should be more"
            ),
            "Yeah, think about it... there should be more",
            "recapitalize after ellipsis"
        )

        let dash = TextPostProcessor.process("one dash two")
        expectEqual(dash, "one \u{2013} two", "spoken dash")
        expect(!dash.contains("\u{2014}"), "spoken dash em")
        expectEqual(
            TextPostProcessor.process("one em dash two"),
            "one \u{2013} two",
            "spoken em dash"
        )

        print("PASS: pause-continuation prove")
    }
}
