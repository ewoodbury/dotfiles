# Ghostty shell integration for Bash. This must be at the very top!
if [ -n "${GHOSTTY_RESOURCES_DIR}" ]; then
    builtin source "${GHOSTTY_RESOURCES_DIR}/shell-integration/bash/ghostty.bash"
fi

alias k='kubectl'
alias d='docker'
alias dc='docker-compose'

# User-local binaries (gh, zellij, nvim, agent, ...)
export PATH="$HOME/.local/bin:$PATH"
export EDITOR=nvim VISUAL=nvim

alias g='git'
# Enhanced git status (colored + grouped)
function gs() {
	_in_git_repo || { echo "not a git repo"; return 1; }
	local colored raw
	colored=$(git -c color.status=always status -sb 2>&1) || { echo "$colored"; return 1; }
	raw=$(git status -sb 2>/dev/null)
	local -a c_lines=() r_lines=()
	while IFS= read -r line; do c_lines+=("$line"); done <<< "$colored"
	while IFS= read -r line; do r_lines+=("$line"); done <<< "$raw"

	local branch="" untracked="" deleted="" modified=""
	local i
	for (( i=0; i<${#r_lines[@]}; i++ )); do
		local r="${r_lines[$i]}" c="${c_lines[$i]}"
		if [[ "$r" == "##"* ]]; then
			branch="$c"
		elif [[ "$r" == "??"* ]]; then
			untracked+="$c"$'\n'
		elif [[ "$r" == D* || "$r" == " D"* ]]; then
			deleted+="$c"$'\n'
		else
			modified+="$c"$'\n'
		fi
	done
	[[ -n "$branch" ]] && echo "$branch"
	local need_sep=false
	if [[ -n "$untracked" ]]; then
		printf "%s" "$untracked"
		need_sep=true
	fi
	if [[ -n "$deleted" ]]; then
		$need_sep && echo ""
		printf "%s" "$deleted"
		need_sep=true
	fi
	if [[ -n "$modified" ]]; then
		$need_sep && echo ""
		printf "%s" "$modified"
	fi
}
alias glog="git log --graph --pretty=format:'%Cred%h%Creset %an: %s - %Creset %C(yellow)%d%Creset %Cgreen(%cr)%Creset' --abbrev-commit --date=relative"
alias ga='git add'
alias gc='git commit -m'
alias gp='git push'

# Fast pure-bash check: are we inside a git worktree?
_in_git_repo() {
	local dir="$PWD"
	while [[ -n "$dir" ]]; do
		[[ -e "$dir/.git" ]] && return 0
		dir="${dir%/*}"
	done
	return 1
}

# get current branch in git repo (works with worktrees)
function parse_git_branch() {
	local dir="$PWD" head
	while [[ -n "$dir" ]]; do
		if [[ -f "$dir/.git/HEAD" ]]; then
			read -r head < "$dir/.git/HEAD"
			case "$head" in
				ref:*) echo "[${head#ref: refs/heads/}] " ;;
				*)     echo "[${head:0:7}] " ;;
			esac
			return
		elif [[ -f "$dir/.git" ]]; then
			# git worktree/submodule: .git is a file, fall back to git command
			local branch
			branch=$(git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null)
			[[ -n "$branch" ]] && echo "[$branch] "
			return
		fi
		dir="${dir%/*}"
	done
}

# Tab / window title: show "dir | zellij" when inside Zellij (Ghostty picks this up)
if [[ -n "${ZELLIJ:-}" ]]; then
	export PS1="\[\e]0;\W | zellij\a\]\n\[\e[34m\]\t\[\e[m\] \[\e[33m\]\W\[\e[m\] \[\e[35m\]\`parse_git_branch\`\[\e[m\]\\n\$ "
else
	export PS1="\[\e]0;\W\a\]\n\[\e[34m\]\t\[\e[m\] \[\e[33m\]\W\[\e[m\] \[\e[35m\]\`parse_git_branch\`\[\e[m\]\\n\$ "
fi

# Enable autocomplete for git:
if [ -f ~/.git-completion.bash ]; then
  . ~/.git-completion.bash
fi

# Zellij helpers — nice session names + layout shortcuts
# Usage:
#   zlc          → launch "coding" layout, session named after current dir
#   zlcw         → launch "coding-wt" (worktree + agent) layout
#   zlt          → launch "terminal" layout
#   z2 / z3      → launch "z2" / "z3" side-by-side panes (full height)
# All take an optional session-name argument.
_zj_launch() {
	local base="${1:-$(basename "$PWD")}" layout="$2"
	local name="$base" i=2
	local sessions
	sessions=$(zellij list-sessions -n 2>/dev/null)
	while true; do
		local line
		line=$(printf '%s\n' "$sessions" | awk -v n="$name" '$1 == n')
		if [[ -z "$line" ]]; then
			break  # name is free
		elif [[ "$line" == *EXITED* ]]; then
			zellij delete-session "$name" 2>/dev/null
			break  # cleaned up dead session, reuse name
		else
			name="${base}-${i}"
			((i++))
		fi
	done
	zellij -s "$name" --new-session-with-layout "$layout"
}

# Zellij layouts
zlc()  { _zj_launch "$1" coding; }
zlt()  { _zj_launch "$1" terminal; }
zlcw() { _zj_launch "$1" coding-wt; }
z2()   { _zj_launch "$1" z2; }
z3()   { _zj_launch "$1" z3; }

# Smart nvim wrapper for Zellij layouts.
# Prefers the stable /tmp/nvim-zellij.sock (used by coding layouts),
# then falls back to a per-session socket so multiple Zellij sessions
# don't fight over the same nvim server.
nvim() {
	local sock
	for sock in "/tmp/nvim-zellij.sock" "/tmp/nvim-${ZELLIJ_SESSION_NAME:-main}.sock"; do
		if [[ -S "$sock" ]] && command nvim --server "$sock" --remote-expr '1' &>/dev/null; then
			command nvim --server "$sock" --remote "$@"
			return
		fi
	done
	# No existing server — start one (prefer layout socket when possible)
	sock="/tmp/nvim-${ZELLIJ_SESSION_NAME:-main}.sock"
	rm -f "$sock"
	command nvim --listen "$sock" "$@"
}


# Run `gcm` to commit changes with an AI-generated commit message by Andrej Karpathy: https://gist.github.com/karpathy/1dd0294ef9567971c1e4348a90d69285
# Be sure to download ollama, then run `ollama run llama3.1` to install llama
# -----------------------------------------------------------------------------
# AI-powered Git Commit Function
# Copy paste this gist into your ~/.bashrc or ~/.zshrc to gain the `gcm` command. It:
# 1) gets the current staged changed diff
# 2) sends them to an LLM to write the git commit message
# 3) allows you to easily accept, edit, regenerate, cancel
# But - just read and edit the code however you like
# the `llm` CLI util is awesome, can get it here: https://llm.datasette.io/en/stable/

gcm() {
    # Function to generate commit message
    generate_commit_message() {
        git diff --cached | ollama run llama3.1 "
Below is a diff of all staged changes, coming from the command:

\`\`\`
git diff --cached
\`\`\`

Please generate a concise, one-line commit message for these changes. Respond with only the message with no other text."
    }

    # Function to read user input compatibly with both Bash and Zsh
    read_input() {
        if [ -n "$ZSH_VERSION" ]; then
            echo -n "$1"
            read -r REPLY
        else
            read -p "$1" -r REPLY
        fi
    }

    # Main script
    echo "Generating AI-powered commit message..."
    commit_message=$(generate_commit_message)

    while true; do
        echo -e "\nProposed commit message:"
        echo "$commit_message"

        read_input "Do you want to (a)ccept, (e)dit, (r)egenerate, or (c)ancel? "
        choice=$REPLY

        case "$choice" in
            a|A )
                if git commit -m "$commit_message"; then
                    echo "Changes committed successfully!"
                    return 0
                else
                    echo "Commit failed. Please check your changes and try again."
                    return 1
                fi
                ;;
            e|E )
                read_input "Enter your commit message: "
                commit_message=$REPLY
                if [ -n "$commit_message" ] && git commit -m "$commit_message"; then
                    echo "Changes committed successfully with your message!"
                    return 0
                else
                    echo "Commit failed. Please check your message and try again."
                    return 1
                fi
                ;;
            r|R )
                echo "Regenerating commit message..."
                commit_message=$(generate_commit_message)
                ;;
            c|C )
                echo "Commit cancelled."
                return 1
                ;;
            * )
                echo "Invalid choice. Please try again."
                ;;
        esac
    done
}
