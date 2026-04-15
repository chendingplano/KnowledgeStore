= Worktree
A worktree is a separate folder where a branch is checked out, with shared Git history but independent editable files. There should never have multiple worktrees on the same branch.

Normally, GIT enforces:
- one repo has only one working directory 
- working directory maps to one branch checkout
In other word, if you want to switch from one branch to another branch, GIT will 'wipe' out
whatever in the current branch, and then checkout the other branch. We may consider this
as a 'view' of GIT. GIT allows only one view.
```text
[Repo]
  └── Working Dir (only one)
        └── Branch (switchable)
```

Worktree allows you to have multiple working directories, thus multiple checkouts.
```text
[Repo (.git shared)]
  ├── Working Dir A → branch main
  ├── Working Dir B → branch feature-x
  └── Working Dir C → branch bugfix
```

Without worktrees, if I want to have multiple checkouts simultaneously, I need to have
multiple clones, not multiple branches of the same clone. It works, but slower and 
uses more disk space.

# Commands
| Command | Explanation |
|---------|-------------|
|```git worktree add ../repo-feature-x feature-x``` | Create a new folder: '../repo-feature-x', Check out branch 'feature-x' there |
|```git worktree add -b feature-x ../repo-feature-x``` | Create branch 'feature-x', Create worktree |
| ```git worktree list``` | List worktrees |
| ```git worktree remove ../repo-feature-x``` | Remove worktree 'repo-feature-x' |