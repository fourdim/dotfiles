command -v bwrap > /dev/null || return

__bwrap() {
    echo "Running $1 in bubblewrap sandbox..."
    bwrap \
        --ro-bind /usr /usr \
        --ro-bind /etc /etc \
        --ro-bind /opt /opt \
        --ro-bind /var /var \
        --symlink usr/lib /lib \
        --symlink usr/lib64 /lib64 \
        --symlink usr/bin /bin \
        --symlink usr/bin /sbin \
        --proc /proc \
        --dev /dev \
        --dev-bind-try /dev/kvm /dev/kvm \
        --tmpfs /tmp \
        --tmpfs /run \
        --bind-try /run/systemd/resolve /run/systemd/resolve \
        --tmpfs "$HOME" \
        --bind "$PWD" "$PWD" \
        --ro-bind-try "$ZDOTDIR" "$ZDOTDIR" \
        --bind-try /dev/null /usr/bin/distrobox-host-exec \
        --unshare-all --share-net \
        --new-session \
        --die-with-parent \
        --hostname bwrap-sandbox \
        ${BWRAP_EXTRA[@]} \
        "$@"
}

__bwrap-claude() {
    local extras=(
        --bind-try "$HOME/.claude" "$HOME/.claude"
        --bind-try "$HOME/.claude.json" "$HOME/.claude.json"
        --ro-bind-try "$HOME/.local/bin/claude" "$HOME/.local/bin/claude"
        --ro-bind-try "$HOME/.local/share/claude" "$HOME/.local/share/claude"
        --ro-bind-try "$HOME/.config/nvm" "$HOME/.config/nvm"
        --bind-try "$HOME/.cache/ms-playwright" "$HOME/.cache/ms-playwright"
        --bind-try "$HOME/.local/share/pnpm" "$HOME/.local/share/pnpm"
        --bind-try "$HOME/go" "$HOME/go"
    )
    local d
    for d in ${(s.:.)CLAUDE_RO}; do
        extras+=(--ro-bind-try "${d/#\~/$HOME}" "${d/#\~/$HOME}")
    done
    BWRAP_EXTRA=("${BWRAP_EXTRA[@]}" "${extras[@]}") __bwrap claude "$@"
}
alias claude='__bwrap-claude'
