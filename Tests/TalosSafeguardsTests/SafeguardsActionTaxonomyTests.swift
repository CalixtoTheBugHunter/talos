import TalosCore
import Testing

/// Asserts every taxonomy constant is spelled exactly as
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#the-action-type-taxonomy
/// spells it — lowercase, dotted `domain.verb` — since matching is exact
/// string equality and an allowlist entry a user wrote is only as good as
/// this spelling staying correct.
@Suite("Safeguards action-type taxonomy: exact spelling")
struct SafeguardsActionTaxonomyTests {
    /// Read tier.
    @Test("file.read")
    func fileRead() {
        #expect(SafeguardsActionType.fileRead.rawValue == "file.read")
    }

    @Test("file.search")
    func fileSearch() {
        #expect(SafeguardsActionType.fileSearch.rawValue == "file.search")
    }

    @Test("git.read")
    func gitRead() {
        #expect(SafeguardsActionType.gitRead.rawValue == "git.read")
    }

    @Test("board.read")
    func boardRead() {
        #expect(SafeguardsActionType.boardRead.rawValue == "board.read")
    }

    @Test("spec.read")
    func specRead() {
        #expect(SafeguardsActionType.specRead.rawValue == "spec.read")
    }

    @Test("config.read")
    func configRead() {
        #expect(SafeguardsActionType.configRead.rawValue == "config.read")
    }

    @Test("connector.read")
    func connectorRead() {
        #expect(SafeguardsActionType.connectorRead.rawValue == "connector.read")
    }

    @Test("analysis.local")
    func analysisLocal() {
        #expect(SafeguardsActionType.analysisLocal.rawValue == "analysis.local")
    }

    /// Write tier.
    @Test("file.write")
    func fileWrite() {
        #expect(SafeguardsActionType.fileWrite.rawValue == "file.write")
    }

    @Test("file.move")
    func fileMove() {
        #expect(SafeguardsActionType.fileMove.rawValue == "file.move")
    }

    @Test("git.commit")
    func gitCommit() {
        #expect(SafeguardsActionType.gitCommit.rawValue == "git.commit")
    }

    @Test("git.branch.create")
    func gitBranchCreate() {
        #expect(SafeguardsActionType.gitBranchCreate.rawValue == "git.branch.create")
    }

    @Test("git.push")
    func gitPush() {
        #expect(SafeguardsActionType.gitPush.rawValue == "git.push")
    }

    @Test("git.pr.open")
    func gitPROpen() {
        #expect(SafeguardsActionType.gitPROpen.rawValue == "git.pr.open")
    }

    @Test("git.pr.comment")
    func gitPRComment() {
        #expect(SafeguardsActionType.gitPRComment.rawValue == "git.pr.comment")
    }

    @Test("board.item.create")
    func boardItemCreate() {
        #expect(SafeguardsActionType.boardItemCreate.rawValue == "board.item.create")
    }

    @Test("board.item.move")
    func boardItemMove() {
        #expect(SafeguardsActionType.boardItemMove.rawValue == "board.item.move")
    }

    @Test("board.item.update")
    func boardItemUpdate() {
        #expect(SafeguardsActionType.boardItemUpdate.rawValue == "board.item.update")
    }

    @Test("board.item.comment")
    func boardItemComment() {
        #expect(SafeguardsActionType.boardItemComment.rawValue == "board.item.comment")
    }

    @Test("spec.write")
    func specWrite() {
        #expect(SafeguardsActionType.specWrite.rawValue == "spec.write")
    }

    @Test("config.write")
    func configWrite() {
        #expect(SafeguardsActionType.configWrite.rawValue == "config.write")
    }

    @Test("config.guidelines.write")
    func configGuidelinesWrite() {
        #expect(SafeguardsActionType.configGuidelinesWrite.rawValue == "config.guidelines.write")
    }

    @Test("connector.write")
    func connectorWrite() {
        #expect(SafeguardsActionType.connectorWrite.rawValue == "connector.write")
    }

    /// Irreversible / outward-facing tier.
    @Test("process.run")
    func processRun() {
        #expect(SafeguardsActionType.processRun.rawValue == "process.run")
    }

    @Test("file.delete")
    func fileDelete() {
        #expect(SafeguardsActionType.fileDelete.rawValue == "file.delete")
    }

    @Test("git.push.protected")
    func gitPushProtected() {
        #expect(SafeguardsActionType.gitPushProtected.rawValue == "git.push.protected")
    }

    @Test("git.push.force")
    func gitPushForce() {
        #expect(SafeguardsActionType.gitPushForce.rawValue == "git.push.force")
    }

    @Test("git.history.rewrite")
    func gitHistoryRewrite() {
        #expect(SafeguardsActionType.gitHistoryRewrite.rawValue == "git.history.rewrite")
    }

    @Test("git.branch.delete")
    func gitBranchDelete() {
        #expect(SafeguardsActionType.gitBranchDelete.rawValue == "git.branch.delete")
    }

    @Test("git.repo.delete")
    func gitRepoDelete() {
        #expect(SafeguardsActionType.gitRepoDelete.rawValue == "git.repo.delete")
    }

    @Test("git.pr.merge")
    func gitPRMerge() {
        #expect(SafeguardsActionType.gitPRMerge.rawValue == "git.pr.merge")
    }

    @Test("board.item.delete")
    func boardItemDelete() {
        #expect(SafeguardsActionType.boardItemDelete.rawValue == "board.item.delete")
    }

    @Test("spec.delete")
    func specDelete() {
        #expect(SafeguardsActionType.specDelete.rawValue == "spec.delete")
    }

    @Test("spec.drive.create")
    func specDriveCreate() {
        #expect(SafeguardsActionType.specDriveCreate.rawValue == "spec.drive.create")
    }

    @Test("secret.read")
    func secretRead() {
        #expect(SafeguardsActionType.secretRead.rawValue == "secret.read")
    }

    @Test("secret.write")
    func secretWrite() {
        #expect(SafeguardsActionType.secretWrite.rawValue == "secret.write")
    }

    @Test("secret.send")
    func secretSend() {
        #expect(SafeguardsActionType.secretSend.rawValue == "secret.send")
    }

    @Test("deploy.staging")
    func deployStaging() {
        #expect(SafeguardsActionType.deployStaging.rawValue == "deploy.staging")
    }

    @Test("deploy.production")
    func deployProduction() {
        #expect(SafeguardsActionType.deployProduction.rawValue == "deploy.production")
    }

    @Test("package.install")
    func packageInstall() {
        #expect(SafeguardsActionType.packageInstall.rawValue == "package.install")
    }

    @Test("package.publish")
    func packagePublish() {
        #expect(SafeguardsActionType.packagePublish.rawValue == "package.publish")
    }

    @Test("spend.paid")
    func spendPaid() {
        #expect(SafeguardsActionType.spendPaid.rawValue == "spend.paid")
    }

    @Test("connector.undeclared")
    func connectorUndeclared() {
        #expect(SafeguardsActionType.connectorUndeclared.rawValue == "connector.undeclared")
    }

    /// Refused — not a tier.
    @Test("config.safeguards.write")
    func configSafeguardsWrite() {
        #expect(SafeguardsActionType.configSafeguardsWrite.rawValue == "config.safeguards.write")
    }

    @Test("config.allowlist.write")
    func configAllowlistWrite() {
        #expect(SafeguardsActionType.configAllowlistWrite.rawValue == "config.allowlist.write")
    }

    @Test("config.tier.write")
    func configTierWrite() {
        #expect(SafeguardsActionType.configTierWrite.rawValue == "config.tier.write")
    }
}
