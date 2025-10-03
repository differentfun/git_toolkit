# Git Toolkit (Zenity)

A graphical companion script for Git users who prefer quick point-and-click workflows on Linux desktops. The toolkit is implemented in Bash and relies on Zenity dialogs to guide almost every Git task, reducing the need to memorise command-line flags.

## Features
- **Repository picker & saver** – remember frequently used Git workspaces and switch with a couple of clicks.
- **Daily helpers** – view status, stage/unstage files, craft commits, and manage pull/fetch/push operations with confirmations.
- **History & diff tools** – browse logs with filters, inspect diffs between working tree, index, or any pair of commits.
- **Branching & tagging** – create or checkout branches, reset, revert, cherry-pick, and manage annotated tags.
- **Advanced flows** – manage stashes, submodules, git-notes, bisect sessions, configuration keys, remotes, and workspace cleaning.
- **Safety prompts** – warns about dirty trees before destructive actions and explains each option directly in the GUI lists.

## Usage
1. Ensure `zenity` and `git` are installed and accessible in `PATH`.
2. Make the script executable: `chmod +x git_toolkit.sh`.
3. Run the toolkit from a graphical session: `./git_toolkit.sh`.
4. Select or add repositories, then drive Git operations through the menu-driven dialogs.

## Open Source
This project is open source. Feel free to fork it, adapt it to your workflow, and send improvements or bug reports.
