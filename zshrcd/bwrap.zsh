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
        --bind-try /dev/null /usr/bin/distrobox-host-exec

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
            tmpfs)
                args+=( --tmpfs "$src" )
                ;;
        esac

    done <<< "$BWRAP_EXTRA"
fi

    bwrap "${args[@]}" "$@"
}

__bwrap-claude() {
    local claude_extra="
bind-try:$HOME/.claude:$HOME/.claude
bind-try:$HOME/.claude.json:$HOME/.claude.json
ro-try:$HOME/.local/bin/claude:$HOME/.local/bin/claude
ro-try:$HOME/.local/share/claude:$HOME/.local/share/claude
ro-try:$HOME/.config/nvm:$HOME/.config/nvm
bind-try:$HOME/.cache/ms-playwright:$HOME/.cache/ms-playwright
bind-try:$HOME/.local/share/pnpm:$HOME/.local/share/pnpm
bind-try:$HOME/.local/share/uv:$HOME/.local/share/uv
bind-try:$HOME/flutter:$HOME/flutter
bind-try:$HOME/.local/bin:$HOME/.local/bin
bind-try:$HOME/go:$HOME/go
bind-try:$HOME/.cargo:$HOME/.cargo
"

    BWRAP_EXTRA="${BWRAP_EXTRA:-} $claude_extra" __bwrap "$@"
}

alias claude="__bwrap-claude claude"
