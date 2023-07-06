export XDG_CONFIG_HOME=~/.config
export XDG_CACHE_HOME=~/.cache
export XDG_DATA_HOME=~/.local/share

export EDITOR='nvim'
export VISUAL='nvim'
export BROWSER='chromium'

export DEBUGINFOD_URLS="https://debuginfod.archlinux.org"

ZDOTDIR=$XDG_CONFIG_HOME/zsh

typeset -U path  # set unique (fpath has been set unique)
path=(
    $ZDOTDIR/scripts
    /opt/mpich/bin
    ~/.local/bin
    ~/.cargo/bin
    ~/.yarn/bin
    ~/go/bin
    $path
)
