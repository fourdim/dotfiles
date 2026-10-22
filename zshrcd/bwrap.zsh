command -v bwrap > /dev/null || return

__bwrap() {
    echo "Running $1 in bubblewrap sandbox..."

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
        --bind /sys/fs/cgroup /sys/fs/cgroup
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
    )

    # ---------------- structured parsing ----------------
if [[ -n "$BWRAP_EXTRA" ]]; then
    local line mode src dst

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
        esac

    done <<< "$BWRAP_EXTRA"
fi

    # Run in its own delegated cgroup scope so the sandbox can manage
    # sub-cgroups under /sys/fs/cgroup. DelegateSubgroup= only applies to
    # services, so move into the "agent" leaf by hand before exec'ing bwrap;
    # this keeps the scope root free of processes. The user manager also
    # doesn't write the user.delegate marker on scopes, so set it here.
    # Fails closed if any step doesn't work.
    local scope=(systemd-run --user --scope --quiet -p Delegate=yes)
    local enter='cg=/sys/fs/cgroup$(sed -n "s/^0:://p" /proc/self/cgroup)
setfattr -n user.delegate -v 1 "$cg" &&
mkdir -p "$cg/agent" && echo 0 > "$cg/agent/cgroup.procs" && exec "$@"'

    if [[ -n "$BWRAP_DEBUG" ]]; then
        print -r -- "${scope[*]} sh -c <enter agent> bwrap ${args[*]} $*"
    fi

    "${scope[@]}" sh -c "$enter" sh bwrap "${args[@]}" "$@"
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
__bwrap_agents[claude]="
bind-try:$HOME/.claude:$HOME/.claude
bind-try:$HOME/.claude.json:$HOME/.claude.json
ro-try:$HOME/.local/share/claude:$HOME/.local/share/claude
"
__bwrap_agents[codebuddy]="
bind-try:$HOME/.codebuddy:$HOME/.codebuddy
ro-try:$HOME/.local/share/codebuddy:$HOME/.local/share/codebuddy
ro-try:$HOME/.local/share/CodeBuddyExtension:$HOME/.local/share/CodeBuddyExtension
"

__bwrap_agents[codex]="
bind-try:$HOME/.codex:$HOME/.codex
"

# __bwrap-agent <name> [args...] — run an agent's binary in the sandbox with
# the shared toolchain plus its own state bound in.
__bwrap-agent() {
    local name="$1"; shift
    BWRAP_EXTRA="${BWRAP_EXTRA:-}
${__bwrap_toolchain}
${__bwrap_agents[$name]}" __bwrap "$name" "$@"
}

alias claude="__bwrap-agent claude"
alias tgclaude="__bwrap-agent claude --channels plugin:telegram@claude-plugins-official"
alias codebuddy="__bwrap-agent codebuddy"
alias codex="__bwrap-agent codex"
