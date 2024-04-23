#!/bin/zsh

DOT=${0:a:h}  # the directory of this script

declare -A pf_map

_add-pf() { pf_map[${2%.*}]+="$1 $3 $4 " }
alias -s pf="_add-pf $USER"
alias -s rpf="_add-pf root"

_rsync-pf() {  # ←|→ <pf-name>
    setopt extended_glob
    for own loc pat in $=pf_map[$2]; case $1@$own {
        (←@*)          rsync $rsync_opts -R $loc/./$~pat $DOT/$2/ ;;
        (→@$USER)      rsync $rsync_opts -R $DOT/$2/./$~pat $loc/ ;;
        (→@root)  sudo rsync $rsync_opts -R $DOT/$2/./$~pat $loc/ ;;
    }
}

_rsync-each-pf() {  # ←|→ [--all|<pf-name>...]
    [[ $2 == --all ]] && set -- $1 ${(k)pf_map}
    source env_parallel.zsh
    sudo true  # refresh cache
    env_parallel --ctag "_rsync-pf $1" ::: ${@:2}
}

cute-dot-sync()  { _rsync-each-pf ← $@ }
cute-dot-apply() { _rsync-each-pf → $@ }

# =============================== Config Begin =============================== #

rsync_opts=(
    # --dry-run
    --recursive
    --mkpath
    --checksum
    --itemize-changes
)

zsh.pf ~ '.zshenv'
zsh.pf ~/.config/zsh '.zshrc|^*.zwc'
p10k.pf ~/.config/zsh '.p10k.zsh'
zshrcd.pf ~/.config/zshrc.d '*'
gpg.pf ~/.gnupg 'gpg.conf|gpg-agent.conf'
git.pf ~ '.gitconfig'
cargo.pf ~/.cargo 'config.toml'
pip.pf ~/.config/pip '*'
go.pf ~/.config/go 'env'
hypr.pf ~/.config/hypr '*'
alacritty.pf ~/.config/alacritty '*'
yarn.pf ~ '.yarnrc.yml'
vscode-server.pf ~/.vscode-server/data/Machine/ '*'

sshd.rpf /etc/ssh 'sshd_config|moduli'
pkglist.rpf /etc 'pkglist.txt'

# ================================ Config End ================================ #

cute-dot-$1 ${@:2}
