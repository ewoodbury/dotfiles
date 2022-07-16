alias k='kubectl'
alias d='docker'
alias dc='docker-compose'
alias g='git'

# get current branch in git repo
function parse_git_branch() {
	BRANCH=`git branch 2> /dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/\1/'`
	if [ ! "${BRANCH}" == "" ]
	then
        echo "[${BRANCH}] "
	else
		echo ""
	fi
}

function git_branch {
  local git_status="$(git status 2> /dev/null)"
  local on_branch="On branch ([^${IFS}]*)"
  local on_commit="HEAD detached at ([^${IFS}]*)"

  if [[ $git_status =~ $on_branch ]]; then
    local branch=${BASH_REMATCH[1]}
    echo "($branch)"
  elif [[ $git_status =~ $on_commit ]]; then
    local commit=${BASH_REMATCH[1]}
    echo "($commit)"
  fi
}

export PS1="\n\[\e[34m\]\t\[\e[m\] \[\e[33m\]\W\[\e[m\] \[\e[35m\]\`parse_git_branch\`\[\e[m\]\\n\$ "
