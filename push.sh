
#!/usr/bin/env bash
set -Eeuo pipefail

# When installed as push.sh, update the current project.
if [[ "$(basename "$0")" == "push.sh" ]]; then
    cd "$(dirname "$(readlink -f "$0")")"

    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo "Error: this folder is not a Git repository."
        exit 1
    fi

    git add -A

    if ! git diff --cached --quiet; then
        git commit -m "Update Python code"
    else
        echo "No changes to commit."
    fi

    git push
    exit 0
fi

# Check required tools.
for cmd in git gh; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Missing $cmd. Install with:"
        echo "sudo pacman -S git github-cli"
        exit 1
    fi
done

# Login to GitHub if needed.
if ! gh auth status >/dev/null 2>&1; then
    gh auth login
fi

gh auth status

echo
read -r -p "Project folder path: " project
project="${project/#\~/$HOME}"
project="$(realpath -e "$project")"

if [[ ! -d "$project" ]]; then
    echo "Error: folder not found."
    exit 1
fi

cd "$project"

# Ask for repository name.
default_name="$(basename "$project")"
read -r -p "GitHub repository name [$default_name]: " repo
repo="${repo:-$default_name}"

read -r -p "Visibility: public or private [private]: " visibility
visibility="${visibility:-private}"

case "$visibility" in
    public|private) ;;
    *)
        echo "Choose public or private."
        exit 1
        ;;
esac

# Install this script into the project.
cp "$(readlink -f "$HOME/github-upload.sh")" "$project/push.sh"
chmod +x "$project/push.sh"

# Initialize Git if necessary.
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git init
fi

# Configure commit identity if missing.
if [[ -z "$(git config user.name || true)" ]]; then
    read -r -p "Your Git name: " git_name
    git config user.name "$git_name"
fi

if [[ -z "$(git config user.email || true)" ]]; then
    read -r -p "Your Git email: " git_email
    git config user.email "$git_email"
fi

# Stage files and create a commit when needed.
git add -A

if ! git diff --cached --quiet; then
    git commit -m "First upload"
fi

if ! git rev-parse --verify HEAD >/dev/null 2>&1; then
    echo "Error: no commit exists. Check whether the folder contains files."
    exit 1
fi

# Connect to GitHub or reuse the existing remote.
if git remote get-url origin >/dev/null 2>&1; then
    echo "Using existing origin:"
    git remote get-url origin
else
    login="$(gh api user --jq .login)"

    if gh repo view "$login/$repo" >/dev/null 2>&1; then
        repo_url="$(gh repo view "$login/$repo" --json url --jq .url)"
        git remote add origin "${repo_url}.git"
    else
        gh repo create "$repo" "--$visibility" \
            --source=. --remote=origin
    fi
fi

# Push the current branch.
branch="$(git branch --show-current)"
git push -u origin "$branch"

echo
echo "Upload complete!"
echo "Project: $project"
echo "Update later by running:"
echo "cd \"$project\" && ./push.sh"
