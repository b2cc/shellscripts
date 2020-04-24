# puny personal attempt at a better default .bashrc with git support
# and timestamp on right hand side (to not clutter the prompt)
# ymmv

# If not running interactively, don't do anything
[ -z "$PS1" ] && return

# set term colors via tput (man terminfo)
black=$(tput setaf 0)
red=$(tput setaf 1)
green=$(tput setaf 2)
yellow=$(tput setaf 3)
blue=$(tput setaf 4)
magenta=$(tput setaf 5)
cyan=$(tput setaf 6)
white=$(tput setaf 7)
bold=$(tput bold)
reset=$(tput sgr0)

alias rm='rm -v'
alias cp='cp -v'
alias mv='mv -v'
alias ll='ls -lah --color=auto'
alias grep='grep --color=always'

# ps with tree output
function p() { ps -efww f | egrep -v '\s+\\_\ \[\w+'; }

# alias vi to vim if installed
#if [[ -x /usr/bin/vim ]]; then
#  alias vi='vim'
#fi

export TERM="xterm-256color"
export EDITOR="vim"
export HISTFILE=~/.bash_history
export HISTCONTROL=ignoredups
export HISTFILESIZE=50000
export HISTIGNORE="&:ls:[bf]g:exit:history"
export HISTSIZE=10000
export HISTTIMEFORMAT="%Y-%m-%d %H:%M:%S "

# append on logout
shopt -s histappend

# update the values of LINES and COLUMNS on every command
shopt -s checkwinsize

# correct spelling mistakes on the fly
shopt -s cdspell

# consolidate multi-line commands to single-line
shopt -s cmdhist

# enable forward search (ctrl-s)
stty -ixon

preflight_checks() {
if [[ ${git_prompt_enabled} -ge "1" ]]; then
  BINARIES=(git curl)
  for binary in "${BINARIES[@]}"; do
    if ! [[ -x $(which ${binary} 2>/dev/null) ]]; then
      echo "${binary} binary not found."
      precondition_failed="1"
      break
    fi
  done
fi
}

dl_extension() {
  curl -f -s -m 5 "${GIT_SHELL_EXTENSIONS_URL}/${git_shell_extension}" -o ~/${git_shell_extension} || \
  echo "missing file ${git_shell_extension} and could not grab it from github.com. check network/firewall. prompt may not work as expected."
  precondition_failed="1"
}

enable_extensions() {
GIT_VERSION="$(git --version | awk '{print $3}')"
GIT_SHELL_EXTENSIONS="git-prompt.sh git-completion.bash"
GIT_SHELL_EXTENSIONS_URL="https://raw.githubusercontent.com/git/git/v${GIT_VERSION}/contrib/completion"

# try grabbing git extensions from github if missing
for git_shell_extension in ${GIT_SHELL_EXTENSIONS}; do
  if ! [[ -f ~/${git_shell_extension} ]]; then
    dl_extension
  fi
done

if [[ -f ~/git-prompt.sh ]] && \
   [[ -f ~/git-completion.bash ]] && \
   [[ ${precondition_failed} -eq 0 ]]
then
  #enable_extensions
  GIT_PS1_SHOWCOLORHINTS=1
  GIT_PS1_SHOWDIRTYSTATE=1
  GIT_PS1_SHOWSTASHSTATE=1
  GIT_PS1_SHOWUNTRACKEDFILES=1
  GIT_PS1_SHOWCOLORHINTS=1
  GIT_PS1_SHOWUPSTREAM="auto"
  GIT_PS1_STATESEPARATOR=''
  GIT_PS1_DESCRIBE_STYLE="branch"
  source ~/git-prompt.sh
  source ~/git-completion.bash
fi
}

_bash_prompt_set() {
  PS1="\[$green$bold\]\u\[$reset\]@\[$green$bold\]\h\[$reset\]:\w${git} \$ "
  printf -v PS1RHS "\e[0m[ \e[0m\e[0;1;37m%(%Y-%m-%d %H:%M)T\e[0m ]" -1
  PS1RHS_stripped=$(sed "s,\x1B\[[0-9;]*[a-zA-Z],,g" <<<"$PS1RHS")
  local Save='\e[s'
  local Rest='\e[u'
  PS1="\[${Save}\e[${COLUMNS:-$(tput cols)}C\e[${#PS1RHS_stripped}D${PS1RHS}${Rest}\]${PS1}"
  local user_shopt
  user_shopt=$(shopt -p promptvars extglob)
  shopt -qu promptvars
  shopt -qs extglob
  local old_PS1=$PS1
  __git_ps1 "" "" " (%s)"
  git=${PS1//@(\\@(\[|\]))/}
  PS1=$old_PS1
  eval "$user_shopt"
}

precondition_failed="0"

# bash completion
if [[ -f /etc/profile.d/bash_completion.sh ]]; then
  source /etc/profile.d/bash_completion.sh
else
  precondition_failed="1"
fi

git_prompt_enabled="1"
if [[ ${git_prompt_enabled} -eq 1 ]]; then
  preflight_checks
  enable_extensions
fi

PROMPT_COMMAND='history -a; history -c; history -r; _bash_prompt_set'

# display a fancy logo
#/usr/bin/linuxlogo -F "Logged on to: #H\n\nKernel: #V\n#C\n#X #T #N #P #M, #R RAM\n#L\n#U\n" -L 9

