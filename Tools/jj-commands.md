| Command | Explanation |
|:--------|:------------|
|jj st | Check the status |
|jj log | Show logs |
|jj commit -m "message" | Create a local commit |
|jj git push --change @- | Create a generated bookmark and push it|
|jj git fetch | Pull from GitHub |
|jj describe -m "message" | Set the name for the current change |
|jj edit <change-id> | Set the current change to <change-id> |
|jj abandon <change-id> | Delete <change-id> |
|jj file untrack <filename> | Untrack a file |
|jj git push --remote origin --bookmark <bookmark> | Push to GitHub |
|jj bookmark create <bookmark> | Create a bookmark. <bookmark> cannot contain spaces |
|jj log -r 'main@origin..@ & files("<filename>")' | Find all changes that contain <filename> |
|jj restore --changes-in <change_id> <filename> | Remove <filename> from <change_id> |
|jj bookmark set main -r @ | Move local main bookmark to point to the current change (@) |
|jj git push --remote origin -b main | push local main to GitHub |
--------
