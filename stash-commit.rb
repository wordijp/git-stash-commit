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

def validateRebase
  return true if systemRet 'git rebase-in-progress'
  return true if getTmp != ''

  puts 'stash-commit (--continue | --skip | --abort) is not need'
  return false
end

def validateStashCommit(branch)
  if branch.match(/^#{PREFIX}/)
    puts "can't work in stash-commit branch" # ネストはややこしい
    return false
  end

  return true
end

# --------------------------------------------------

def tryCommitTracked(stash, commitMessage)
  return false if !systemRet "git checkout -b \"#{stash}\""
  return false if !systemRet "git commit-tracked -m \"#{commitMessage}\""

  return true
end

def tryStashCommit(branch, no, commitMessage)
  stash = stashName branch, no
  return false if !tryCommitTracked stash, commitMessage
  return false if !systemRet "git checkout #{branch}"

  return true
end

def tryStashCommitGrow(branch, to, commitMessage)
  return true if tryStashCommit branch, to, commitMessage

  # 存在してるので、そのブランチへ追加する
  toTmp = "#{to}-#{TMP_SUFFIX}"
  tmpBranch = stashName branch, toTmp
  stashBranch = stashName branch, to
  return false if !tryCommitTracked tmpBranch, commitMessage
  return false if !systemRet "git rebase \"#{stashBranch}\" \"#{tmpBranch}\""
  return false if !systemRet "git rebase \"#{tmpBranch}\" \"#{stashBranch}\""
  return false if !systemRet "git branch -d \"#{tmpBranch}\""
  return false if !systemRet "git checkout #{branch}"

  return true
end

# --------------------------------------------------

def tryStashCommitContinue
  tmpBranch = getTmp
  if tmpBranch == ''
    puts 'tmp is not found'
    return false
  end
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
  return false if !systemRet "git checkout #{rootBranch}"

  return true
end

# --------------------------------------------------

def tryStashCommitSkip
  tmpBranch = getTmp
  if tmpBranch == ''
    puts 'tmp is not found'
    return false
  end
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
  if tmpBranch == ''
    puts 'tmp is not found'
    return false
  end
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
  git stash-commit [--to (index | branch name)]
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
      # TODO : バリエーション対応(コミットハッシュ | ブランチ名)
      if i >= argv.length
        usage
        Kernel.exit false
      end
      to = argv[i].to_i
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

  # continue | skip | abort
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

  # 作業中のブランチがある?
  if getTmp != ''
    puts '* error: find tmp branch, please fix it.'
    Kernel.exit false
  end

  if `git changes-count` == '0'
    puts 'not need'
    return
  end

  if to != nil
    # 指定がある時
    Kernel.exit false if !validateStashCommit branch
    if tryStashCommitGrow branch, to, commitMessage
      puts 'success'
      return
    end

    puts '* failed: stash-commit to'
    Kernel.exit false
  else
    # 指定がない時
    Kernel.exit false if !validateStashCommit branch
    MAX.times do |i|
      if tryStashCommit branch, i, commitMessage
        puts 'success'
        return
      end
    end

    puts '* failed: stash-commit branch is too many'
    Kernel.exit false
  end
end

main ARGV
