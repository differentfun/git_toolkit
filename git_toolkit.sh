#!/usr/bin/env bash

set -Eeuo pipefail

# --- persistent configuration ------------------------------------------------
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/git_toolkit"
REPO_LIST_FILE="$CONFIG_DIR/repos.list"
mkdir -p "$CONFIG_DIR"
touch "$REPO_LIST_FILE"

CURRENT_REPO=""
ZENITY_SEPARATOR=$'\x1f'

cleanup_tmp() {
  local file
  for file in "$CONFIG_DIR"/.tmp_*; do
    [ -e "$file" ] && rm -f "$file"
  done
}

trap cleanup_tmp EXIT

zenity_installed() {
  if ! command -v zenity >/dev/null 2>&1; then
    printf 'This toolkit requires Zenity to be installed.\n' >&2
    exit 1
  fi
}

show_error() {
  local message=$1
  zenity --error --title="Error" --width=400 --text="$message" || true
}

show_notification() {
  local message=$1
  zenity --info --title="Git Toolkit" --width=400 --text="$message" || true
}

show_text() {
  local title=$1
  local text=$2
  local tmpfile
  tmpfile=$(mktemp "$CONFIG_DIR/.tmp_XXXX")
  printf '%s\n' "$text" >"$tmpfile"
  zenity --text-info --title="$title" --width=900 --height=600 --filename="$tmpfile" || true
  rm -f "$tmpfile"
}

run_git() {
  git -C "$CURRENT_REPO" "$@"
}

ensure_repo_valid() {
  if ! git -C "$1" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    show_error "The selected path is not a valid Git repository."
    return 1
  fi
  return 0
}

list_saved_repos() {
  mapfile -t repos < "$REPO_LIST_FILE"
  printf '%s\n' "${repos[@]}"
}

add_repo_to_list() {
  local repo=$1
  mapfile -t repos < "$REPO_LIST_FILE"
  for existing in "${repos[@]}"; do
    if [ "$existing" = "$repo" ]; then
      return
    fi
  done
  printf '%s\n' "$repo" >>"$REPO_LIST_FILE"
}

remove_repos_from_list() {
  local remove_list=("$@")
  [ ${#remove_list[@]} -eq 0 ] && return
  mapfile -t repos < "$REPO_LIST_FILE"
  : >"$REPO_LIST_FILE"
  local repo rem
  for repo in "${repos[@]}"; do
    local keep=1
    for rem in "${remove_list[@]}"; do
      [ -z "$rem" ] && continue
      if [ "$repo" = "$rem" ]; then
        keep=0
        break
      fi
    done
    if [ $keep -eq 1 ]; then
      printf '%s\n' "$repo" >>"$REPO_LIST_FILE"
    fi
  done
}

manage_repo_list() {
  while true; do
    local choice
    choice=$(zenity --list \
      --title="Saved Repository Manager" \
      --width=600 --height=360 \
      --column="Operation" \
      --column="Description" \
      "Add" "Select a new Git repository" \
      "Remove" "Remove one or more saved repositories" \
      "Clear list" "Delete all saved repositories" \
      "Show list" "Display current list" \
      "Back" "Return to previous screen") || return 0

    case "$choice" in
      "Add")
        local new_repo
        new_repo=$(zenity --file-selection --directory --title="Select Git repository folder") || continue
        if ensure_repo_valid "$new_repo"; then
          add_repo_to_list "$new_repo"
          show_notification "Repository added to list: $new_repo"
        fi
        ;;
      "Remove")
        mapfile -t repos < "$REPO_LIST_FILE"
        if [ ${#repos[@]} -eq 0 ]; then
          show_notification "No saved repositories to remove."
          continue
        fi
        local options=( )
        local repo
        for repo in "${repos[@]}"; do
          options+=(FALSE "$repo")
        done
        local to_delete
        to_delete=$(zenity --list --checklist --title="Choose repositories to remove" \
          --width=680 --height=420 \
          --column="Select" --column="Repository" \
          --separator="$ZENITY_SEPARATOR" \
          "${options[@]}") || continue
        if [ -n "$to_delete" ]; then
          IFS="$ZENITY_SEPARATOR" read -ra remove_arr <<< "$to_delete"
          remove_repos_from_list "${remove_arr[@]}"
          show_notification "Repositories removed from the list."
        fi
        ;;
      "Clear list")
        if zenity --question --title="Confirm" --text="Do you really want to delete all saved repositories?"; then
          : > "$REPO_LIST_FILE"
          show_notification "List cleared."
        fi
        ;;
      "Show list")
        local list
        list=$(list_saved_repos)
        [ -z "$list" ] && list="(No saved repositories)"
        show_text "Saved repositories" "$list"
        ;;
      "Back")
        return 0
        ;;
    esac
  done
}

select_repository() {
  while true; do
    mapfile -t repos < "$REPO_LIST_FILE"
    local options=()
    local repo
    for repo in "${repos[@]}"; do
      [ -z "$repo" ] && continue
      if [ ! -d "$repo" ]; then
        options+=("$repo" "Path not found (will be removed automatically)" "Remove")
      elif git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        local branch
        branch=$(git -C "$repo" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "Detached HEAD")
        options+=("$repo" "Current branch: $branch" "Open")
      else
        options+=("$repo" "Not a valid Git repository (will be removed)" "Remove")
      fi
    done
    options+=("Browse..." "Pick a repository from the filesystem" "Choose")
    options+=("Manage list..." "Add or remove saved repositories" "Manage")
    options+=("Quit" "Close the toolkit" "Exit")

    local selection
    selection=$(zenity --list --title="Select Git repository" \
      --width=780 --height=480 \
      --column="Path/Option" --column="Notes" --column="Action" \
      --hide-column=3 --print-column=1 \
      "${options[@]}") || exit 0

    case "$selection" in
      "Browse...")
        local chosen
        chosen=$(zenity --file-selection --directory --title="Select Git repository folder") || continue
        if ensure_repo_valid "$chosen"; then
          add_repo_to_list "$chosen"
          CURRENT_REPO="$chosen"
          return 0
        fi
        ;;
      "Manage list...")
        manage_repo_list
        ;;
      "Quit")
        exit 0
        ;;
      *)
        if [ ! -d "$selection" ]; then
          show_error "Path $selection does not exist: removing it from the list."
          remove_repos_from_list "$selection"
          continue
        fi
        if ensure_repo_valid "$selection"; then
          add_repo_to_list "$selection"
          CURRENT_REPO="$selection"
          return 0
        else
          remove_repos_from_list "$selection"
        fi
        ;;
    esac
  done
}

require_selection() {
  if [ -z "$CURRENT_REPO" ]; then
    show_error "Select a repository first."
    return 1
  fi
  return 0
}

confirm_action() {
  local prompt=$1
  if zenity --question --title="Confirm" --text="$prompt"; then
    return 0
  fi
  return 1
}

choose_from_log() {
  local title=$1
  local allow_multiple=$2
  local max_entries=${3:-200}
  local log
  log=$(git -C "$CURRENT_REPO" log -n "$max_entries" --pretty=format:'%h%x09%s%x09%cr%x09%an' 2>/dev/null) || {
    show_error "Unable to read the Git log."
    return 1
  }
  [ -z "$log" ] && {
    show_error "No commits available."
    return 1
  }
  local data=()
  while IFS=$'\t' read -r hash subject reltime author; do
    data+=(FALSE "$hash" "$subject" "$reltime" "$author")
  done <<< "$log"
  local opts=(--title="$title" --width=880 --height=520 \
    --column="Select" --column="Commit" --column="Message" --column="When" --column="Author")
  if [ "$allow_multiple" = "true" ]; then
    opts=(--list --checklist --separator="$ZENITY_SEPARATOR" "${opts[@]}")
  else
    opts=(--list --radiolist --separator="$ZENITY_SEPARATOR" "${opts[@]}")
  fi
  local selection
  selection=$(zenity "${opts[@]}" --print-column=2 "${data[@]}") || return 1
  printf '%s\n' "$selection"
  return 0
}

choose_branch() {
  local title=$1
  local include_remote=${2:-false}
  local branches
  if [ "$include_remote" = true ]; then
    branches=$(git -C "$CURRENT_REPO" for-each-ref --format='%(refname:short)\t%(objectname:short)\t%(authordate:relative)' refs/heads refs/remotes)
  else
    branches=$(git -C "$CURRENT_REPO" for-each-ref --format='%(refname:short)\t%(objectname:short)\t%(authordate:relative)' refs/heads)
  fi
  [ -z "$branches" ] && {
    show_error "No branches available."
    return 1
  }
  local data=()
  while IFS=$'\t' read -r name hash rel; do
    data+=(FALSE "$name" "$hash" "$rel")
  done <<< "$branches"
  local selection
  selection=$(zenity --list --radiolist --title="$title" --width=720 --height=480 \
    --column="Select" --column="Branch" --column="Commit" --column="Last update" \
    --print-column=2 "${data[@]}") || return 1
  printf '%s\n' "$selection"
  return 0
}

ensure_clean_or_confirm() {
  if git -C "$CURRENT_REPO" diff --quiet && git -C "$CURRENT_REPO" diff --cached --quiet; then
    return 0
  fi
  confirm_action "There are unsaved changes. Continue anyway?"
}

show_status() {
  local output
  output=$(git -C "$CURRENT_REPO" status --short --branch 2>&1) || {
    show_error "$output"
    return
  }
  [ -z "$output" ] && output="No changes."
  show_text "Repository status" "$output"
}

stage_files() {
  local status
  status=$(git -C "$CURRENT_REPO" status --short 2>/dev/null)
  if [ -z "$status" ]; then
    show_notification "No files to stage."
    return
  fi
  local options=()
  while IFS= read -r line; do
    local code=${line:0:2}
    local file=${line:3}
    options+=(FALSE "$code" "$file")
  done <<< "$status"
  local selection
  selection=$(zenity --list --checklist --title="Add files to the index" --width=900 --height=520 \
    --column="Select" --column="Status" --column="File" \
    --print-column=3 --separator="$ZENITY_SEPARATOR" "${options[@]}") || return
  [ -z "$selection" ] && return
  local IFS="$ZENITY_SEPARATOR"
  local -a files=()
  read -ra files <<< "$selection"
  local file
  for file in "${files[@]}"; do
    [ -z "$file" ] && continue
    git -C "$CURRENT_REPO" add -- "$file"
  done
  show_notification "Files added to the index."
}

unstage_files() {
  local status
  status=$(git -C "$CURRENT_REPO" status --short --cached 2>/dev/null)
  if [ -z "$status" ]; then
    show_notification "No staged files to remove."
    return
  fi
  local options=()
  while IFS= read -r line; do
    local code=${line:0:2}
    local file=${line:3}
    options+=(FALSE "$code" "$file")
  done <<< "$status"
  local selection
  selection=$(zenity --list --checklist --title="Remove files from the index" --width=900 --height=520 \
    --column="Select" --column="Status" --column="File" \
    --print-column=3 --separator="$ZENITY_SEPARATOR" "${options[@]}") || return
  [ -z "$selection" ] && return
  local IFS="$ZENITY_SEPARATOR"
  local -a files=()
  read -ra files <<< "$selection"
  local file
  for file in "${files[@]}"; do
    [ -z "$file" ] && continue
    git -C "$CURRENT_REPO" reset HEAD -- "$file"
  done
  show_notification "Files removed from the index."
}

commit_changes() {
  local staged
  local output
  staged=$(git -C "$CURRENT_REPO" diff --cached --name-only)
  if [ -z "$staged" ]; then
    if ! zenity --question --title="Empty index" --text="No files are staged. Create a commit including all changes (git commit -am)?"; then
      return
    fi
    local msg_form
    msg_form=$(zenity --forms --title="Quick commit" --add-entry="Commit message" --text="git commit -am") || return
    local message=${msg_form%%|*}
    [ -z "$message" ] && { show_error "The commit message is required."; return; }
    if ! output=$(git -C "$CURRENT_REPO" commit -am "$message" 2>&1); then
      show_error "$output"
    else
      show_text "Commit result" "$output"
    fi
    return
  fi
  local form
  form=$(zenity --forms --title="Create commit" --add-entry="Subject (required)" --add-entry="Multiline description (optional)" --separator=$'\n') || return
  local subject=${form%%$'\n'*}
  local body=${form#*$'\n'}
  [ -z "$subject" ] && { show_error "The commit message is required."; return; }
  local tmpfile
  tmpfile=$(mktemp "$CONFIG_DIR/.tmp_commit_XXXX")
  printf '%s\n\n%s\n' "$subject" "$body" >"$tmpfile"
  if ! output=$(GIT_EDITOR="cat" git -C "$CURRENT_REPO" commit -F "$tmpfile" 2>&1); then
    rm -f "$tmpfile"
    show_error "$output"
    return
  fi
  rm -f "$tmpfile"
  show_text "Commit result" "$output"
}

pull_changes() {
  local remotes
  remotes=$(git -C "$CURRENT_REPO" remote)
  [ -z "$remotes" ] && { show_error "No remotes configured."; return; }
  local default_branch
  default_branch=$(git -C "$CURRENT_REPO" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  local remote_list=()
  local remote
  for remote in $remotes; do
    remote_list+=(FALSE "$remote")
  done
  local selected_remote
  selected_remote=$(zenity --list --radiolist --title="Select remote" --width=500 --height=320 \
    --column="Select" --column="Remote" \
    --print-column=2 "${remote_list[@]}") || return
  [ -z "$selected_remote" ] && return
  local branch
  branch=$(zenity --entry --title="Branch to update" --text="Specify the branch to update" --entry-text="$default_branch") || return
  [ -z "$branch" ] && { show_error "Branch is required."; return; }
  if ! ensure_clean_or_confirm; then
    return
  fi
  local output
  if ! output=$(git -C "$CURRENT_REPO" pull "$selected_remote" "$branch" 2>&1); then
    show_error "$output"
  else
    show_text "git pull" "$output"
  fi
}

fetch_changes() {
  local choice
  choice=$(zenity --list --title="git fetch" --width=520 --height=260 \
    --column="Option" --column="Description" \
    "Fetch specific remote" "Download updates from a remote" \
    "Fetch --all" "Download updates from all remotes") || return
  local output
  case "$choice" in
    "Fetch specific remote")
      local remotes
      remotes=$(git -C "$CURRENT_REPO" remote)
      [ -z "$remotes" ] && { show_error "No remotes configured."; return; }
      local remote_list=()
      local remote
      for remote in $remotes; do
        remote_list+=(FALSE "$remote")
      done
      local selected_remote
      selected_remote=$(zenity --list --radiolist --title="Select remote" --width=500 --height=320 \
        --column="Select" --column="Remote" \
        --print-column=2 "${remote_list[@]}") || return
      [ -z "$selected_remote" ] && return
      output=$(git -C "$CURRENT_REPO" fetch "$selected_remote" 2>&1) || {
        show_error "$output"
        return
      }
      ;;
    "Fetch --all")
      output=$(git -C "$CURRENT_REPO" fetch --all 2>&1) || {
        show_error "$output"
        return
      }
      ;;
  esac
  show_text "git fetch" "$output"
}

push_changes() {
  local remotes
  remotes=$(git -C "$CURRENT_REPO" remote)
  [ -z "$remotes" ] && { show_error "No remotes configured."; return; }
  local remote_list=()
  local remote
  for remote in $remotes; do
    remote_list+=(FALSE "$remote")
  done
  local selected_remote
  selected_remote=$(zenity --list --radiolist --title="Select remote" --width=500 --height=320 \
    --column="Select" --column="Remote" \
    --print-column=2 "${remote_list[@]}") || return
  [ -z "$selected_remote" ] && return
  local default_branch
  default_branch=$(git -C "$CURRENT_REPO" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  local branch
  branch=$(zenity --entry --title="Branch to push" --text="Specify the branch to push" --entry-text="$default_branch") || return
  [ -z "$branch" ] && { show_error "Branch is required."; return; }
  local options
  options=$(zenity --forms --title="Push options" --text="Leave empty to use defaults" \
    --add-entry="Additional tag options (e.g. --tags)" \
    --add-entry="Extra options (e.g. --force-with-lease)" --separator=$'\n') || return
  local tags_opt=${options%%$'\n'*}
  local extra_opt=${options#*$'\n'}
  local cmd=(push "$selected_remote" "$branch")
  if [ -n "$tags_opt" ]; then
    local -a tag_args=()
    read -r -a tag_args <<< "$tags_opt"
    cmd+=("${tag_args[@]}")
  fi
  if [ -n "$extra_opt" ]; then
    local -a extra_array=()
    read -r -a extra_array <<< "$extra_opt"
    cmd+=("${extra_array[@]}")
  fi
  local output
  if ! output=$(git -C "$CURRENT_REPO" "${cmd[@]}" 2>&1); then
    show_error "$output"
  else
    show_text "git push" "$output"
  fi
}

checkout_ref() {
  local choice
  choice=$(zenity --list --title="Checkout" --width=640 --height=360 \
    --column="Option" --column="Description" \
    "Existing branch" "Switch to a local or remote branch" \
    "Commit" "Checkout a specific commit (detached HEAD)" \
    "Quick creation" "Create and switch to a new branch" ) || return
  case "$choice" in
    "Existing branch")
      local branch
      branch=$(choose_branch "Choose branch" true) || return
      if ! ensure_clean_or_confirm; then
        return
      fi
      local output
      if ! output=$(git -C "$CURRENT_REPO" checkout "$branch" 2>&1); then
        show_error "$output"
      else
        show_text "git checkout" "$output"
      fi
      ;;
    "Commit")
      local commit
      commit=$(choose_from_log "Select commit" false 400) || return
      if ! ensure_clean_or_confirm; then
        return
      fi
      local output
      if ! output=$(git -C "$CURRENT_REPO" checkout "$commit" 2>&1); then
        show_error "$output"
      else
        show_text "Checkout commit" "$output"
      fi
      ;;
    "Quick creation")
      local form
      form=$(zenity --forms --title="New branch" --add-entry="Branch name" --add-entry="Starting point (commit/branch)" --separator=$'\n') || return
      local name=${form%%$'\n'*}
      local base=${form#*$'\n'}
      [ -z "$name" ] && { show_error "The branch name is required."; return; }
      local cmd=(checkout -b "$name")
      [ -n "$base" ] && cmd=(checkout -b "$name" "$base")
      if ! ensure_clean_or_confirm; then
        return
      fi
      local output
      if ! output=$(git -C "$CURRENT_REPO" "${cmd[@]}" 2>&1); then
        show_error "$output"
      else
        show_text "New branch" "$output"
      fi
      ;;
  esac
}

create_branch() {
  local form
  form=$(zenity --forms --title="Create branch" --add-entry="Branch name" --add-entry="Base (branch/commit)" --text="Leave Base blank to use HEAD" --separator=$'\n') || return
  local name=${form%%$'\n'*}
  local base=${form#*$'\n'}
  [ -z "$name" ] && { show_error "The branch name is required."; return; }
  local output
  if [ -n "$base" ]; then
    output=$(git -C "$CURRENT_REPO" branch "$name" "$base" 2>&1)
  else
    output=$(git -C "$CURRENT_REPO" branch "$name" 2>&1)
  fi
  if [ $? -ne 0 ]; then
    show_error "$output"
  else
    show_text "Branch created" "$output"
  fi
}

merge_branch() {
  local branch
  branch=$(choose_branch "Select branch to merge" false) || return
  if ! ensure_clean_or_confirm; then
    return
  fi
  local options
  options=$(zenity --forms --title="Merge options" --add-entry="Strategy (e.g. ours, theirs)" --add-entry="Extra options (e.g. --no-ff)" --separator=$'\n') || return
  local strategy=${options%%$'\n'*}
  local extra=${options#*$'\n'}
  local cmd=(merge "$branch")
  [ -n "$strategy" ] && cmd=(merge -s "$strategy" "$branch")
  if [ -n "$extra" ]; then
    IFS=' ' read -r -a extra_array <<< "$extra"
    cmd+=("${extra_array[@]}")
  fi
  local output
  if ! output=$(git -C "$CURRENT_REPO" "${cmd[@]}" 2>&1); then
    show_error "$output"
  else
    show_text "git merge" "$output"
  fi
}

rebase_branch() {
  if ! ensure_clean_or_confirm; then
    return
  fi
  local branch
  branch=$(choose_branch "Choose base branch" true) || return
  local options
  options=$(zenity --forms --title="Rebase options" --add-entry="Extra options (e.g. --interactive)" ) || return
  local extra=${options%%|*}
  local cmd=(rebase "$branch")
  if [ -n "$extra" ]; then
    IFS=' ' read -r -a extra_array <<< "$extra"
    cmd+=("${extra_array[@]}")
  fi
  local output
  if ! output=$(git -C "$CURRENT_REPO" "${cmd[@]}" 2>&1); then
    show_error "$output"
  else
    show_text "git rebase" "$output"
  fi
}

show_log() {
  local choice
  choice=$(zenity --list --title="View log" --width=640 --height=360 \
    --column="Mode" --column="Description" \
    "Compact graph" "git log --graph --decorate --oneline" \
    "Full details" "git log -n 100" \
    "Filter by author" "Show commits by a specific author" \
    "Search by keyword" "Filter commits by search term" ) || return
  local output
  case "$choice" in
    "Compact graph")
      output=$(git -C "$CURRENT_REPO" log --graph --decorate --oneline -n 200 2>&1)
      ;;
    "Full details")
      output=$(git -C "$CURRENT_REPO" log -n 100 2>&1)
      ;;
    "Filter by author")
      local author
      author=$(zenity --entry --title="Author" --text="Enter name or email" ) || return
      output=$(git -C "$CURRENT_REPO" log --author="$author" --graph --oneline -n 200 2>&1)
      ;;
    "Search by keyword")
      local term
      term=$(zenity --entry --title="Filtro" --text="Enter search string" ) || return
      output=$(git -C "$CURRENT_REPO" log --grep="$term" --graph --decorate --oneline -n 200 2>&1)
      ;;
  esac
  if [ $? -ne 0 ]; then
    show_error "$output"
  else
    [ -z "$output" ] && output="No results."
    show_text "Git log" "$output"
  fi
}

diff_view() {
  local choice
  choice=$(zenity --list --title="Diff" --width=660 --height=360 \
    --column="Option" --column="Description" \
    "Diff working tree" "Compare unstaged changes with HEAD" \
    "Diff staged" "Compare index with HEAD" \
    "Diff between commits" "Compare two commits" \
    "Specific file diff" "Choose a file to compare" ) || return
  local output
  case "$choice" in
    "Diff working tree")
      output=$(git -C "$CURRENT_REPO" diff 2>&1)
      ;;
    "Diff staged")
      output=$(git -C "$CURRENT_REPO" diff --cached 2>&1)
      ;;
    "Diff between commits")
      local commits
      commits=$(choose_from_log "Select commits (base first, then target)" true 200) || return
      IFS='|' read -r first second <<< "${commits//\n/|}"
      if [ -z "$first" ] || [ -z "$second" ]; then
        show_error "Select at least two commits."
        return
      fi
      output=$(git -C "$CURRENT_REPO" diff "$first" "$second" 2>&1)
      ;;
    "Specific file diff")
      local file
      file=$(zenity --entry --title="File" --text="Relative file path" ) || return
      output=$(git -C "$CURRENT_REPO" diff -- "$file" 2>&1)
      ;;
  esac
  if [ $? -ne 0 ]; then
    show_error "$output"
  else
    [ -z "$output" ] && output="No differences."
    show_text "Diff" "$output"
  fi
}

create_tag() {
  local form
  form=$(zenity --forms --title="Create tag" --add-entry="Tag name" --add-entry="Reference commit (optional)" --add-entry="Annotated message" --separator=$'\n') || return
  local name=$(sed -n '1p' <<<"$form")
  local commit=$(sed -n '2p' <<<"$form")
  local message=$(sed -n '3p' <<<"$form")
  [ -z "$name" ] && { show_error "The tag name is required."; return; }
  local cmd=(tag -a "$name")
  [ -n "$commit" ] && cmd+=("$commit")
  local tmpfile
  tmpfile=$(mktemp "$CONFIG_DIR/.tmp_tag_XXXX")
  printf '%s\n' "$message" >"$tmpfile"
  local output
  if ! output=$(GIT_EDITOR="cat" git -C "$CURRENT_REPO" "${cmd[@]}" -F "$tmpfile" 2>&1); then
    rm -f "$tmpfile"
    show_error "$output"
    return
  fi
  rm -f "$tmpfile"
  show_text "Tag created" "$output"
}

delete_tag() {
  local tags
  tags=$(git -C "$CURRENT_REPO" tag)
  [ -z "$tags" ] && { show_notification "No tags to delete."; return; }
  local options=()
  local tag
  while IFS= read -r tag; do
    options+=(FALSE "$tag")
  done <<< "$tags"
  local selection
  selection=$(zenity --list --checklist --title="Delete tag" --width=520 --height=420 \
    --column="Select" --column="Tag" --separator="$ZENITY_SEPARATOR" "${options[@]}") || return
  [ -z "$selection" ] && return
  if ! confirm_action "Confirm deletion of selected tags?"; then
    return
  fi
  local IFS="$ZENITY_SEPARATOR"
  local -a tags_to_delete=()
  read -ra tags_to_delete <<< "$selection"
  local tg
  for tg in "${tags_to_delete[@]}"; do
    [ -z "$tg" ] && continue
    git -C "$CURRENT_REPO" tag -d "$tg" >/dev/null 2>&1 || true
  done
  show_notification "Tags deleted."
}

stash_save() {
  local form
  form=$(zenity --forms --title="Stash" --add-entry="Description message" --add-combo="Options" --combo-values="\n--include-untracked\n--all" --separator=$'\n') || return
  local message=$(sed -n '1p' <<<"$form")
  local option=$(sed -n '2p' <<<"$form")
  local cmd=(stash push)
  [ -n "$option" ] && cmd+=("$option")
  [ -n "$message" ] && cmd+=("-m" "$message")
  local output
  if ! output=$(git -C "$CURRENT_REPO" "${cmd[@]}" 2>&1); then
    show_error "$output"
  else
    show_text "git stash push" "$output"
  fi
}

stash_apply() {
  local list
  list=$(git -C "$CURRENT_REPO" stash list)
  [ -z "$list" ] && { show_notification "No stashes available."; return; }
  local options=()
  while IFS= read -r line; do
    local name=${line%%:*}
    local desc=${line#*: }
    options+=(FALSE "$name" "$desc")
  done <<< "$list"
  local selection
  selection=$(zenity --list --radiolist --title="Apply stash" --width=700 --height=420 \
    --column="Select" --column="Stash" --column="Description" --print-column=2 "${options[@]}") || return
  local action
  action=$(zenity --list --title="Action" --width=500 --height=280 \
    --column="Operation" --column="Description" \
    "apply" "Apply stash" \
    "pop" "Apply stash and drop it" \
    "drop" "Drop stash" ) || return
  local output
  if ! output=$(git -C "$CURRENT_REPO" stash "$action" "$selection" 2>&1); then
    show_error "$output"
  else
    show_text "git stash $action" "$output"
  fi
}

stash_list() {
  local output
  output=$(git -C "$CURRENT_REPO" stash list 2>&1) || {
    show_error "$output"
    return
  }
  [ -z "$output" ] && output="No stashes present."
  show_text "Available stashes" "$output"
}

reset_branch() {
  local commit
  commit=$(choose_from_log "Select commit for reset" false 200) || return
  local mode
  mode=$(zenity --list --title="Reset mode" --width=520 --height=280 \
    --column="Type" --column="Description" \
    "soft" "Keep index and working tree" \
    "mixed" "Keep working tree, reset index" \
    "hard" "Full reset (loses changes)" ) || return
  if [ "$mode" = "hard" ] && ! confirm_action "Hard reset will discard unsaved changes. Continue?"; then
    return
  fi
  local output
  if ! output=$(git -C "$CURRENT_REPO" reset --"$mode" "$commit" 2>&1); then
    show_error "$output"
  else
    show_text "git reset --$mode" "$output"
  fi
}

revert_commit() {
  local commits
  commits=$(choose_from_log "Select commits to revert" true 200) || return
  local options
  options=$(zenity --forms --title="Revert options" --add-combo="Strategy" --combo-values="\n--no-commit" --add-entry="Extra parameters" --separator=$'\n') || return
  local strategy=$(sed -n '1p' <<<"$options")
  local extra=$(sed -n '2p' <<<"$options")
  local cmd=(revert)
  [ -n "$strategy" ] && cmd+=("$strategy")
  if [ -n "$extra" ]; then
    IFS=' ' read -r -a extra_array <<< "$extra"
    cmd+=("${extra_array[@]}")
  fi
  local commit
  local IFS="$ZENITY_SEPARATOR"
  local -a commits_list=()
  read -ra commits_list <<< "$commits"
  local commit
  for commit in "${commits_list[@]}"; do
    [ -z "$commit" ] && continue
    cmd+=("$commit")
  done
  local output
  if ! output=$(git -C "$CURRENT_REPO" "${cmd[@]}" 2>&1); then
    show_error "$output"
  else
    show_text "git revert" "$output"
  fi
}

cherry_pick() {
  local commits
  commits=$(choose_from_log "Select commits for cherry-pick" true 200) || return
  local options
  options=$(zenity --forms --title="Cherry-pick options" --add-entry="Extra parameters (e.g. --no-commit, -x)" ) || return
  local extra=${options%%|*}
  local cmd=(cherry-pick)
  if [ -n "$extra" ]; then
    IFS=' ' read -r -a extra_array <<< "$extra"
    cmd+=("${extra_array[@]}")
  fi
  local IFS="$ZENITY_SEPARATOR"
  local -a commits_list=()
  read -ra commits_list <<< "$commits"
  local commit
  for commit in "${commits_list[@]}"; do
    [ -z "$commit" ] && continue
    cmd+=("$commit")
  done
  local output
  if ! output=$(git -C "$CURRENT_REPO" "${cmd[@]}" 2>&1); then
    show_error "$output"
  else
    show_text "git cherry-pick" "$output"
  fi
}

rollback_files() {
  local commit
  commit=$(choose_from_log "Select reference commit" false 200) || return
  local files
  files=$(git -C "$CURRENT_REPO" ls-tree -r --name-only "$commit" 2>/dev/null)
  if [ -z "$files" ]; then
    show_error "Unable to retrieve files from the selected commit."
    return
  fi
  local options=()
  while IFS= read -r file; do
    options+=(FALSE "$file")
  done <<< "$files"
  local selection
  selection=$(zenity --list --checklist --title="Restore files" --width=780 --height=520 \
    --column="Select" --column="File" --print-column=2 --separator="$ZENITY_SEPARATOR" "${options[@]}") || return
  [ -z "$selection" ] && return
  if ! confirm_action "Selected files will be overwritten with content from commit $commit. Continue?"; then
    return
  fi
  local IFS="$ZENITY_SEPARATOR"
  local -a files_to_restore=()
  read -ra files_to_restore <<< "$selection"
  local file
  for file in "${files_to_restore[@]}"; do
    [ -z "$file" ] && continue
    git -C "$CURRENT_REPO" checkout "$commit" -- "$file"
  done
  show_notification "Files restored from commit $commit."
}

manage_submodules() {
  local choice
  choice=$(zenity --list --title="Submodule" --width=520 --height=320 \
    --column="Operation" --column="Description" \
    "init" "Initialize submodules" \
    "update" "Update submodules" \
    "status" "Show submodule status" \
    "sync" "Synchronize submodule URLs" ) || return
  local output
  if ! output=$(git -C "$CURRENT_REPO" submodule "$choice" --recursive 2>&1); then
    show_error "$output"
  else
    show_text "git submodule $choice" "$output"
  fi
}

manage_bisect() {
  local choice
  choice=$(zenity --list --title="Git bisect" --width=620 --height=360 \
    --column="Operation" --column="Description" \
    "start" "Start a bisect session" \
    "good" "Mark good commit" \
    "bad" "Mark bad commit" \
    "skip" "Skip commit" \
    "reset" "End bisect" \
    "log" "Show bisect status" ) || return
  local output
  case "$choice" in
    "start")
      local form
      form=$(zenity --forms --title="git bisect start" --add-entry="Bad commit" --add-entry="Good commit" --separator=$'\n') || return
      local bad=${form%%$'\n'*}
      local good=${form#*$'\n'}
      [ -z "$bad" ] && { show_error "The bad commit is required."; return; }
      local cmd=(bisect start "$bad")
      [ -n "$good" ] && cmd+=("$good")
      output=$(git -C "$CURRENT_REPO" "${cmd[@]}" 2>&1)
      ;;
    "good")
      local commit
      commit=$(zenity --entry --title="git bisect good" --text="Good commit (blank = HEAD)" ) || return
      output=$(git -C "$CURRENT_REPO" bisect good ${commit:+"$commit"} 2>&1)
      ;;
    "bad")
      local commit
      commit=$(zenity --entry --title="git bisect bad" --text="Bad commit (blank = HEAD)" ) || return
      output=$(git -C "$CURRENT_REPO" bisect bad ${commit:+"$commit"} 2>&1)
      ;;
    "skip")
      local commit
      commit=$(zenity --entry --title="git bisect skip" --text="Commit to skip (blank = HEAD)" ) || return
      output=$(git -C "$CURRENT_REPO" bisect skip ${commit:+"$commit"} 2>&1)
      ;;
    "reset")
      output=$(git -C "$CURRENT_REPO" bisect reset 2>&1)
      ;;
    "log")
      output=$(git -C "$CURRENT_REPO" bisect log 2>&1)
      ;;
  esac
  if [ $? -ne 0 ]; then
    show_error "$output"
  else
    [ -z "$output" ] && output="(no output)"
    show_text "git bisect $choice" "$output"
  fi
}

show_config() {
  local choice
  choice=$(zenity --list --title="Git configuration" --width=600 --height=320 \
    --column="Option" --column="Description" \
    "Show local configuration" "git config --list" \
    "Set key" "Define a configuration key" \
    "Remove key" "Delete a configuration key" ) || return
  case "$choice" in
    "Show local configuration")
      local output
      output=$(git -C "$CURRENT_REPO" config --list 2>&1) || {
        show_error "$output"
        return
      }
      show_text "Repository configuration" "$output"
      ;;
    "Set key")
      local form
      form=$(zenity --forms --title="git config" --add-entry="Key (e.g. user.email)" --add-entry="Value" --separator=$'\n') || return
      local key=${form%%$'\n'*}
      local value=${form#*$'\n'}
      [ -z "$key" ] && { show_error "The key is required."; return; }
      if ! git -C "$CURRENT_REPO" config "$key" "$value" 2>/dev/null; then
        show_error "Unable to set key."
      else
        show_notification "Configuration updated."
      fi
      ;;
    "Remove key")
      local key
      key=$(zenity --entry --title="git config --unset" --text="Key to remove" ) || return
      if ! git -C "$CURRENT_REPO" config --unset "$key" 2>/dev/null; then
        show_error "Unable to remove key (maybe it does not exist)."
      else
        show_notification "Key removed."
      fi
      ;;
  esac
}

clean_worktree() {
  local choice
  choice=$(zenity --list --title="git clean" --width=620 --height=320 \
    --column="Option" --column="Description" \
    "--dry-run" "Show what would be removed" \
    "-fd" "Remove untracked files and directories" ) || return
  local output
  if [ "$choice" = "--dry-run" ]; then
    output=$(git -C "$CURRENT_REPO" clean -fd --dry-run 2>&1) || {
      show_error "$output"
      return
    }
    show_text "git clean --dry-run" "$output"
    return
  fi
  if confirm_action "All untracked files will be deleted. Continue?"; then
    output=$(git -C "$CURRENT_REPO" clean -fd 2>&1)
    if [ $? -ne 0 ]; then
      show_error "$output"
    else
      show_text "git clean" "$output"
    fi
  fi
}

manage_remotes() {
  local choice
  choice=$(zenity --list --title="Remotes" --width=600 --height=320 \
    --column="Operation" --column="Description" \
    "List remotes" "Show configured remotes" \
    "Add" "Add a new remote" \
    "Remove" "Remove a remote" \
    "Edit URL" "Update a remote URL" ) || return
  local output
  case "$choice" in
    "List remotes")
      output=$(git -C "$CURRENT_REPO" remote -v 2>&1) || {
        show_error "$output"
        return
      }
      show_text "git remote -v" "$output"
      ;;
    "Add")
      local form
      form=$(zenity --forms --title="Add remote" --add-entry="Name" --add-entry="URL" --separator=$'\n') || return
      local name=${form%%$'\n'*}
      local url=${form#*$'\n'}
      if [ -z "$name" ] || [ -z "$url" ]; then
        show_error "Name and URL are required."
        return
      fi
      if ! output=$(git -C "$CURRENT_REPO" remote add "$name" "$url" 2>&1); then
        show_error "$output"
      else
        show_notification "Remote added."
      fi
      ;;
    "Remove")
      local remotes
      remotes=$(git -C "$CURRENT_REPO" remote)
      [ -z "$remotes" ] && { show_notification "No remotes to remove."; return; }
      local options=()
      local remote
      for remote in $remotes; do
        options+=(FALSE "$remote")
      done
      local selection
      selection=$(zenity --list --checklist --title="Remove remotes" --width=500 --height=380 \
        --column="Select" --column="Remote" --separator="$ZENITY_SEPARATOR" "${options[@]}") || return
      [ -z "$selection" ] && return
      local IFS="$ZENITY_SEPARATOR"
      local -a remotes_to_remove=()
      read -ra remotes_to_remove <<< "$selection"
      local remote_name
      for remote_name in "${remotes_to_remove[@]}"; do
        [ -z "$remote_name" ] && continue
        git -C "$CURRENT_REPO" remote remove "$remote_name"
      done
      show_notification "Remotes removed."
      ;;
    "Edit URL")
      local remotes
      remotes=$(git -C "$CURRENT_REPO" remote)
      [ -z "$remotes" ] && { show_error "No remotes configured."; return; }
      local options=()
      local remote
      for remote in $remotes; do
        options+=(FALSE "$remote")
      done
      local selection
      selection=$(zenity --list --radiolist --title="Choose remote" --width=500 --height=320 \
        --column="Select" --column="Remote" --print-column=2 "${options[@]}") || return
      local url
      url=$(zenity --entry --title="New URL" --text="Enter the new URL for $selection" ) || return
      if ! git -C "$CURRENT_REPO" remote set-url "$selection" "$url" 2>/dev/null; then
        show_error "Unable to update the URL."
      else
        show_notification "URL updated."
      fi
      ;;
  esac
}

manage_notes() {
  local choice
  choice=$(zenity --list --title="Git notes" --width=600 --height=320 \
    --column="Operation" --column="Description" \
    "Show notes" "View saved notes" \
    "Add note" "Add or edit a commit note" \
    "Remove note" "Delete a commit note" ) || return
  local output
  case "$choice" in
    "Show notes")
      output=$(git -C "$CURRENT_REPO" notes list 2>&1)
      if [ $? -ne 0 ]; then
        show_error "$output"
      else
        [ -z "$output" ] && output="No notes available."
        show_text "git notes list" "$output"
      fi
      ;;
    "Add note")
      local commit
      commit=$(choose_from_log "Select commit" false 200) || return
      local content
      content=$(zenity --entry --title="Notes" --text="Note text" ) || return
      if ! output=$(git -C "$CURRENT_REPO" notes add -m "$content" "$commit" 2>&1); then
        show_error "$output"
      else
        show_notification "Note added to commit $commit."
      fi
      ;;
    "Remove note")
      local commit
      commit=$(choose_from_log "Select commit" false 200) || return
      if ! git -C "$CURRENT_REPO" notes remove "$commit" 2>/dev/null; then
        show_error "Unable to remove note (maybe it does not exist)."
      else
        show_notification "Note removed."
      fi
      ;;
  esac
}

open_terminal() {
  if command -v x-terminal-emulator >/dev/null 2>&1; then
    x-terminal-emulator -e bash -lc "cd '$CURRENT_REPO' && exec bash" &
    return
  fi
  if command -v gnome-terminal >/dev/null 2>&1; then
    gnome-terminal -- bash -lc "cd '$CURRENT_REPO' && exec bash" &
    return
  fi
  show_error "No graphical terminal found. Open one manually in $CURRENT_REPO."
}

main_menu() {
  while true; do
    local branch
    branch=$(git -C "$CURRENT_REPO" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "Detached HEAD")
    local header="Repository: $CURRENT_REPO\nCurrent branch: $branch"
    local choice
    choice=$(zenity --list --title="Git Toolkit" --text="$header" --width=860 --height=620 \
      --column="Operation" --column="Description" \
      "Status" "Show repository status" \
      "Stage" "Add files to staging" \
      "Unstage" "Remove files from staging" \
      "Commit" "Create a new commit" \
      "Pull" "Integrate updates from the remote" \
      "Fetch" "Download updates without merging" \
      "Push" "Publish commits to the remote" \
      "Checkout" "Switch to branch or commit" \
      "Create branch" "Create a new branch" \
      "Merge" "Merge another branch into the current one" \
      "Rebase" "Apply commits on top of another branch" \
      "Log" "View history" \
      "Diff" "Analyze differences" \
      "Create tag" "Define an annotated tag" \
      "Delete tag" "Remove existing tags" \
      "Save stash" "Stash current changes" \
      "Manage stash" "Apply or drop stashes" \
      "Stash list" "Show available stashes" \
      "Reset" "Reset branch to a commit" \
      "Revert" "Undo commit(s) by creating a new one" \
      "Cherry-pick" "Apply selected commits" \
      "Rollback" "Restore files from a commit" \
      "Submodules" "Manage submodules" \
      "Bisect" "Diagnose regressions" \
      "Config" "Read or set git configuration" \
      "Clean" "Remove untracked files" \
      "Remotes" "Manage remotes" \
      "Notes" "Manage git notes" \
      "Terminal" "Open a terminal in the repository" \
      "Change repository" "Choose another repository" \
      "Quit" "Close the toolkit" ) || exit 0

    case "$choice" in
      "Status") show_status ;;
      "Stage") stage_files ;;
      "Unstage") unstage_files ;;
      "Commit") commit_changes ;;
      "Pull") pull_changes ;;
      "Fetch") fetch_changes ;;
      "Push") push_changes ;;
      "Checkout") checkout_ref ;;
      "Create branch") create_branch ;;
      "Merge") merge_branch ;;
      "Rebase") rebase_branch ;;
      "Log") show_log ;;
      "Diff") diff_view ;;
      "Create tag") create_tag ;;
      "Delete tag") delete_tag ;;
      "Save stash") stash_save ;;
      "Manage stash") stash_apply ;;
      "Stash list") stash_list ;;
      "Reset") reset_branch ;;
      "Revert") revert_commit ;;
      "Cherry-pick") cherry_pick ;;
      "Rollback") rollback_files ;;
      "Submodules") manage_submodules ;;
      "Bisect") manage_bisect ;;
      "Config") show_config ;;
      "Clean") clean_worktree ;;
      "Remotes") manage_remotes ;;
      "Notes") manage_notes ;;
      "Terminal") open_terminal ;;
      "Change repository") select_repository ;;
      "Quit") exit 0 ;;
    esac
  done
}

zenity_installed
select_repository
main_menu
