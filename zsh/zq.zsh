# QC's Zsh Plugin Manager
#
# Usage:
#
#   $ zq plug romkatv/zsh-no-ps2                 # load plugin
#   $ zq plug ohmyzsh/ohmyzsh plugins/sudo       # load plugin in specific sub-folder
#   $ zq plug ohmyzsh/ohmyzsh lib/clipboard.zsh  # load specific shell script
#   $ zq update                                  # update all plugins
#   $ zq outdated 7 && zq update                 # update every 7 days
#   $ zstyle ':zq:*' cooldown 7                  # updates lag upstream by 7 days
#   $ zstyle ':zq:ohmyzsh/ohmyzsh' cooldown 14   # per-plugin cooldown
#
# Files are stored at `$ZQ_DIR`, which is `~/.local/share/zq` by default.
#
# To mitigate supply chain attacks, updates lag upstream by the cooldown in days
# (7 by default). `zq update` moves to the upstream tip as this machine fetched
# it that many days ago, cut back to what upstream still has. Timestamps come
# from the local reflog, never from commit dates, which upstream controls. So a
# commit upstream removes within the cooldown is never installed, and one
# already installed is moved off, to a delayed commit or else back to the
# history it shares with upstream, never to an undelayed tip.
#
# The cooldown of a commit starts when `zq update` first fetches it, so the
# time between updates adds to the lag: updating every 7 days with a cooldown
# of 7 installs a commit 7 to 14 days after upstream pushed it. `zq plug`
# installs new plugins at the upstream tip, since there is no fetch history to
# delay against yet. A plugin with local commits is left alone.

ZQ_DIR=${ZQ_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/zq}

zq() {
    emulate -LR zsh -o extended_glob -o err_return
    _zq-$1 "${@:2}"
}

_zq-plug() {  # <repo> [<dir>|<file>]
    local repo_dir=$ZQ_DIR/repos/$1
    if [[ ! -d $repo_dir ]] {
        printf "\e[1m\e[33m$1\e[0m\n"
        git clone --depth=1 https://github.com/$1 $repo_dir
        git -C $repo_dir update-ref refs/zq/installed HEAD
        _zq-compile $repo_dir
    }

    if [[ $2 == '' ]] {
        local targets=($repo_dir/${1:t}.{zsh-theme,plugin.zsh}(N))
    } elif [[ -d $repo_dir/$2 ]] {
        local targets=($repo_dir/$2/*.{zsh-theme,plugin.zsh}(N))
    } else {
        local targets=($repo_dir/$2)
    }
    source $targets[1]
}

_zq-update() {
    autoload -Uz zargs
    zmodload -F zsh/datetime p:EPOCHSECONDS
    zargs -P8 -l1 -r -- $ZQ_DIR/repos/*/*(N/) -- _zq-update-repo
    mkdir -p $ZQ_DIR && touch $ZQ_DIR/update
}

# Failures are reported per repo and return 0, so one bad repo neither aborts
# `zq update` nor keeps it from recording the update.
_zq-update-repo() {  # <dir>
    local -a git=(git -C $1)
    local output ref target head installed from days
    zstyle -s ":zq:${1:h:t}/${1:t}" cooldown days || days=7
    if [[ $days != <-> ]] {
        _zq-warn $1 "cooldown '$days' is not a number of days, not updating"
        return 0
    }
    if ! ref=$(_zq-fetch $1 2>&1) && ! { _zq-follow-head $1 && ref=$(_zq-fetch $1 2>&1) }; then
        _zq-warn $1 'cannot fetch the default branch, not updating' $ref
        return 0
    fi
    if ! head=$($git rev-parse -q --verify HEAD 2>/dev/null); then
        _zq-warn $1 'no commit is checked out, not updating'
        return 0
    fi
    # Without a record (installed by an older zq), assume zq checked out HEAD.
    installed=$($git rev-parse -q --verify refs/zq/installed 2>/dev/null) || installed=$head

    local removed=0
    if ! $git merge-base --is-ancestor $head $ref 2>/dev/null; then
        if [[ $head != $installed ]] {
            _zq-warn $1 "checked-out ${head[1,12]} has local commits, not updating"
            return 0
        }
        # Upstream removed the commit zq installed. A shallow clone cuts off the
        # history needed to find what is still shared, so fetch the rest of it.
        removed=1
        if [[ $($git rev-parse --is-shallow-repository 2>/dev/null) == true ]] {
            $git fetch -q --unshallow &>/dev/null || true
        }
    fi

    # Reflog entries are newest first, stamped with local fetch time.
    local cutoff=$(( EPOCHSECONDS - days * 86400 )) entry ts
    for entry in ${(f)"$($git reflog --format='%H %gd' --date=unix $ref 2>/dev/null)"}; {
        ts=${${entry##*\{}%\}}
        if [[ $ts != <-> ]] {
            _zq-warn $1 "unexpected reflog entry '$entry', not updating"
            return 0
        }
        (( ts <= cutoff )) && { target=${entry%% *}; break }
    }
    # Drop anything upstream has removed since.
    [[ -z $target ]] || target=$($git merge-base $target $ref 2>/dev/null) || target=

    if (( removed )) {
        # Nothing delayed to move to: fall back to the history shared with upstream.
        if [[ -z $target ]] && ! target=$($git merge-base $head $ref 2>/dev/null); then
            _zq-warn $1 "checked-out ${head[1,12]} was removed upstream and shares no history with it, not updating"
            return 0
        fi
        _zq-warn $1 "checked-out ${head[1,12]} was removed upstream, moving to ${target[1,12]}"
    } elif [[ -z $target || $head == $target ]] || ! $git merge-base --is-ancestor $head $target 2>/dev/null; then
        # Nothing has cooled down yet, or HEAD is at or past the delayed tip, e.g.
        # after raising the cooldown. Only ever move forward from a commit that is
        # still upstream.
        return 0
    fi

    from=$($git merge-base $head $target 2>/dev/null) || from=
    output=${from:+$($git -c color.ui=always log --oneline --no-decorate $from..$target 2>&1)} || output=
    [[ -n $output ]] ||
        output="now at $($git -c color.ui=always log -1 --oneline --no-decorate $target 2>&1)" || true
    if ! entry=$($git -c advice.detachedHead=false checkout -q --detach $target 2>&1); then
        _zq-warn $1 'checkout failed' $entry
        return 0
    fi
    $git update-ref refs/zq/installed $target || true
    _zq-compile $1
    printf '\e[1m\e[33m%s\e[0m\n%s\n' ${1:h:t}/${1:t} $output
}

# Fetches and prints the remote-tracking ref of the upstream default branch.
# The cooldown is measured on the reflog, so always write it and never expire it.
_zq-fetch() {  # <dir>
    git -C $1 -c core.logAllRefUpdates=true -c gc.reflogExpire=never \
        -c gc.reflogExpireUnreachable=never -c remote.origin.followRemoteHEAD=always fetch -q &&
        git -C $1 symbolic-ref -q refs/remotes/origin/HEAD
}

# Points origin/HEAD at the upstream default branch, for when it is unset or
# upstream renamed the only branch a shallow clone tracks.
_zq-follow-head() {  # <dir>
    local -a git=(git -C $1)
    local line
    $git remote set-head origin --auto &>/dev/null && return 0
    line=$($git ls-remote --symref origin HEAD 2>/dev/null) || return 1
    [[ $line == 'ref: refs/heads/'* ]] || return 1
    line=${${line#ref: refs/heads/}%%[[:space:]]*}
    # The caller fetches the branch, so that its reflog starts there.
    $git remote set-branches origin $line &>/dev/null &&
        $git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/$line
}

_zq-compile() {  # <dir>
    local file
    { for file in $1/**/*.zsh{,-theme}(N.); zcompile $file; } &!
}

_zq-warn() {  # <dir> <message> [<details>]
    printf '\e[1m\e[31m%s\e[0m: %s\n%s' ${1:h:t}/${1:t} $2 ${3:+$3$'\n'}
}

_zq-outdated() {  # <days>
    local last_update=($ZQ_DIR/update(Nm-$1))
    [[ $last_update == '' ]]
}
