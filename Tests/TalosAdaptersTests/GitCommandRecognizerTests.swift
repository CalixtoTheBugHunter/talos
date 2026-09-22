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
}
