# puny personal attempt at a better default .bashrc with git support
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

# git support
# check for git completion files and download if needed
curl_missing="0"
git_prompt_enabled="0"
if ! [[ -x $(which curl 2>/dev/null) ]]; then curl_missing="1"; fi

GIT_SHELL_EXTENSIONS="git-prompt.sh git-completion.bash"
GIT_SHELL_EXTENSIONS_URL="https://raw.githubusercontent.com/git/git/master/contrib/completion"

for extension in ${GIT_SHELL_EXTENSIONS[@]}; do
  if ! [[ -f ~/${extension} ]]; then
    if [[ ${curl_missing} -eq "1" ]]; then
      echo "curl binary missing, can't auto-install shell extension ${extension} for git."
    else
      curl -f -s -m 3 "${GIT_SHELL_EXTENSIONS_URL}/${extension}" -o ~/${extension} || echo "missing file ${extension} and could not grab it from intx git server. check network/firewall. prompt may not work as expected."
    fi
  fi
  if [[ -f ~/${extension} ]]; then source ~/${extension} && git_prompt_enabled="1"; fi
done

if [[ ${git_prompt_enabled} -eq "1" ]]; then
  GIT_PS1_SHOWDIRTYSTATE=1
  GIT_PS1_SHOWSTASHSTATE=1
  GIT_PS1_SHOWUNTRACKEDFILES=1
  GIT_PS1_SHOWCOLORHINTS=1
  GIT_PS1_SHOWUPSTREAM="auto"
  GIT_PS1_DESCRIBE_STYLE="branch"
  PROMPT_COMMAND='history -a; history -c; history -r; __git_ps1 "\[$green$bold\]\u\[$reset\]@\[$green$bold\]\h\[$reset\]:\w" " \\\$ "'
else
  PROMPT_COMMAND='history -a; history -c; history -r; PS1="\[$green$bold\]\u\[$reset\]@\[$green$bold\]\h\[$reset\]:\w # "'
fi

# display a fancy logo
#/usr/bin/linuxlogo -F "Logged on to: #H\n\nKernel: #V\n#C\n#X #T #N #P #M, #R RAM\n#L\n#U\n" -L 9

