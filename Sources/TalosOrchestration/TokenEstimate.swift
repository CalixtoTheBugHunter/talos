/// Talos's own local, deterministic token-size approximation — never a call
/// to a model or a tokenizer service. Talos holds no model API
/// (https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary),
/// so enforcing a guideline's declared token ceiling and computing
/// Talos-added token overhead both need a way to size text that involves no
/// network call and no model. This is pure arithmetic over the text's own
/// character count, not a claim of exactness against any specific model's
/// real tokenizer — the ceiling check and the overhead ratio only need the
/// same estimator applied consistently, which is what makes both
/// reproducible.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Talos-Guidelines#editable-talos-guidelines
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Vision-and-Principles#budgets-that-make-the-above-testable
public enum TokenEstimate {
    /// Characters per token in this estimator's fixed ratio.
    private static let charactersPerToken = 4.0

    /// A deterministic size estimate for `text`, in whole tokens, rounded
    /// up so a non-empty string never estimates to zero.
    public static func approximate(_ text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        return Int((Double(text.count) / charactersPerToken).rounded(.up))
    }
}
