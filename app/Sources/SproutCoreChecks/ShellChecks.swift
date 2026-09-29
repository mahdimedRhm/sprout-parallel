import Foundation
import SproutCore

func shellChecks() async {
    checkEqual(shellQuote("feature/x-1"), "feature/x-1", "safe strings stay unquoted")
    checkEqual(shellQuote("a b"), "'a b'", "spaces get quoted")
    checkEqual(shellQuote("it's"), "'it'\\''s'", "single quotes are escaped")
    checkEqual(shellQuote(""), "''", "empty string is quoted")
    checkEqual(shellQuote("$(rm -rf ~)"), "'$(rm -rf ~)'", "command substitution is neutralised")

    let box = LinesBox()
    let result = await LoginShell().run("printf 'one\\ntwo\\n'; echo oops >&2; printf 'tail'; exit 3") {
        box.append($0)
    }
    checkEqual(result.exitCode, 3, "login shell returns exit code")
    checkEqual(result.stdout, "one\ntwo\ntail", "stdout collected, trailing partial line kept")
    checkEqual(result.stderr, "oops\n", "stderr collected separately")
    checkEqual(Set(box.lines), Set(["one", "two", "oops", "tail"]), "every line streamed")

    let missing = await LoginShell().run("definitely-not-a-command-xyz") { _ in }
    checkEqual(missing.exitCode, 127, "missing command exits 127")
}
