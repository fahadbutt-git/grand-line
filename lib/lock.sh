# shellcheck shell=bash
# One run at a time: a lock that a crash never leaves stuck.
#
# The lock is a folder, made with mkdir (which only one process can win).
# Its owner file holds the holder's process ID and that process's start
# time, so a lock is stale when its process is gone, or when the ID now
# belongs to another process (IDs are reused). A lock whose holder died
# before writing its name (between mkdir and the write) is stale once it is
# a minute old. A stale lock is broken by one taker at a time: breaking
# needs a second lock (LOCK.break), and the lock is checked again while it
# is held, so two takers can never both win.
# Used by lib/auto-update.sh (update.lock) and bin/tidy-downloads.

# lock_proc_id PID: "PID start-time" for a running process, or nothing.
lock_proc_id() {
  local start
  start="$(LC_ALL=C ps -o lstart= -p "$1" 2>/dev/null | sed 's/^ *//; s/ *$//')"
  [[ -n "$start" ]] || return 1
  printf '%s %s\n' "$1" "$start"
}

# lock_owner LOCK: what the holder wrote (also reads the older pid file).
lock_owner() {
  cat "$1/owner" 2>/dev/null || cat "$1/pid" 2>/dev/null
}

# lock_stale LOCK: the lock is left over from a run that no longer exists.
lock_stale() {
  local lock="$1" owner pid
  [[ -d "$lock" ]] || return 1
  owner="$(lock_owner "$lock")"
  if [[ -z "$owner" ]]; then
    [[ -n "$(find "$lock" -maxdepth 0 -mmin +1 2>/dev/null)" ]]
    return
  fi
  pid="${owner%% *}"
  [[ "$pid" =~ ^[0-9]+$ ]] || return 0
  # kill -0 fails for a live process of another user, so ps has the last word.
  kill -0 "$pid" 2>/dev/null || ps -p "$pid" >/dev/null 2>&1 || return 0
  # Same ID, but a different process started since: the ID was reused.
  [[ "$owner" == *" "* && "$(lock_proc_id "$pid")" != "$owner" ]]
}

# lock_take LOCK: take the lock. Fails when a live run holds it, naming its
# process in LOCK_HOLDER.
lock_take() {
  local lock="$1" me got=1
  LOCK_HOLDER=""
  mkdir -p "$(dirname "$lock")" 2>/dev/null
  if ! mkdir "$lock" 2>/dev/null; then
    if ! lock_stale "$lock"; then
      LOCK_HOLDER="$(lock_owner "$lock")"; LOCK_HOLDER="${LOCK_HOLDER%% *}"
      return 1
    fi
    if ! mkdir "$lock.break" 2>/dev/null; then
      # Another taker is breaking it. A break lock a minute old was left by
      # a crash in the middle of it; clear it for the next run.
      [[ -n "$(find "$lock.break" -maxdepth 0 -mmin +1 2>/dev/null)" ]] && rmdir "$lock.break" 2>/dev/null
      return 1
    fi
    if lock_stale "$lock"; then
      rm -f "$lock/owner" "$lock/pid" "$lock"/owner.* 2>/dev/null
      rmdir "$lock" 2>/dev/null
    fi
    mkdir "$lock" 2>/dev/null && got=0
    rmdir "$lock.break" 2>/dev/null
    [[ "$got" == 0 ]] || return 1
  fi
  me="$(lock_proc_id "$$")" || me="$$"
  printf '%s\n' "$me" > "$lock/owner.$$" && mv -f "$lock/owner.$$" "$lock/owner"
}

# lock_release LOCK: give the lock back, only when this process holds it.
lock_release() {
  local lock="$1" owner
  owner="$(lock_owner "$lock")"
  [[ -n "$owner" && "${owner%% *}" == "$$" ]] || return 0
  rm -f "$lock/owner" "$lock/pid"; rmdir "$lock" 2>/dev/null
  return 0
}
