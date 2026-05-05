| Command | Explanation |
|:--------|:------------|
| jj git init | Initialize jj |
| jj st | Check the status |
| jj log | Show logs |
| jj commit -m "message" | Create a local commit |
| jj git push --change @- | Create a generated bookmark and push it|
| jj git fetch | Pull from GitHub |
| jj describe -m "message" | Set the name for the current change |
| jj edit \<change-id\> | Set the current change to \<change-id\> |
| jj abandon \<change-id\> | Delete \<change-id\> |
| jj file untrack \<filename\> | Untrack a file |
| jj git push --remote origin --bookmark \<bookmark\> | Push to GitHub |
| jj bookmark create \<bookmark\> | Create a bookmark. \<bookmark\> cannot contain spaces |
| jj log -r 'main@origin..@ & files("\<filename\>")' | Find all changes that contain \<filename\> |
| jj restore --changes-in \<change_id\> \<filename\> | Remove \<filename\> from \<change_id\> |
| jj bookmark set main -r @ | Move local main bookmark to point to the current change (@) |
| jj git push --remote origin -b main | push local main to GitHub |
| jj new [-m "Merge spmq and nvmp"] | Create a new change |
| jj new 'spmq' 'nvmp' -m "Merge spmq and nvmp" | Create a new change by merging the two |
| jj config set --user merge.tool meld | Excellent visual merge tool |
| jj config set --user ui.merge-editor vscode | Recommended if using VS code |
| jj resolve path/to/file | Open the editor to resolve conflicts |
| jj resolve --list | List all the conflicts |
| jj diff [--name-only] | Show the differences |
| jj diff --from <named-change> --to @ -- path/to/file | Compare diffs of a file in two changes |
| git tag -a rel-20230323 -m "Release 2023-03-23" | Create a tag |
| git push origin rel-20230323 | Push the tag |
--------

---
## Push to GitHub
```text
jj describe -m "feat: description"
jj bookmark set main -r @
jj git push --remote=origin -b main
```

--- 
## Tagging
```text
git tag -a rel-20230323 -m "Release 2023-03-23"
git push origin rel-20230323
```

---
## Untrack Files
If some files are already in a repo but you want to remove them from the repo (untrack):
```text
# Stop tracking cached files (keeps them on disk)
jj file untrack .gocache

# Verify they're no longer tracked
jj status

# Record the change
jj describe -m "Stop tracking .gocache build cache files"
jj new
```