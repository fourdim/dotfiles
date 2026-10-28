command -v bwrap > /dev/null || return

# True when a systemd user manager owns our cgroup and is reachable, i.e. we
# can get a delegated scope from it.
__bwrap-can-delegate() {
    [[ "$(</proc/self/cgroup)" == 0::/user.slice/*/user@<->.service/* ]] &&
        systemctl --user show-environment &> /dev/null
}

# __bwrap <cmd> [args...] — run <cmd> in the sandbox. Extra mounts come from
# $__bwrap_spec (set by __bwrap-agent) followed by the user's $BWRAP_EXTRA,
# so user overrides are applied last and win.
__bwrap() {
    print -u2 -r -- "Running $1 in bubblewrap sandbox..."

    # Refuse to expose $HOME (or / or /home) wholesale via the $PWD bind.
    if [[ "$PWD" == / || "$HOME" == "$PWD" || "$HOME" == "$PWD"/* ]]; then
        print -u2 -r -- "bwrap: refusing to bind $PWD; cd into a project directory first"
        return 1
    fi

    local args=()

    # ---------------- base system ----------------
    args+=(
        --ro-bind /usr /usr
        --ro-bind /etc /etc
        --ro-bind /opt /opt
        --ro-bind /var /var
        --tmpfs /var/tmp

        --symlink usr/lib /lib
        --symlink usr/lib64 /lib64
        --symlink usr/bin /bin
        --symlink usr/bin /sbin

        --proc /proc
        --dev /dev
        --dev-bind-try /dev/kvm /dev/kvm
        --dev-bind-try /dev/net/tun /dev/net/tun

        --tmpfs /tmp
        --tmpfs /run

        --bind-try /run/systemd/resolve /run/systemd/resolve
        --tmpfs /home
        --bind "$PWD" "$PWD"

        --ro-bind-try "$ZDOTDIR" "$ZDOTDIR"

#        --cap-add CAP_SYS_PTRACE
        --unshare-user --unshare-ipc --unshare-pid --unshare-uts --share-net
        --new-session
        --die-with-parent
        --hostname bwrap-sandbox
        --unsetenv BWRAP_EXTRA
    )

    # ---------------- structured parsing ----------------
    # One "mode:src:dst" per line. dir/json create a missing src first so
    # state written in the sandbox is never lost to the tmpfs /home.
    local line mode rest src dst
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        mode="${line%%:*}"
        rest="${line#*:}"

        src="${rest%:*}"
        dst="${rest##*:}"

        case "$mode" in
            bind)
                args+=( --bind "$src" "$dst" )
                ;;
            bind-try)
                args+=( --bind-try "$src" "$dst" )
                ;;
            dir)
                mkdir -p -- "$src" || return
                args+=( --bind "$src" "$dst" )
                ;;
            json)
                [[ -e "$src" ]] || print -r -- '{}' > "$src" || return
                args+=( --bind "$src" "$dst" )
                ;;
            ro)
                args+=( --ro-bind "$src" "$dst" )
                ;;
            ro-try)
                args+=( --ro-bind-try "$src" "$dst" )
                ;;
            mask)
                 # Bind only if dst exists -- /dev/null as a universal black hole.
                [[ -e "$dst" ]] && args+=( --bind "$src" "$dst" )
                ;;
            tmpfs)
                args+=( --tmpfs "$src" )
                ;;
            setenv)
                args+=( --setenv "$src" "$dst" )
                ;;
        esac
    done <<< "${__bwrap_spec-}
${BWRAP_EXTRA-}"

    local runner=()
    if __bwrap-can-delegate; then
        # Run in its own delegated cgroup scope so the sandbox can manage
        # sub-cgroups. DelegateSubgroup= only applies to services, so move
        # into the "agent" leaf by hand before exec'ing bwrap; this keeps the
        # scope root free of processes. The user manager also doesn't write
        # the user.delegate marker on scopes, so set it here. Only the scope
        # is mounted, at its real path, so /proc/self/cgroup still resolves
        # and the rest of the host cgroup tree stays out of reach.
        # Fails closed if any step doesn't work.
        local enter='cg=/sys/fs/cgroup$(sed -n "s/^0:://p" /proc/self/cgroup)
setfattr -n user.delegate -v 1 "$cg" &&
mkdir -p "$cg/agent" && echo 0 > "$cg/agent/cgroup.procs" &&
b=$1 && shift && exec "$b" --bind "$cg" "$cg" "$@"'
        runner=(systemd-run --user --scope --quiet -p Delegate=yes sh -c "$enter" sh)
    fi

    [[ -n "$BWRAP_DEBUG" ]] && print -u2 -r -- "${runner[*]} bwrap ${args[*]} $*"

    "${runner[@]}" bwrap "${args[@]}" "$@"
}

# ---------------- coding agents ----------------

# Dev toolchain shared by every coding agent in the sandbox.
__bwrap_toolchain="
ro-try:$HOME/.agents/skills:$HOME/.agents/skills
ro-try:$HOME/.config/nvm:$HOME/.config/nvm
bind-try:$HOME/.cache/ms-playwright:$HOME/.cache/ms-playwright
bind-try:$HOME/.local/share/pnpm:$HOME/.local/share/pnpm
bind-try:$HOME/.local/share/uv:$HOME/.local/share/uv
bind-try:$HOME/flutter:$HOME/flutter
bind-try:$HOME/.local/bin:$HOME/.local/bin
bind-try:$HOME/.bun:$HOME/.bun
bind-try:$HOME/go:$HOME/go
bind-try:$HOME/.cargo:$HOME/.cargo
bind-try:$HOME/.rustup:$HOME/.rustup
"

# Per-agent state: config + binary + data, keyed by agent name.
typeset -gA __bwrap_agents
# Binary to run for an agent, when it differs from the agent name.
typeset -gA __bwrap_bins

__bwrap_agents[claude]="
dir:$HOME/.claude:$HOME/.claude
json:$HOME/.claude.json:$HOME/.claude.json
ro-try:$HOME/.local/share/claude:$HOME/.local/share/claude
"

# Second Claude account; CLAUDE_CONFIG_DIR keeps .claude.json and
# .credentials.json inside the config dir, so one mount covers it.
__bwrap_agents[claudew]="
dir:$HOME/.claude-work:$HOME/.claude-work
setenv:CLAUDE_CONFIG_DIR:$HOME/.claude-work
ro-try:$HOME/.local/share/claude:$HOME/.local/share/claude
"
__bwrap_bins[claudew]=claude

__bwrap_agents[codebuddy]="
dir:$HOME/.codebuddy:$HOME/.codebuddy
ro-try:$HOME/.local/share/codebuddy:$HOME/.local/share/codebuddy
ro-try:$HOME/.local/share/CodeBuddyExtension:$HOME/.local/share/CodeBuddyExtension
"

__bwrap_agents[codex]="
dir:$HOME/.codex:$HOME/.codex
"

# __bwrap-agent <name> [args...] — run an agent's binary in the sandbox with
# the shared toolchain plus its own state bound in.
__bwrap-agent() {
    local name="$1"; shift
    local __bwrap_spec="${__bwrap_toolchain}
${__bwrap_agents[$name]}"
    __bwrap "${__bwrap_bins[$name]:-$name}" "$@"
}

alias claude="__bwrap-agent claude"
alias claudew="__bwrap-agent claudew"
alias tgclaude="__bwrap-agent claude --channels plugin:telegram@claude-plugins-official"
alias codebuddy="__bwrap-agent codebuddy"
alias codex="__bwrap-agent codex"
