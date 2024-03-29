#!/bin/zsh

CYAN='\033[0;36m'
NC='\033[0m'  # No Color

DOT_DIR=${0:a:h}  # the directory of this script

pf_loc=()  # profile locations
pf_pat=()  # profile patterns

declare -A pf_map   # <pf-name> : <idxes>

_add-pf() {  # <pf-name> {<pf-loc> <pf-pat>}...
    local name=${1%.pf}
    for i in {2..$#@..2}; {
        pf_loc+=($@[i])
        pf_pat+=($@[i+1])
        pf_map[$name]+="$#pf_loc "
    }
}
alias -s pf='_add-pf'

_rsync-pat() {  # <src> <dst> <pat>
    cd $1 && rsync $rsync_opt --relative $~=3 $2/
}

_sync() {  # <pf-name>
    for i in $=pf_map[$1]; {
        local changes=$(_rsync-pat $pf_loc[i] $DOT_DIR/$1 $pf_pat[i])
        if [[ $changes != '' ]] {
            echo $CYAN"$1 <- ${(D)pf_loc[i]}"$NC
            echo $changes
            echo
        }
    }
}

_apply() {  # <pf-name>
    for i in $=pf_map[$1]; {
        local changes=$(_rsync-pat $DOT_DIR/$1 $pf_loc[i] $pf_pat[i])
        if [[ $changes != '' ]] {
            echo $CYAN"$1 -> ${(D)pf_loc[i]}"$NC
            echo $changes
            echo
        }
    }
}

source $(which env_parallel.zsh)

_init() {
    setopt null_glob extended_glob
}

_for-each-pf() {  # <func> [--all | <pf-name>...]
    local func=$1; shift
    if [[ $1 == --all ]] {
        env_parallel "_init; $func" ::: ${(k)pf_map}
    } else {
        env_parallel "_init; $func" ::: ${(u)@}
    }
}

cute-dot-list()  { printf '%s\n' ${(ko)pf_map} }
cute-dot-sync()  { _for-each-pf _sync $@ }
cute-dot-apply() { _for-each-pf _apply $@ }

# =============================== Config Begin =============================== #

rsync_opt=(
    '--recursive'
    '--mkpath'
    '--checksum'
    '--itemize-changes'
)

zsh.pf \
    ~ '.zshenv' \
    ~/.config/zsh '.zshrc *.zsh */^*.zwc'

# systemd.pf \
#     ~/.config 'user-tmpfiles.d/*'

gpg.pf \
    ~/.gnupg 'gpg.conf gpg-agent.conf'

# ssh.pf \
#     ~/.ssh 'config'

git.pf \
    ~ '.gitconfig'

# proxychains.pf \
#     ~/.proxychains 'proxychains.conf'

cargo.pf \
    ~/.cargo 'config.toml'

# ghc.pf \
#     ~/.ghc 'ghci.conf'

pip.pf \
    ~/.config/pip '*'

# ipython.pf \
#     ~/.ipython/profile_default 'ipython_config.py'

# direnv.pf \
#     ~/.config/direnv '*'

# fontconfig.pf \
#     ~/.config/fontconfig '*'

# paru.pf \
#     ~/.config/paru '*'

# clang/clang-format.pf \
#     ~ '.clang-format'

# clang/clangd.pf \
#     ~/.config/clangd '*'

go.pf \
    ~/.config/go 'env'

# npm.pf \
#     ~ '.npmrc'

yarn.pf \
    ~ '.yarnrc.yml'

vscode-server.pf \
    ~/.vscode-server/data/Machine/ '*'

# vscode-server-insiders.pf \
#     ~/.vscode-server-insiders/data/Machine/ '*'

# docker.pf \
#     ~/.docker 'config.json'

pkglist.pf \
    ~/.config 'pkglist.txt'

# ================================ Config End ================================ #

cp /etc/pkglist.txt ~/.config
cute-dot-$1 ${@:2}
