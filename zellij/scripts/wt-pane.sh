#!/usr/bin/env bash
# wt-pane.sh — coordinate worktree detection across zellij panes
#
# The "agent" pane snapshots existing git worktrees, then starts the agent with -w.
# A background watcher detects the new worktree (via git worktree list) and writes
# its path to a signal file keyed on ZELLIJ_SESSION_NAME.
# The "nvim" and "terminal" panes wait for that signal, cd there, and start.
#
# Usage (called from zellij layout):
#   wt-pane.sh agent
#   wt-pane.sh nvim
#   wt-pane.sh terminal

MODE="${1:-terminal}"
SIGNAL="/tmp/agent-wt-${ZELLIJ_SESSION_NAME:-$$}"

case "$MODE" in
  agent)
    rm -f "$SIGNAL"
    # Snapshot existing worktrees before agent creates a new one
    BEFORE=$(git worktree list --porcelain 2>/dev/null | grep '^worktree ' | sort)
    # Background watcher: compare worktree list every second for up to 60s
    (
      for i in $(seq 1 60); do
        sleep 1
        AFTER=$(git worktree list --porcelain 2>/dev/null | grep '^worktree ' | sort)
        NEW=$(comm -13 <(printf '%s\n' "$BEFORE") <(printf '%s\n' "$AFTER") | head -1)
        if [[ -n "$NEW" ]]; then
          printf '%s' "${NEW#worktree }" > "$SIGNAL"
          break
        fi
      done
    ) &
    exec agent -w
    ;;

  nvim)
    # Wait up to 30s for agent to create the worktree
    for i in $(seq 1 30); do
      if [[ -f "$SIGNAL" ]]; then
        cd "$(cat "$SIGNAL")" 2>/dev/null && break
      fi
      sleep 1
    done
    SOCK="/tmp/nvim-zellij.sock"
    rm -f "$SOCK"
    exec nvim --listen "$SOCK"
    ;;

  terminal)
    # Wait up to 30s for agent to create the worktree
    for i in $(seq 1 30); do
      if [[ -f "$SIGNAL" ]]; then
        cd "$(cat "$SIGNAL")" 2>/dev/null && break
      fi
      sleep 1
    done
    exec bash --login
    ;;
esac
