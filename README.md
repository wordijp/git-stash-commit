# git-stash-commit
==================

git sub command made in ruby, stash change files as commit of branch.
when have the change files, commit to 'stash-commit' branch, and restore it. this command is instead of the 'git stash'


## Installation

    $ gem install git-stash-commit


## stash-commit branches

when run 'git stash-commit --to NAME', change files commit to prefixed with 'stash-commit/' and postfixed with '@NAME' branch('stash-commit/from_branch@NAME').
commit, and make a new stash-commit/*topic*@NAME branch point to it.

    --- * --- * --- *          <-- topic
                     \
                      *        <-- stash-commit/topic@NAME

the second time, if when run 'git stash-commit', --to is serial number(default, start is 0).

    --- * --- * --- *          <-- topic
                    |\
                    | *        <-- stash-commit/topic@NAME
                     \ 
                      *        <-- stash-commit/topic@0


the third time, when run 'git stash-commit', next serial number is '1'.

    --- * --- * --- *          <-- topic
                    |\
                    | *        <-- stash-commit/topic@NAME
                    |\  
                    | *        <-- stash-commit/topic@0
                     \
                      *        <-- stash-commit/topic@1

the fourth time, when run 'git stash-commit --to 0', growth commit to 'stash-commit/topic@0'.

    --- * --- * --- *          <-- topic
                    |\
                    | *        <-- stash-commit/topic@NAME
                    |\  
                    | * --- *  <-- stash-commit/topic@0
                     \
                      *        <-- stash-commit/topic@1


unstash branch, if when run 'git stash-commit --from NAME', apply 'stash-commit/topic@NAME' branch on top of the current working tree state.

    --- * --- * --- *          <-- topic
                    |\  
                    | * --- *  <-- stash-commit/topic@0
                     \
                      *        <-- stash-commit/topic@1


## git-stash-commit commands

show command help

    $ git stash-commit help

```
usage)
  git stash-commit [--to (index | name)] [-m <commit message>] [-a | -p]
    options : --to              default: unused index
              -m | --message    default: "WIP on <branch>: <hash> <title>"
              -a | --all        default
              -p | --patch
    NOTE : --all   equal 'git commit --all'
           --patch equal 'git commit --patch'
  git stash-commit --from (index | name) [--no-reset]
    NOTE : --no-reset rebase only
  git stash-commit --continue
  git stash-commit --skip
  git stash-commit --abort
  git stash-commit --rename <oldname> <newname>
    NOTE : stash-commit/<oldname>@to stash-commit/<newname>@to
  git stash-commit -l [-a]
    options : -l | --list       listup stash-commit branch, in this group
              -a | --all        listup stash-commit branch all
  git stash-commit help
  git stash-commit <any args> [-d]
    options : -d | --debug      debug mode, show backtrace
```

## if CONFLICT

if conflict of 'stash-commit [--to N] [-p]' command, working branch remains.

* stash-commit/*topic*@backup
  - backup branch of this time, contains commit all change files
  - delete on complete
* stash-commit/*topic*@*to*-progresstmp
  - growth commit branch, contains change files of 'commit --patch', it add to '--to' target branch
  - delete on complete
* stash-commit/*topic*@*to*-progresstmp-patch-remain
  - commit remain branch, contains remain change files of 'commit --patch', it apply the current working tree state
  - delete on complete

if fixed CONFLICT, add to it and run 'git stash-commit --continue'  
if cancel this time, run 'git stash-commit --abort'  
if skip this time, run 'git stash-commit --skip'

these options behave like rebase.

the conflict of '--from' is also the same.


## if renamed branch name

if renamed branch 'topic' to 'renamed_topic', please run 'git stash-commit --rename topic renamed_topic'.


## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/wordijp/git-stash-commit.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

