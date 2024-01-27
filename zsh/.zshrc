# >>> p10k instant prompt >>>
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi
# <<< p10k instant prompt <<<

alias diff='diff --color=auto'
alias grep='grep --color=auto'
alias ip='ip -color=auto'
export LESS='-R --use-color -Dd+r$Du+b'
alias ls='ls --color=auto'
alias cat='bat'
export MANPAGER="sh -c 'col -bx | bat -l man -p --theme=\"Monokai Extended Bright\"'"
export MANROFFOPT="-c"
export BAT_THEME='Visual Studio Dark+'
alias git-nosign="git -c commit.gpgsign=false"
# export CUDAToolkit_ROOT='/opt/cuda'

cleanup() {
    find . -name "$1" -type d -prune -exec rm -r '{}' +
    find . -name "$1" -type f -prune -exec rm '{}' +
}

# >>> proxy >>>
proxy() {
    export http_proxy="http://192.168.254.1:17992"
    export https_proxy="http://192.168.254.1:17992"
}

unsetproxy() {
    unset http_proxy
    unset https_proxy
}
# <<< proxy <<<

ipv624() {
    readonly port=${1:?"The port must be specified."}
    socat TCP4-LISTEN:${port},fork TCP6:\[::\]:${port}
}

docker_prune_build_cache() {
    docker buildx prune --filter=unused-for=120h
}

bell() {
    repeat ${1:-10} do
        printf '\a';
        sleep ${2:-0.5};
    done
}

# zsh misc
setopt auto_cd               # simply type dir name to cd
setopt auto_pushd            # make cd behaves like pushd
setopt pushd_ignore_dups     # don't pushd duplicates
setopt pushd_minus           # exchange the meanings of `+` and `-` in pushd
setopt interactive_comments  # comments in interactive shells
setopt multios               # multiple redirections
setopt ksh_option_print      # make setopt output all options
setopt extended_glob         # extended globbing
unsetopt beep                # no beep
WORDCHARS='*?_-.[]~=&;!#$%^(){}<>'  # remove '/'

# zsh history
setopt hist_ignore_all_dups  # no duplicates
setopt hist_save_no_dups     # don't save duplicates
setopt hist_ignore_space     # no commands starting with space
setopt hist_reduce_blanks    # remove all unneccesary spaces
setopt share_history         # share history between sessions
[ -z "$HISTFILE" ] && HISTFILE="$ZDOTDIR/.zsh_history"
HISTSIZE=290000
SAVEHIST=$HISTSIZE


# >>> zinit >>>
if [[ ! -f $HOME/.local/share/zinit/zinit.git/zinit.zsh ]]; then
    print -P "%F{33} %F{220}Installing %F{33}ZDHARMA-CONTINUUM%F{220} Initiative Plugin Manager (%F{33}zdharma-continuum/zinit%F{220})…%f"
    command mkdir -p "$HOME/.local/share/zinit" && command chmod g-rwX "$HOME/.local/share/zinit"
    command git clone https://github.com/zdharma-continuum/zinit "$HOME/.local/share/zinit/zinit.git" && \
        print -P "%F{33} %F{34}Installation successful.%f%b" || \
        print -P "%F{160} The clone has failed.%f%b"
fi

source "$HOME/.local/share/zinit/zinit.git/zinit.zsh"
autoload -Uz _zinit
(( ${+_comps} )) && _comps[zinit]=_zinit
# <<< zinit <<<

zicompinit

zinit light-mode for \
    OMZL::completion.zsh

zinit wait="1" lucid for \
    OMZL::clipboard.zsh \
    OMZL::git.zsh \
    OMZP::systemd/systemd.plugin.zsh \
    OMZP::sudo/sudo.plugin.zsh \
    OMZP::extract/extract.plugin.zsh \
    OMZP::git/git.plugin.zsh

zinit light fourdim/zsh-archlinux
zinit light fourdim/zsh-pack
zinit light fourdim/zsh-poetry

# Load a few important annexes, without Turbo
# (this is currently required for annexes)
zinit light-mode for \
    zdharma-continuum/zinit-annex-as-monitor \
    zdharma-continuum/zinit-annex-bin-gem-node \
    zdharma-continuum/zinit-annex-patch-dl \
    zdharma-continuum/zinit-annex-rust \
    zdharma-continuum/history-search-multi-word

zinit light Aloxaf/fzf-tab

zinit light-mode for \
    zsh-users/zsh-autosuggestions \
    zdharma-continuum/fast-syntax-highlighting

#nvm
export NVM_DIR="$HOME/.config/nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm

# fzf
export FZF_DEFAULT_OPTS='--ansi --height=60% --reverse --cycle --bind=tab:accept'

# gpg
export GPG_TTY=$TTY

# term
export TERM=alacritty

# vscode
if command -v code-insiders > /dev/null; then
    alias code=code-insiders
fi

# nvim
if command -v nvim > /dev/null; then
    alias vim=nvim
fi

if command -v code > /dev/null; then
    alias zshrc='code ~/.config/zsh/.zshrc'
else
    alias zshrc='vim ~/.config/zsh/.zshrc'
fi

# CMake
export CMAKE_GENERATOR="Ninja"

# Electron
export ELECTRON_MIRROR="https://npmmirror.com/mirrors/electron/"

# fzf-tab
zstyle ':fzf-tab:*' fzf-command ftb-tmux-popup
zstyle ':fzf-tab:*' fzf-bindings 'tab:accept'
zstyle ':fzf-tab:*' switch-group ',' '.'
zstyle ':fzf-tab:complete:kill:argument-rest' fzf-preview 'ps --pid=$word -o cmd --no-headers -w -w'
zstyle ':fzf-tab:complete:kill:argument-rest' fzf-flags '--preview-window=down:3:wrap'
zstyle ':fzf-tab:complete:kill:*' popup-pad 0 3


### End of Zinit's installer chunk

zinit ice depth=1; zinit light romkatv/powerlevel10k

[[ ! -f ${ZDOTDIR}/.p10k.zsh ]] || source ${ZDOTDIR}/.p10k.zsh

precmd () { echo -n "\x1b]1337;CurrentDir=$(pwd)\x07" }

gpgconf --create-socketdir

[ -f "/home/fourdim/.ghcup/env" ] && source "/home/fourdim/.ghcup/env" # ghcup-env
# bun completions
[ -s "/home/fourdim/.bun/_bun" ] && source "/home/fourdim/.bun/_bun"

# pnpm
export PNPM_HOME="/home/fourdim/.local/share/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac
# pnpm end

export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"
