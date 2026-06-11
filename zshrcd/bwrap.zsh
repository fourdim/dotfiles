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

        --symlink usr/lib /lib
        --symlink usr/lib64 /lib64
        --symlink usr/bin /bin
        --symlink usr/bin /sbin

        --proc /proc
        --dev /dev
        --dev-bind-try /dev/kvm /dev/kvm

        --tmpfs /tmp
        --tmpfs /run

        --bind-try /run/systemd/resolve /run/systemd/resolve
        --tmpfs /home
        --bind "$PWD" "$PWD"

        --ro-bind-try "$ZDOTDIR" "$ZDOTDIR"

        --cap-add CAP_SYS_PTRACE
        --unshare-all --share-net
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

    if [[ -n "$BWRAP_DEBUG" ]]; then
        print -r -- "bwrap ${args[*]} $*"
    fi

    bwrap "${args[@]}" "$@"
}

# ---------------- coding agents ----------------

# Dev toolchain shared by every coding agent in the sandbox.
__bwrap_toolchain="
ro-try:$HOME/.config/nvm:$HOME/.config/nvm
bind-try:$HOME/.cache/ms-playwright:$HOME/.cache/ms-playwright
bind-try:$HOME/.local/share/pnpm:$HOME/.local/share/pnpm
bind-try:$HOME/.local/share/uv:$HOME/.local/share/uv
bind-try:$HOME/flutter:$HOME/flutter
bind-try:$HOME/.local/bin:$HOME/.local/bin
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

# __bwrap-agent <name> [args...] — run an agent's binary in the sandbox with
# the shared toolchain plus its own state bound in.
__bwrap-agent() {
    local name="$1"; shift
    BWRAP_EXTRA="${BWRAP_EXTRA:-}
${__bwrap_toolchain}
${__bwrap_agents[$name]}" __bwrap "$name" "$@"
}

alias claude="__bwrap-agent claude"
alias codebuddy="__bwrap-agent codebuddy"
