import TalosCore
import TalosSafeguards
import Testing

/// One test per taxonomy entry: "a test that only exercises a tier in
/// general does not catch a new member" added to the wrong table.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Safeguards-and-Autonomy#the-action-type-taxonomy
@Suite("Safeguards action classifier: read tier")
struct SafeguardsClassifierReadTests {
    @Test("file.read classifies as read")
    func fileRead() {
        #expect(SafeguardsActionClassifier.classify(.fileRead) == .tier(.read))
    }

    @Test("file.search classifies as read")
    func fileSearch() {
        #expect(SafeguardsActionClassifier.classify(.fileSearch) == .tier(.read))
    }

    @Test("git.read classifies as read")
    func gitRead() {
        #expect(SafeguardsActionClassifier.classify(.gitRead) == .tier(.read))
    }

    @Test("board.read classifies as read")
    func boardRead() {
        #expect(SafeguardsActionClassifier.classify(.boardRead) == .tier(.read))
    }

    @Test("spec.read classifies as read")
    func specRead() {
        #expect(SafeguardsActionClassifier.classify(.specRead) == .tier(.read))
    }

    @Test("config.read classifies as read")
    func configRead() {
        #expect(SafeguardsActionClassifier.classify(.configRead) == .tier(.read))
    }

    @Test("connector.read classifies as read")
    func connectorRead() {
        #expect(SafeguardsActionClassifier.classify(.connectorRead) == .tier(.read))
    }

    @Test("analysis.local classifies as read")
    func analysisLocal() {
        #expect(SafeguardsActionClassifier.classify(.analysisLocal) == .tier(.read))
    }
}

@Suite("Safeguards action classifier: write tier")
struct SafeguardsClassifierWriteTests {
    @Test("file.write classifies as write")
    func fileWrite() {
        #expect(SafeguardsActionClassifier.classify(.fileWrite) == .tier(.write))
    }

    @Test("file.move classifies as write")
    func fileMove() {
        #expect(SafeguardsActionClassifier.classify(.fileMove) == .tier(.write))
    }

    @Test("git.commit classifies as write")
    func gitCommit() {
        #expect(SafeguardsActionClassifier.classify(.gitCommit) == .tier(.write))
    }

    @Test("git.branch.create classifies as write")
    func gitBranchCreate() {
        #expect(SafeguardsActionClassifier.classify(.gitBranchCreate) == .tier(.write))
    }

    @Test("git.push classifies as write")
    func gitPush() {
        #expect(SafeguardsActionClassifier.classify(.gitPush) == .tier(.write))
    }

    @Test("git.pr.open classifies as write")
    func gitPROpen() {
        #expect(SafeguardsActionClassifier.classify(.gitPROpen) == .tier(.write))
    }

    @Test("git.pr.comment classifies as write")
    func gitPRComment() {
        #expect(SafeguardsActionClassifier.classify(.gitPRComment) == .tier(.write))
    }

    @Test("board.item.create classifies as write")
    func boardItemCreate() {
        #expect(SafeguardsActionClassifier.classify(.boardItemCreate) == .tier(.write))
    }

    @Test("board.item.move classifies as write")
    func boardItemMove() {
        #expect(SafeguardsActionClassifier.classify(.boardItemMove) == .tier(.write))
    }

    @Test("board.item.update classifies as write")
    func boardItemUpdate() {
        #expect(SafeguardsActionClassifier.classify(.boardItemUpdate) == .tier(.write))
    }

    @Test("board.item.comment classifies as write")
    func boardItemComment() {
        #expect(SafeguardsActionClassifier.classify(.boardItemComment) == .tier(.write))
    }

    @Test("spec.write classifies as write")
    func specWrite() {
        #expect(SafeguardsActionClassifier.classify(.specWrite) == .tier(.write))
    }

    @Test("config.write classifies as write")
    func configWrite() {
        #expect(SafeguardsActionClassifier.classify(.configWrite) == .tier(.write))
    }

    @Test("config.guidelines.write classifies as write")
    func configGuidelinesWrite() {
        #expect(SafeguardsActionClassifier.classify(.configGuidelinesWrite) == .tier(.write))
    }

    @Test("connector.write classifies as write")
    func connectorWrite() {
        #expect(SafeguardsActionClassifier.classify(.connectorWrite) == .tier(.write))
    }
}

@Suite("Safeguards action classifier: irreversible tier")
struct SafeguardsClassifierIrreversibleTests {
    @Test("process.run classifies as irreversible — a command cannot be proven safe before it runs")
    func processRun() {
        #expect(SafeguardsActionClassifier.classify(.processRun) == .tier(.irreversible))
    }

    @Test("file.delete classifies as irreversible")
    func fileDelete() {
        #expect(SafeguardsActionClassifier.classify(.fileDelete) == .tier(.irreversible))
    }

    @Test("git.push.protected classifies as irreversible")
    func gitPushProtected() {
        #expect(SafeguardsActionClassifier.classify(.gitPushProtected) == .tier(.irreversible))
    }

    @Test("git.push.force classifies as irreversible")
    func gitPushForce() {
        #expect(SafeguardsActionClassifier.classify(.gitPushForce) == .tier(.irreversible))
    }

    @Test("git.history.rewrite classifies as irreversible")
    func gitHistoryRewrite() {
        #expect(SafeguardsActionClassifier.classify(.gitHistoryRewrite) == .tier(.irreversible))
    }

    @Test("git.branch.delete classifies as irreversible")
    func gitBranchDelete() {
        #expect(SafeguardsActionClassifier.classify(.gitBranchDelete) == .tier(.irreversible))
    }

    @Test("git.repo.delete classifies as irreversible")
    func gitRepoDelete() {
        #expect(SafeguardsActionClassifier.classify(.gitRepoDelete) == .tier(.irreversible))
    }

    @Test("git.pr.merge classifies as irreversible")
    func gitPRMerge() {
        #expect(SafeguardsActionClassifier.classify(.gitPRMerge) == .tier(.irreversible))
    }

    @Test("board.item.delete classifies as irreversible")
    func boardItemDelete() {
        #expect(SafeguardsActionClassifier.classify(.boardItemDelete) == .tier(.irreversible))
    }

    @Test("spec.delete classifies as irreversible")
    func specDelete() {
        #expect(SafeguardsActionClassifier.classify(.specDelete) == .tier(.irreversible))
    }

    @Test("spec.drive.create classifies as irreversible")
    func specDriveCreate() {
        #expect(SafeguardsActionClassifier.classify(.specDriveCreate) == .tier(.irreversible))
    }

    @Test("secret.read classifies as irreversible")
    func secretRead() {
        #expect(SafeguardsActionClassifier.classify(.secretRead) == .tier(.irreversible))
    }

    @Test("secret.write classifies as irreversible")
    func secretWrite() {
        #expect(SafeguardsActionClassifier.classify(.secretWrite) == .tier(.irreversible))
    }

    @Test("secret.send classifies as irreversible")
    func secretSend() {
        #expect(SafeguardsActionClassifier.classify(.secretSend) == .tier(.irreversible))
    }

    @Test("deploy.staging classifies as irreversible")
    func deployStaging() {
        #expect(SafeguardsActionClassifier.classify(.deployStaging) == .tier(.irreversible))
    }

    @Test("deploy.production classifies as irreversible")
    func deployProduction() {
        #expect(SafeguardsActionClassifier.classify(.deployProduction) == .tier(.irreversible))
    }

    @Test("package.install classifies as irreversible")
    func packageInstall() {
        #expect(SafeguardsActionClassifier.classify(.packageInstall) == .tier(.irreversible))
    }

    @Test("package.publish classifies as irreversible")
    func packagePublish() {
        #expect(SafeguardsActionClassifier.classify(.packagePublish) == .tier(.irreversible))
    }

    @Test("spend.paid classifies as irreversible")
    func spendPaid() {
        #expect(SafeguardsActionClassifier.classify(.spendPaid) == .tier(.irreversible))
    }

    @Test("connector.undeclared classifies as irreversible")
    func connectorUndeclared() {
        #expect(SafeguardsActionClassifier.classify(.connectorUndeclared) == .tier(.irreversible))
    }
}

@Suite("Safeguards action classifier: refused types resolve to a refusal, not a tier")
struct SafeguardsClassifierRefusedTests {
    @Test("config.safeguards.write is refused")
    func configSafeguardsWrite() {
        #expect(SafeguardsActionClassifier.classify(.configSafeguardsWrite) == .refused)
    }

    @Test("config.allowlist.write is refused")
    func configAllowlistWrite() {
        #expect(SafeguardsActionClassifier.classify(.configAllowlistWrite) == .refused)
    }

    @Test("config.tier.write is refused")
    func configTierWrite() {
        #expect(SafeguardsActionClassifier.classify(.configTierWrite) == .refused)
    }

    @Test("a refused type never resolves to a tier value that an approval could open")
    func refusedIsNeverATier() {
        let classification = SafeguardsActionClassifier.classify(.configTierWrite)
        guard case .tier = classification else { return }
        Issue.record("config.tier.write resolved to a tier, but refused types must never resolve to one")
    }
}

@Suite("Safeguards action classifier: unrecognized names, purity, and connector target override")
struct SafeguardsClassifierDefaultTests {
    /// > Classification defaults to the most restrictive tier when a call is
    /// > unrecognized — never to read.
    @Test("An unrecognized action type classifies as irreversible, never read")
    func unrecognizedDefaultsToIrreversible() {
        let unknown = SafeguardsActionType(rawValue: "totally.unrecognized")
        #expect(SafeguardsActionClassifier.classify(unknown) == .tier(.irreversible))
    }

    @Test("Classifying the same action type twice returns the same result — no I/O, no hidden state")
    func classifyIsPure() {
        let first = SafeguardsActionClassifier.classify(.fileWrite)
        let second = SafeguardsActionClassifier.classify(.fileWrite)
        #expect(first == second)
    }

    /// > `connector.undeclared` is classified by its target, not its verb,
    /// > so it overrides whatever the verb would have given: a read against
    /// > an undeclared system is `connector.undeclared`, not `connector.read`.
    @Test("An undeclared-system read resolves to connector.undeclared, not connector.read")
    func undeclaredReadOverridesVerb() {
        let resolved = SafeguardsActionType.connector(verb: .read, declared: false)
        #expect(resolved == .connectorUndeclared)
        #expect(resolved != .connectorRead)
    }

    @Test("An undeclared-system write also resolves to connector.undeclared, not connector.write")
    func undeclaredWriteOverridesVerb() {
        let resolved = SafeguardsActionType.connector(verb: .write, declared: false)
        #expect(resolved == .connectorUndeclared)
        #expect(resolved != .connectorWrite)
    }

    @Test("A declared-system read resolves to connector.read")
    func declaredReadResolvesToConnectorRead() {
        #expect(SafeguardsActionType.connector(verb: .read, declared: true) == .connectorRead)
    }

    @Test("A declared-system write resolves to connector.write")
    func declaredWriteResolvesToConnectorWrite() {
        #expect(SafeguardsActionType.connector(verb: .write, declared: true) == .connectorWrite)
    }
}
