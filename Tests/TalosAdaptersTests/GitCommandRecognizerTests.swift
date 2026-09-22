@testable import TalosAdapters
import TalosCore
import Testing

/// The adapter parses `git`/`gh` out of the `Bash` command because Claude Code
/// runs them through `Bash`, so each `taxonomy: 1` git type has its own case
/// here, and the safe-default cases assert that an unrecognized command narrows
/// to nothing rather than to a permissive guess.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#the-action-type-taxonomy
@Suite("Git command recognition")
struct GitCommandRecognizerTests {
    // MARK: Write tier — local

    @Test("git commit is git.commit, local")
    func commit() {
        let recognized = try? #require(GitCommandRecognizer.recognize(command: "git commit -m \"msg\""))
        #expect(recognized?.action == .gitCommit)
        #expect(recognized?.reachesRemote == false)
    }

    @Test("git branch <name> is git.branch.create")
    func branchCreate() {
        #expect(GitCommandRecognizer.recognize(command: "git branch feature/x")?.action == .gitBranchCreate)
    }

    @Test("git checkout -b and git switch -c create a branch")
    func branchCreateViaCheckoutAndSwitch() {
        #expect(GitCommandRecognizer.recognize(command: "git checkout -b feature/x")?.action == .gitBranchCreate)
        #expect(GitCommandRecognizer.recognize(command: "git switch -c feature/x")?.action == .gitBranchCreate)
    }

    // MARK: Write tier — remote

    @Test("git push is git.push and reaches a remote")
    func push() {
        let recognized = try? #require(GitCommandRecognizer.recognize(command: "git push origin main"))
        #expect(recognized?.action == .gitPush)
        #expect(recognized?.reachesRemote == true)
        #expect(recognized?.explicitRemoteURL == nil)
    }

    @Test("git push to an explicit URL carries that URL for the declared-target check")
    func pushExplicitURL() {
        let recognized = GitCommandRecognizer.recognize(command: "git push https://github.com/org/repo.git main")
        #expect(recognized?.action == .gitPush)
        #expect(recognized?.explicitRemoteURL == "https://github.com/org/repo.git")
    }

    @Test("gh pr create is git.pr.open, gh pr comment/review is git.pr.comment")
    func prOpenAndComment() {
        #expect(GitCommandRecognizer.recognize(command: "gh pr create --fill")?.action == .gitPROpen)
        #expect(GitCommandRecognizer.recognize(command: "gh pr comment 12 --body hi")?.action == .gitPRComment)
        #expect(GitCommandRecognizer.recognize(command: "gh pr review 12 --approve")?.action == .gitPRComment)
    }

    // MARK: Irreversible tier

    @Test("git push --force and its aliases are git.push.force")
    func forcePush() {
        #expect(GitCommandRecognizer.recognize(command: "git push --force origin main")?.action == .gitPushForce)
        #expect(GitCommandRecognizer.recognize(command: "git push -f origin main")?.action == .gitPushForce)
        #expect(
            GitCommandRecognizer.recognize(command: "git push --force-with-lease origin main")?.action == .gitPushForce
        )
    }

    @Test("git rebase, filter-branch, and commit --amend are git.history.rewrite")
    func historyRewrite() {
        #expect(GitCommandRecognizer.recognize(command: "git rebase -i HEAD~3")?.action == .gitHistoryRewrite)
        let filterBranch = GitCommandRecognizer.recognize(command: "git filter-branch --tree-filter x")
        #expect(filterBranch?.action == .gitHistoryRewrite)
        #expect(GitCommandRecognizer.recognize(command: "git commit --amend -m x")?.action == .gitHistoryRewrite)
    }

    @Test("git branch -d/-D is git.branch.delete")
    func branchDelete() {
        #expect(GitCommandRecognizer.recognize(command: "git branch -d feature/x")?.action == .gitBranchDelete)
        #expect(GitCommandRecognizer.recognize(command: "git branch -D feature/x")?.action == .gitBranchDelete)
    }

    @Test("gh pr merge is git.pr.merge, gh repo delete is git.repo.delete")
    func mergeAndRepoDelete() {
        #expect(GitCommandRecognizer.recognize(command: "gh pr merge 12 --squash")?.action == .gitPRMerge)
        #expect(GitCommandRecognizer.recognize(command: "gh repo delete org/repo --yes")?.action == .gitRepoDelete)
    }

    // MARK: Global options

    @Test("git's own global options are skipped before the subcommand")
    func globalOptionsSkipped() {
        #expect(GitCommandRecognizer.recognize(command: "git -C /w -c k=v push origin main")?.action == .gitPush)
    }

    // MARK: The safe default — narrows to nothing, never to a guess

    @Test("A non-git command is not recognized")
    func nonGitCommand() {
        #expect(GitCommandRecognizer.recognize(command: "cat one.txt") == nil)
        #expect(GitCommandRecognizer.recognize(command: "rm -rf build") == nil)
    }

    @Test("git status and git branch listing mutate nothing and are not gated as a write here")
    func readOnlyGitIsNotRecognizedAsAWrite() {
        #expect(GitCommandRecognizer.recognize(command: "git status") == nil)
        #expect(GitCommandRecognizer.recognize(command: "git branch --list") == nil)
    }

    /// A recognized git op chained with an unrecognized segment falls to `nil`
    /// as a whole, so an unrecognized `rm` can never ride in under a
    /// `git.commit` allowlist.
    @Test("A git op chained with an unrecognized command is not recognized")
    func chainedUnrecognizedSegmentFallsThrough() {
        #expect(GitCommandRecognizer.recognize(command: "git commit -m x && rm -rf /") == nil)
    }

    /// A command chaining two recognized git ops resolves to the most
    /// restrictive, the same principle `process.run` is classified by.
    @Test("Two chained git ops resolve to the most restrictive")
    func chainedGitOpsResolveToMostRestrictive() {
        let chained = GitCommandRecognizer.recognize(command: "git commit -m x && git push --force origin main")
        #expect(chained?.action == .gitPushForce)
    }

    // MARK: Fail closed on unmodeled shell constructs

    /// The operators that begin a new command all fall closed the same way `&&`
    /// does — otherwise a dangerous neighbour rides in as trailing tokens of a
    /// recognized segment (which the subcommand parsers ignore), laundering an
    /// `rm` into `git.push`'s allowlistable tier.
    @Test("A git op joined to another command by any command operator is not recognized")
    func chainedByAnyOperatorFallsThrough() {
        #expect(GitCommandRecognizer.recognize(command: "git push origin main & rm -rf x") == nil)
        #expect(GitCommandRecognizer.recognize(command: "git push origin main | tee log") == nil)
        #expect(GitCommandRecognizer.recognize(command: "git commit -m x ; rm -rf x") == nil)
        #expect(GitCommandRecognizer.recognize(command: "git commit -m x\nrm -rf x") == nil)
    }

    /// Substitution, a subshell, a redirect, and an escape are unmodeled — each
    /// can execute or expand into a second command, so the whole command falls
    /// to the most-restrictive default. `$` and a backtick are unmodeled even
    /// inside double quotes, where the shell still expands them.
    @Test("Substitution, redirects, and subshells are not recognized")
    func unmodeledConstructsFallThrough() {
        #expect(GitCommandRecognizer.recognize(command: "git push origin $(rm -rf x)") == nil)
        #expect(GitCommandRecognizer.recognize(command: "git commit -m `rm -rf x`") == nil)
        #expect(GitCommandRecognizer.recognize(command: "git commit -m \"$(rm -rf x)\"") == nil)
        #expect(GitCommandRecognizer.recognize(command: "git push origin main > ~/.ssh/authorized_keys") == nil)
        #expect(GitCommandRecognizer.recognize(command: "git push origin main \\; rm -rf x") == nil)
    }

    /// A `;`/`&&`/`|` inside a quoted commit message is literal, so the commit
    /// is still recognized — the scanner does not split mid-quote.
    @Test("A quoted commit message carrying an operator character is still git.commit")
    func quotedOperatorInMessageIsLiteral() {
        #expect(GitCommandRecognizer.recognize(command: "git commit -m \"fix: parse a; b && c\"")?.action == .gitCommit)
    }

    /// A `gh` op names no remote URL, so a link or `@mention` in a comment body
    /// is not read as one — it stays `git.pr.comment` with no explicit URL, and
    /// the gate resolves declared-ness against the repo connector.
    @Test("A URL or mention in a gh pr comment body is not read as the remote")
    func ghCommentBodyIsNotReadAsRemote() {
        let recognized = GitCommandRecognizer.recognize(
            command: "gh pr comment 12 --body 'see https://github.com/o/r/issues/5 @me'"
        )
        #expect(recognized?.action == .gitPRComment)
        #expect(recognized?.explicitRemoteURL == nil)
    }
}
