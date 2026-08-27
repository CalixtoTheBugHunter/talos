import Darwin
import Foundation

/// The `posix_spawn` call itself, and the C plumbing it needs — still the
/// adapter layer, the only layer permitted to spawn. Starts `executablePath`
/// as the leader of a brand-new process group, wired to the given pipe write
/// ends, with the given working directory and *only* the given environment.
/// https://github.com/CalixtoTheBugHunter/talos/wiki/Architecture-The-Orchestration-Boundary
///
/// - Returns: The child's pid, which is also its process group id.
/// - Throws: ``AgentSpawnFailure`` carrying the `errno` `posix_spawn` reported.
func spawnLeadingItsOwnProcessGroup(
    executablePath: String,
    arguments: [String],
    configuration: AgentLaunchConfiguration,
    standardOutputWrite: Int32,
    standardErrorWrite: Int32
) throws -> pid_t {
    var attributes: posix_spawnattr_t?
    posix_spawnattr_init(&attributes)
    defer { posix_spawnattr_destroy(&attributes) }
    // SETPGROUP with a group of 0 makes the child its own group leader, so
    // `killpg` on its pid reaches everything it starts and nothing of ours.
    // CLOEXEC_DEFAULT closes every descriptor the file actions below do not
    // name, so no Talos handle leaks into an agent CLI.
    posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT))
    posix_spawnattr_setpgroup(&attributes, 0)

    var actions: posix_spawn_file_actions_t?
    posix_spawn_file_actions_init(&actions)
    defer { posix_spawn_file_actions_destroy(&actions) }
    posix_spawn_file_actions_addchdir(&actions, configuration.workingDirectory.path)
    posix_spawn_file_actions_adddup2(&actions, standardOutputWrite, STDOUT_FILENO)
    posix_spawn_file_actions_adddup2(&actions, standardErrorWrite, STDERR_FILENO)

    // Built only from what the caller named, with nothing merged in from this
    // process — which makes "the spawned environment contains no model API key"
    // a property of the shape rather than of a list somebody remembered to strip.
    let environment = configuration.environment
        .map { "\($0.key)=\($0.value)" }
        .sorted()

    var spawned: pid_t = 0
    let code = withCStringArray([executablePath] + arguments) { argv in
        withCStringArray(environment) { envp in
            posix_spawn(&spawned, executablePath, &actions, &attributes, argv, envp)
        }
    }
    guard code == 0 else {
        throw AgentSpawnFailure(executablePath: executablePath, code: code)
    }
    return spawned
}

/// Builds and frees the `NULL`-terminated `char *[]` that `posix_spawn` takes.
/// Nesting `withCString` per element does not generalize to a count known only
/// at runtime.
private func withCStringArray<Result>(
    _ values: [String],
    _ body: (UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> Result
) -> Result {
    let array = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>.allocate(capacity: values.count + 1)
    for (offset, value) in values.enumerated() {
        array[offset] = strdup(value)
    }
    array[values.count] = nil
    defer {
        for offset in 0 ..< values.count {
            free(array[offset])
        }
        array.deallocate()
    }
    return body(array)
}
