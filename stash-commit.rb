#!ruby

$:.unshift File.dirname(__FILE__)
require 'helper.rb'

MAX = 5
PREFIX = 'stash-commit'
TMP_SUFFIX = 'progresstmp'

def systemRet(cmd)
  Kernel.system(cmd)
  $?.success?
end

def stashName(branch, no)
  "#{PREFIX}/#{branch}@#{no}"
end

# --------------------------------------------------

def getTmp
  `git stash-commit-list-all | grep -E '#{TMP_SUFFIX}$' | head -n 1 | tr -d '\n'`
end

def validateFromTo(fromto)
  # 数値 or ブランチ名
  if fromto == ''
    puts 'target name is empty'
    return false
  end
  if fromto.match(/#{TMP_SUFFIX}$/)
    puts "/#{TMP_SUFFIX}$/ is reserved words"
    return false
  end

  return true
end

def validateRebase
  if getTmp == ''
    puts 'tmp is not found'
    return false
  end
  return true if systemRet 'git rebase-in-progress'

  puts 'stash-commit (--continue | --skip | --abort) is not need'
  return false
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

def tryStashCommitTo(branch, no, commitMessage)
  stash = stashName branch, no
  return false if !tryCommitTracked stash, commitMessage
  return false if !systemRet "git checkout \"#{branch}\""

  return true
end

def tryStashCommitToGrow(branch, to, commitMessage)
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

def tryStashCommitFrom(branch, from)
  stashBranch = stashName branch, from
  baseHash = `git show-branch --merge-base "#{branch}" "#{stashBranch}" | tr -d '\n'`
  return false if !systemRet "git rebase --onto \"#{branch}\" \"#{baseHash}\" \"#{stashBranch}\""

  # ここまでくれば安心
  return false if !systemRet "git rebase \"#{stashBranch}\" \"#{branch}\""
  return false if !systemRet "git branch -d \"#{stashBranch}\""

  return true
end

# --------------------------------------------------

def tryStashCommitContinue
  tmpBranch = getTmp
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

# --------------------------------------------------

def tryStashCommitSkip
  tmpBranch = getTmp
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

# --------------------------------------------------

def tryStashCommitAbort
  tmpBranch = getTmp
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

# --------------------------------------------------

def usage
  print <<-EOS
  git stash-commit [--to (index | name)]
  git stash-commit --from (index | name)
  git stash-commit --continue
  git stash-commit --skip
  git stash-commit --abort
  EOS
end

# --------------------------------------------------

def main(argv)
  hash=`git revision`
  branch=`git branch-name`
  title=`git title`

  commitMessage = "WIP on #{branch}: #{hash} #{title}" # default
  to = nil
  from = nil
  continue = false
  _skip = false
  _abort = false

  # parse argv
  i = 0
  while i < argv.length do
    case argv[i]
    when '-m', '--message'
      i += 1
      if i >= argv.length
        usage
        Kernel.exit false
      end
      commitMessage = argv[i]
    when '--to'
      i += 1
      if i >= argv.length
        usage
        Kernel.exit false
      end
      to = argv[i]
    when '--from'
      i += 1
      if i >= argv.length
        usage
        Kernel.exit false
      end
      from = argv[i]
    when '--continue'
      if argv.length != 1
        usage
        Kernel.exit false
      end
      continue = true
    when '--skip'
      if argv.length != 1
        usage
        Kernel.exit false
      end
      _skip = true
    when '--abort'
      if argv.length != 1
        usage
        Kernel.exit false
      end
      _abort = true
    when 'help'
      usage
      Kernel.exit true
    else
      puts "unknown option:#{argv[i]}"
      usage
      Kernel.exit false
    end

    i += 1
  end

  # --continue | --skip | --abort
  # -----------------------------
  if continue
    Kernel.exit false if !validateRebase

    if tryStashCommitContinue
      puts 'success'
      return
    end

    puts '* failed: stash-commit --contine'
    Kernel.exit false
  end
  if _skip
    Kernel.exit false if !validateRebase

    if tryStashCommitSkip
      puts 'success'
      return
    end

    puts '* failed: stash-commit --skip'
    Kernel.exit false
  end
  if _abort
    Kernel.exit false if !validateRebase

    if tryStashCommitAbort
      puts 'success'
      return
    end

    puts '* failed: stash-commit --abort'
    Kernel.exit false
  end

  # stash-commit --from | --to
  # --------------------------
  if from != nil
    Kernel.exit false if !validateFromTo from
    Kernel.exit false if !validateStashCommitFrom branch

    if tryStashCommitFrom branch, from
      puts 'success'
      return
    end

    puts '* failed: stash-commit --from (index | name)'
    Kernel.exit false
  elsif to != nil
    # --to 指定がある時
    Kernel.exit false if !validateFromTo to
    Kernel.exit false if !validateStashCommitTo branch
    if tryStashCommitToGrow branch, to, commitMessage
      puts 'success'
      return
    end

    puts '* failed: stash-commit --to (index | name)'
    Kernel.exit false
  else
    # --to 指定がない時
    Kernel.exit false if !validateStashCommitTo branch
    MAX.times do |i|
      if tryStashCommitTo branch, i, commitMessage
        puts 'success'
        return
      end
    end

    puts '* failed: stash-commit branch is too many'
    Kernel.exit false
  end
end

main ARGV
