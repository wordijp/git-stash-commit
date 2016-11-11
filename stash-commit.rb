#!ruby

$:.unshift File.dirname(__FILE__)
require 'helper.rb'

MAX = 5
PREFIX = 'stash-commit'
TMP_SUFFIX = 'progresstmp'
REMAIN_SUFFIX = 'patch-remain'

def systemRet(cmd)
  Kernel.system(cmd)
  $?.success?
end

def stashName(branch, no)
  "#{PREFIX}/#{branch}@#{no}"
end

def getTmp
  `git stash-commit-list-all | grep -E '#{TMP_SUFFIX}$' | head -n 1 | tr -d '\n'`
end

# --------------------------------------------------

def validateRebase
  return true if getTmp != ''
  return true if systemRet 'git rebase-in-progress'

  puts 'stash-commit (--continue | --skip | --abort) is not need'
  return false
end

def validateRename(branch, renameOld, renameNew)
  return false if !validateStashCommitFromTo branch # 同じ
  return false if !validateFromTo renameOld
  return false if !validateFromTo renameNew
  if renameOld == renameNew
    puts "old:\"#{renameOld}\" new:\"#{renameNew}\" is same"
    return false
  end

  return true
end

def validateFromTo(fromto)
  # 数値 or ブランチ名
  if fromto == ''
    puts 'target name is empty'
    return false
  end
  if fromto.match(/^#{PREFIX}/)
    puts "/^#{PREFIX}/ is reserved words"
    return false
  end
  if fromto.match(/#{TMP_SUFFIX}$/)
    puts "/#{TMP_SUFFIX}$/ is reserved words"
    return false
  end
  if fromto.match(/#{REMAIN_SUFFIX}$/)
    puts "/#{REMAIN_SUFFIX}$/ is reserved words"
    return false
  end
  if fromto.match(/@/)
    puts '@ is used in delimiter'
    return false
  end

  return true
end

def validateStashCommitFromTo(branch)
  if systemRet 'git rebase-in-progress'
    puts 'now rebase in progress, please fix it'
    return false
  end
  if getTmp != ''
    puts 'find tmp branch, please fix it'
    return false
  end

  if branch.match(/^#{PREFIX}/)
    puts "can't work in stash-commit branch" # ネストはややこしい
    return false
  end

  return true
end

def validateStashCommitFrom(branch)
  if `git changes-count` != '0'
    puts 'find editing files, please fix it'
    return false
  end
  return false if !validateStashCommitFromTo branch

  return true
end

def validateStashCommitTo(branch)
  if `git changes-count` == '0'
    puts 'not need'
    return false
  end
  return false if !validateStashCommitFromTo branch

  return true
end

# --------------------------------------------------

def tryCommitTracked(stash, commitMessage)
  return false if !systemRet "git checkout -b \"#{stash}\""
  return false if !systemRet "git commit-tracked -m \"#{commitMessage}\""

  return true
end

def tryStashCommitTo(branch, no, commitMessage, commit)
  stash = stashName branch, no
  return false if !tryCommitTracked stash, commitMessage
  return false if !systemRet "git checkout \"#{branch}\""

  return true
end

def tryStashCommitToGrow(branch, to, commitMessage, commit)
  # TODO ちゃんと、存在してるかを事前に調べて場合分けする

  return true if tryStashCommitTo branch, to, commitMessage

  # 存在してるので、そのブランチへ追加する
  toTmp = "#{to}-#{TMP_SUFFIX}"
  tmpBranch = stashName branch, toTmp
  stashBranch = stashName branch, to
  return false if !tryCommitTracked tmpBranch, commitMessage
  return false if !systemRet "git rebase \"#{stashBranch}\" \"#{tmpBranch}\""
  return false if !systemRet "git rebase \"#{tmpBranch}\" \"#{stashBranch}\""
  return false if !systemRet "git branch -d \"#{tmpBranch}\""
  return false if !systemRet "git checkout \"#{branch}\""

  return true
end

# --------------------------------------------------

def tryStashCommitFrom(branch, from, noReset)
  stashBranch = stashName branch, from
  baseHash = `git show-branch --merge-base "#{branch}" "#{stashBranch}" | tr -d '\n'`
  return false if !systemRet "git rebase --onto \"#{branch}\" \"#{baseHash}\" \"#{stashBranch}\""

  # ここまでくれば安心
  revision = `git revision \"#{branch}\"`
  return false if !systemRet "git rebase \"#{stashBranch}\" \"#{branch}\""
  return false if !systemRet "git branch -d \"#{stashBranch}\""
  if !noReset
    return false if !systemRet "git reset \"#{revision}\""
  end

  return true
end

# --------------------------------------------------

def tryStashCommitContinueTo(tmpBranch)
  stashBranch = tmpBranch.match(/^(#{PREFIX}\/.+)-#{TMP_SUFFIX}$/)[1]
  rootBranch = tmpBranch.match(/^#{PREFIX}\/(.+)@.+-#{TMP_SUFFIX}$/)[1]

  # rebase --continue前かもしれない
  return false if systemRet('git rebase-in-progress') && !systemRet('git rebase --continue')
  # rebase --abort後で別ブランチかもしれない
  return false if !systemRet "git rebase \"#{stashBranch}\" \"#{tmpBranch}\""
  # rebase --skip後かもしれない
  return false if !systemRet "git parent-child-branch \"#{tmpBranch}\" \"#{stashBranch}\""

  # ここまでくれば安心
  return false if !systemRet "git rebase \"#{tmpBranch}\" \"#{stashBranch}\""
  return false if !systemRet "git branch -d \"#{tmpBranch}\""
  return false if !systemRet "git checkout \"#{rootBranch}\""

  return true
end

def tryStashCommitContinueFrom(branch)
  # tmpが無いので、rebase中の時のみ継続
  return false if !systemRet 'git rebase-in-progress'

  stashMatch = branch.match(/.+rebasing (#{PREFIX}\/.+)\)$/)
  rootMatch = branch.match(/.+rebasing #{PREFIX}\/(.+)@.+\)$/)
  return false if !stashMatch
  return false if !systemRet 'git rebase --continue'

  # ここまでくれば安心
  stashBranch = stashMatch[1]
  rootBranch = rootMatch[1]
  return false if !systemRet "git rebase \"#{stashBranch}\" \"#{rootBranch}\""
  return false if !systemRet "git branch -d \"#{stashBranch}\""

  return true
end

def tryStashCommitContinue(branch)
  tmpBranch = getTmp
  if tmpBranch != ''
    return tryStashCommitContinueTo tmpBranch
  else
    return tryStashCommitContinueFrom branch
  end
end

# --------------------------------------------------

def tryStashCommitSkipTo(tmpBranch)
  stashBranch = tmpBranch.match(/^(#{PREFIX}\/.+)-#{TMP_SUFFIX}$/)[1]
  rootBranch = tmpBranch.match(/^#{PREFIX}\/(.+)@.+-#{TMP_SUFFIX}$/)[1]

  # rebase --skip前かもしれない
  return false if systemRet('git rebase-in-progress') && !systemRet('git rebase --skip')
  # rebase --continue後かもしれない
  return false if systemRet "git parent-child-branch \"#{tmpBranch}\" \"#{stashBranch}\""
  # rebase --abort後はスルー

  # ここまでくれば安心
  return false if !systemRet "git checkout \"#{rootBranch}\""
  return false if !systemRet "git branch -D \"#{tmpBranch}\"" # skipなのでtmpを捨てる

  return true
end

def tryStashCommitSkipFrom(branch)
  # tmpが無いので、rebase中の時のみ継続
  return false if !systemRet 'git rebase-in-progress'

  stashMatch = branch.match(/.+rebasing (#{PREFIX}\/.+)\)$/)
  rootMatch = branch.match(/.+rebasing #{PREFIX}\/(.+)@.+\)$/)
  return false if !stashMatch
  return false if !systemRet 'git rebase --skip'

  # ここまでくれば安心
  stashBranch = stashMatch[1]
  rootBranch = rootMatch[1]
  return false if !systemRet "git rebase \"#{stashBranch}\" \"#{rootBranch}\""
  return false if !systemRet "git branch -d \"#{stashBranch}\""

  return true
end

def tryStashCommitSkip(branch)
  tmpBranch = getTmp
  if tmpBranch != ''
    return tryStashCommitSkipTo tmpBranch
  else
    return tryStashCommitSkipFrom branch
  end
end

# --------------------------------------------------

def tryStashCommitAbortTo(tmpBranch)
  stashBranch = tmpBranch.match(/^(#{PREFIX}\/.+)-#{TMP_SUFFIX}$/)[1]
  rootBranch = tmpBranch.match(/^#{PREFIX}\/(.+)@.+-#{TMP_SUFFIX}$/)[1]

  # rebase --abort前かもしれない
  return false if systemRet('git rebase-in-progress') && !systemRet('git rebase --abort')
  # rebase --continue後かもしれない
  return false if systemRet "git parent-child-branch \"#{tmpBranch}\" \"#{stashBranch}\""
  # rebase --skip後かもしれない
  return false if systemRet "git same-branch \"#{tmpBranch}\" \"#{stashBranch}\""
  # 念の為
  return false if !systemRet "git parent-child-branch \"#{tmpBranch}\" \"#{rootBranch}\""

  # ここまでくれば安心
  return false if !systemRet "git rebase \"#{tmpBranch}\" \"#{rootBranch}\""
  return false if !systemRet "git branch -d \"#{tmpBranch}\""
  return false if !systemRet 'git reset HEAD~'

  return true
end

def tryStashCommitAbortFrom(branch)
  # tmpが無いので、rebase中の時のみ継続
  return false if !systemRet 'git rebase-in-progress'

  rootMatch = branch.match(/.+rebasing #{PREFIX}\/(.+)@.+\)$/)
  return false if !rootMatch
  return false if !systemRet 'git rebase --abort'

  # ここまでくれば安心
  rootBranch = rootMatch[1]
  return false if !systemRet "git checkout \"#{rootBranch}\""

  return true
end

def tryStashCommitAbort(branch)
  tmpBranch = getTmp
  if tmpBranch != ''
    return tryStashCommitAbortTo tmpBranch
  else
    return tryStashCommitAbortFrom branch
  end
end

# --------------------------------------------------

def tryStashCommitRename(branch, renameOld, renameNew)
  # 名前被りチェック
  preCmd = "git stash-commit-list-all | sed -E 's/^#{PREFIX}\\/(.+)@.+$/\\1/g' | sort | uniq"

  # renameOldの存在チェック
  if `#{preCmd} | grep -w \"#{renameOld}\" | wc -l | tr -d '\n'` == '0'
    puts "'#{renameOld}' name is not found"
    return false
  end

  beforeCount = `#{preCmd} | wc -l | tr -d '\n'`
  afterCount = `#{preCmd} | sed 's/#{renameOld}/#{renameNew}/' | sort | uniq | wc -l | tr -d '\n'`

  # 数が減っている(= 名前が被ってる)
  if beforeCount != afterCount
    puts 'name is overlap'
    return false
  end

  # ここまでくれば安心
  # rename処理
  renameCmd = <<-EOS
  git stash-commit-list-all | \
    grep -E "^.+#{renameOld}@.+$" | \
    awk '{old=$0; new=$0; sub("#{renameOld}", "#{renameNew}", new); print old; print new;}' | \
    xargs -L 2 git branch -m
  EOS
  return false if !systemRet renameCmd

  return true
end

# --------------------------------------------------

def usage
  print <<-EOS
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
    NOTE : #{PREFIX}/<oldname>@to #{PREFIX}/<newname>@to
  git stash-commit help
EOS
end

# --------------------------------------------------

class ArgvIterator
  def initialize(argv)
    @argv = argv
    @index = 0
  end

  def next?
    @index < @argv.length
  end

  def next
    if @index < @argv.length
      ret = @argv[@index]
      @index += 1
      return ret
    else
      puts '* error: argument is not enoufh'
      usage
      Kernel.exit false
    end
  end

  def rebaseMode
    if @argv.length != 1
      puts '* error: illegal argument'
      usage
      Kernel.exit false
    end
  end
end

module Rebase
  CONTINUE = '--continue'
  SKIP     = '--skip'
  ABORT    = '--abort'
end

module Commit
  ALL   = '--all'
  PATCH = '--patch'
end

def main(argv)
  hash=`git revision`
  branch=`git branch-name`
  title=`git title`

  commitMessage = "WIP on #{branch}: #{hash} #{title}" # default
  to = nil
  from = nil
  noReset = false
  rebase = nil
  commit = Commit::ALL
  renameOld = nil
  renameNew = nil

  # parse argv
  # ----------
  itArgv = ArgvIterator.new(argv)
  while itArgv.next? do
    arg = itArgv.next
    case arg
    when '-m', '--message'
      commitMessage = itArgv.next
    when '--to'
      to = itArgv.next
    when '--from'
      from = itArgv.next
    when '--no-reset'
      noReset = true
    when '-a', '--all'
      commit = Commit::ALL
    when '-p', '--patch'
      commit = Commit::PATCH
    when '--continue'
      itArgv.rebaseMode
      rebase = Rebase::CONTINUE
    when '--skip'
      itArgv.rebaseMode
      rebase = Rebase::SKIP
    when '--abort'
      itArgv.rebaseMode
      rebase = Rebase::ABORT
    when '--rename'
      renameOld = itArgv.next
      renameNew = itArgv.next
    when 'help'
      usage
      Kernel.exit true
    else
      puts "* error: unknown option:#{arg}"
      usage
      Kernel.exit false
    end
  end

  # [rebase] --continue | --skip | --abort
  # --------------------------------------
  if rebase != nil
    if validateRebase
      case rebase
      when Rebase::CONTINUE
        return if tryStashCommitContinue branch
      when Rebase::SKIP
        return if tryStashCommitSkip branch
      when Rebase::ABORT
        return if tryStashCommitAbort branch
      end
    end

    puts "* failed: stash-commit #{rebase}"
    Kernel.exit false
  end

  # --rename
  # --------
  if renameOld != nil
    if validateRename branch, renameOld, renameNew
      return if tryStashCommitRename branch, renameOld, renameNew
    end

    puts '* failed: stash-commit --rename'
    Kernel.exit false
  end

  # stash-commit --from | --to
  # --------------------------
  if from != nil
    if validateFromTo from and
       validateStashCommitFrom branch
      return if tryStashCommitFrom branch, from, noReset
    end

    puts '* failed: stash-commit --from (index | name)'
    Kernel.exit false
  elsif to != nil
    # --to 指定がある時
    if validateFromTo to and
       validateStashCommitTo branch
      return if tryStashCommitToGrow branch, to, commitMessage, commit
    end

    puts '* failed: stash-commit --to (index | name)'
    Kernel.exit false
  else
    # --to 指定がない時
    if validateStashCommitTo branch
      MAX.times do |i|
        return if tryStashCommitTo branch, i, commitMessage, commit
      end
    end

    puts '* failed: stash-commit branch is too many'
    Kernel.exit false
  end
end

main ARGV
