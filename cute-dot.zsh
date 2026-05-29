#!/bin/zsh

DOT=${0:a:h}  # the directory of this script

declare -A pf_map

_add-pf() { pf_map[${2%.*}]+="$1 $3 $4 "; }
alias -s pf="_add-pf self"
alias -s rpf="_add-pf root"

_rsync-pf() {  # sync|apply <pf-name>
    setopt extended_glob
    local output=$(for own loc pat in $=pf_map[$2]; case $1-$own {
        (sync-*)          rsync $rsync_opts -R $loc/./$~pat $DOT/$2/ ;;
        (apply-self)      rsync $rsync_opts -R $DOT/$2/./$~pat $loc/ ;;
        (apply-root) sudo rsync $rsync_opts -R $DOT/$2/./$~pat $loc/ ;;
    })
    [[ $output == '' ]] || printf "\e[1m\e[33m$2\e[0m\n$output\n"
}

_rsync-each-pf() {  # sync|apply [--all|<pf-name>...]
    [[ $2 == --all ]] && set -- $1 ${(k)pf_map}
    [[ $1 == apply ]] && sudo -v
    autoload -Uz zargs
    # FIXME: Weird 123 return code on macOS, could be a zargs bug.
    zargs -P0 -l1 -r -- ${@:2} -- _rsync-pf $1
}

# =============================== Config Begin =============================== #

rsync_opts=(
    # --dry-run
    --recursive
    --mkpath
    --checksum
    --itemize-changes
)

zsh.pf ~ '.zshenv'
zsh.pf ~/.config/zsh '.zshrc|^*.zwc|.p10k.zsh'
zshrcd.pf ~/.config/zshrc.d '*'
gpg.pf ~/.gnupg 'gpg.conf|gpg-agent.conf'
git.pf ~ '.gitconfig'
cargo.pf ~/.cargo 'config.toml'
pip.pf ~/.config/pip '*'
go.pf ~/.config/go 'env'
alacritty.pf ~/.config/alacritty '*'
yarn.pf ~ '.yarnrc.yml'
vscode-server.pf ~/.vscode-server/data/Machine/ '*'
containers.pf ~/.config/containers '*'

sshd.rpf /etc/ssh 'sshd_config'
pkglist.rpf /etc 'pkglist.txt'

# ================================ Config End ================================ #

_rsync-each-pf $@
