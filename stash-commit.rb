#!ruby

$:.unshift File.dirname(__FILE__)
require 'helper.rb'
require 'branch.rb'
require 'command.rb'
require 'define.rb'

if !Cmd::gitdirExist?
  puts 'git dir is not found'
  Kernel.exit false
end

# XXX : gitconfigのaliasを利用している為、密結合
# FIXME : 途中で強制終了した際、ブランチが破壊される事がある

MAX = 5

G = Struct.new(:tmp, :patch, :backup)
# XXX : めちゃ遅い
$g = G.new(
  BranchFactory::find(Cmd::getTmp),
  BranchFactory::find(Cmd::getPatchRemain),
  BranchFactory::find(Cmd::getBackup))

# --------------------------------------------------

def validateRebase
  return true if $g.tmp
  return true if Cmd::rebaseInProgress?
  return true if $g.patch

  puts 'stash-commit (--continue | --skip | --abort) is not need'
  return false
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
  if fromto.match(/#{PATCH_REMAIN_SUFFIX}$/)
    puts "/#{PATCH_REMAIN_SUFFIX}$/ is reserved words"
    return false
  end
  if fromto.match(/#{BACKUP_SUFFIX}$/)
    puts "/#{BACKUP_SUFFIX}$/ is reserved words"
    return false
  end
  if fromto.match(/@/)
    puts '@ is used in delimiter'
    return false
  end

  return true
end

def validateStashCommitFromTo(branch)
  if Cmd::rebaseInProgress?
    puts 'now rebase in progress, please fix it'
    return false
  end
  if $g.tmp
    puts 'find tmp branch, please fix it'
    return false
  end
  if $g.patch
    puts 'find patch branch, please fix it'
    return false
  end
  if $g.backup
    puts'find backup branch, please fix it'
    return false
  end

  if branch.match(/^#{PREFIX}/)
    puts "can't work in stash-commit branch" # ネストはややこしい
    return false
  end

  return true
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

def validateStashCommitFrom(branch)
  if Cmd::changesCount != '0'
    puts 'find editing files, please fix it'
    return false
  end
  return false if !validateStashCommitFromTo branch

  return true
end

def validateStashCommitTo(branch)
  if Cmd::changesCount == '0'
    puts 'not need'
    return false
  end
  return false if !validateStashCommitFromTo branch

  return true
end

# --------------------------------------------------

def createBackup(_branch)
  retBackup = DetachBranch.new Cmd::stashName(_branch, BACKUP_SUFFIX), _branch
  branch = BranchFactory::find _branch
  retBackup.commit Branch::CommitMode::ALL, <<-EOS
backup from #{_branch}: #{Cmd::revision _branch}

*** backup commit ***
'stash-commit --to' working backup commit
EOS
  branch.cherryPickNoCommit retBackup.name
  branch.reset # cancel 'git add'

  retBackup
end

def _tryCommit(stash, mode, commitMessage, &onFail)
  root = BranchFactory::find stash.name.match(/^#{PREFIX}\/(.+)@.+$/)[1]
  stash.commit(mode, commitMessage){
    # commit --patchのキャンセル時ここに来る
    root.checkout
    $g.backup.delete
    onFail.call
  }

  if Cmd::changesCount != '0'
    remain = DetachBranch.new "#{stash.name}-#{PATCH_REMAIN_SUFFIX}", stash.name
    remain.commit Branch::CommitMode::ALL, <<-EOS
patch-remain from #{Cmd::revision stash.name}: #{hash}

*** patch remain ***
'stash-commit --patch' working patch remain commit.

please fix conflicts without '#{stash.name}' contents
EOS
    $g.patch = remain
  end

  return true
end
def tryCommitAll(stash, commitMessage, &onFail)
  _tryCommit(stash, Branch::CommitMode::ALL, commitMessage){onFail.call}
end
def tryCommitPatch(stash, commitMessage, &onFail)
  _tryCommit(stash, Branch::CommitMode::PATCH, commitMessage){onFail.call}
end

def tryStashCommitToInternal(stash, commitMessage, commit, reset=true, backup=true)
  root = BranchFactory::find stash.name.match(/^#{PREFIX}\/(.+)@.+$/)[1]

  $g.backup = createBackup root.name if backup

  case commit
  when Commit::ALL
    return false if !tryCommitAll(stash, commitMessage){stash.delete}
    root.checkout
  when Commit::PATCH
    return false if !tryCommitPatch(stash, commitMessage){stash.delete}

    if $g.patch
      $g.patch.rebaseOnto root.name, "#{$g.patch.name}~"

      if reset
        revision = Cmd::revision root.name
        root.rebase $g.patch.name
        $g.patch.delete
        root.reset revision
      else
        root.checkout
      end
    else
      root.checkout
    end
  end

  $g.backup.delete if backup

  return true
end

def tryStashCommitTo(stashBranch, commitMessage, commit, reset=true, backup=true)
  rootBranch = stashBranch.match(/^#{PREFIX}\/(.+)@.+$/)[1]
  stash = Branch::new stashBranch, rootBranch
  tryStashCommitToInternal stash, commitMessage, commit, reset, backup
end

def tryStashCommitToGrow(branch, to, commitMessage, commit)
  stashBranch = Cmd::stashName branch, to
  root = BranchFactory::find stashBranch.match(/^#{PREFIX}\/(.+)@.+$/)[1]

  $g.backup = createBackup root.name

  if !Cmd::branchExist? stashBranch
    # 新規作成
    stash = Branch.new stashBranch, root.name
    return false if !tryStashCommitToInternal stash, commitMessage, commit, true, false
  else
    # 存在してるので、そのブランチへ追加する
    # 一端新規作成し
    tmp = DetachBranch.new "#{stashBranch}-#{TMP_SUFFIX}", root.name
    return false if !tryStashCommitToInternal tmp, commitMessage, commit, false, false

    stash = BranchFactory::find stashBranch

    # rebaseで追加
    tmp.rebase stash.name
    stash.rebase tmp.name
    tmp.delete

    root.checkout

    case commit
    when Commit::ALL
      # no-op
    when Commit::PATCH
      if $g.patch
        revision = Cmd::revision root.name
        root.rebase $g.patch.name
        $g.patch.delete
        root.reset revision
      end
    end
  end

  $g.backup.delete

  return true
end

# --------------------------------------------------

def tryStashCommitFrom(_branch, from)
  stash = BranchFactory::find (Cmd::stashName _branch, from)
  branch = BranchFactory::find _branch

  baseHash = Cmd::mergeBaseHash branch.name, stash.name
  stash.rebaseOnto branch.name, baseHash

  # ここまでくれば安心
  revision = Cmd::revision branch.name
  branch.rebase stash.name
  stash.delete
  branch.reset revision

  return true
end

# --------------------------------------------------

def tryStashCommitContinueTo(tmp, patch)
  # rebase --continue前かもしれない
  Cmd::exec('git rebase --continue') if Cmd::rebaseInProgress?

  if patch
    root = BranchFactory::find patch.name.match(/^#{PREFIX}\/(.+)@.+-#{PATCH_REMAIN_SUFFIX}$/)[1]
    # rebase --skip後かもしれない
    if Cmd::sameBranch? patch.name, root.name
      puts "stop, '#{PATCH_REMAIN_SUFFIX}' rebase --skip found, from starting stash-commit --patch"
      raise
    end
    # rebase --abort後かもしれない
    if !Cmd::parentChildBranch? patch.name, root.name
      patch.rebaseOnto root.name, "#{patch.name}~"
    end
  end
  if tmp
    stash = BranchFactory::find tmp.name.match(/^(#{PREFIX}\/.+)-#{TMP_SUFFIX}$/)[1]
    # rebase --skip後かもしれない
    if Cmd::sameBranch? tmp.name, stash.name
      puts "stop, '#{TMP_SUFFIX}' rebase --skip found, from starting stash-commit --to"
      raise
    end
    # rebase --abort後かもしれない
    if !Cmd::parentChildBranch? tmp.name, stash.name
      tmp.rebaseOnto stash.name, "#{tmp.name}~"
    end
  end

  # ここまでくれば安心
  if tmp
    root = BranchFactory::find tmp.name.match(/^#{PREFIX}\/(.+)@.+-#{TMP_SUFFIX}$/)[1]
    stash = BranchFactory::find tmp.name.match(/^(#{PREFIX}\/.+)-#{TMP_SUFFIX}$/)[1]

    tmp.rebase stash.name
    stash.rebase tmp.name
    tmp.delete
    root.checkout
  end
  if patch
    root = BranchFactory::find patch.name.match(/^#{PREFIX}\/(.+)@.+-#{PATCH_REMAIN_SUFFIX}$/)[1]
    revision = Cmd::revision root.name

    root.rebase patch.name
    patch.delete
    root.reset revision
  end

  return true
end

def tryStashCommitContinueFrom(branch)
  # tmpが無いので、rebase中の時のみ継続
  return false if !Cmd::rebaseInProgress?

  stashMatch = branch.match(/.+rebasing (#{PREFIX}\/.+)\)$/)
  rootMatch = branch.match(/.+rebasing #{PREFIX}\/(.+)@.+\)$/)
  return false if !stashMatch
  return false if !Cmd::execRet 'git rebase --continue'

  # ここまでくれば安心
  stash = BranchFactory::find stashMatch[1]
  root = BranchFactory::find rootMatch[1]
  revision = Cmd::revision root.name
  root.rebase stash.name
  stash.delete
  root.reset revision

  return true
end

def tryStashCommitContinue(branch)
  if $g.tmp or $g.patch
    return false if !tryStashCommitContinueTo $g.tmp, $g.patch
    $g.backup.delete if $g.backup
  else
    return false if !tryStashCommitContinueFrom branch
  end

  return true
end

# --------------------------------------------------

def tryStashCommitSkipTo(tmp, patch)
  # rebase --skip前かもしれない
  Cmd::exec('git rebase --skip') if Cmd::rebaseInProgress?

  if patch
    root = BranchFactory::find patch.name.match(/^#{PREFIX}\/(.+)@.+-#{PATCH_REMAIN_SUFFIX}$/)[1]
    # rebase --continue後かもしれない
    if Cmd::parentChildBranch? patch.name, root.name
      puts "stop, '#{PATCH_REMAIN_SUFFIX}' rebase --continue found, from starting stash-commit --patch"
      raise
    end
    # rebase --abort後はスルー
  end
  if tmp
    stash = BranchFactory::find tmp.name.match(/^(#{PREFIX}\/.+)-#{TMP_SUFFIX}$/)[1]
    # rebase --continue後かもしれない
    if Cmd::parentChildBranch? tmp.name, stash.name
      puts "stop, '#{TMP_SUFFIX}' rebase --continue found, from starting stash-commit --to"
      raise
    end
    # rebase --abort後はスルー
  end

  # ここまでくれば安心
  if tmp
    root = BranchFactory::find tmp.name.match(/^#{PREFIX}\/(.+)@.+-#{TMP_SUFFIX}$/)[1]
    root.checkout
    tmp.delete # skipなので捨てる
  end
  if patch
    root = BranchFactory::find patch.name.match(/^#{PREFIX}\/(.+)@.+-#{PATCH_REMAIN_SUFFIX}$/)[1]
    root.checkout
    patch.delete # skipなので捨てる

    # もしかしたらtmpとして削除済み
    patchParent = BranchFactory::find patch.name.match(/^(#{PREFIX}\/.+)-#{PATCH_REMAIN_SUFFIX}$/)[1]
    if patchParent
      patchParent.delete
    end
  end

  return true
end

def tryStashCommitSkipFrom(branch)
  # tmpが無いので、rebase中の時のみ継続
  return false if !Cmd::rebaseInProgress?

  stashMatch = branch.match(/.+rebasing (#{PREFIX}\/.+)\)$/)
  rootMatch = branch.match(/.+rebasing #{PREFIX}\/(.+)@.+\)$/)
  return false if !stashMatch
  return false if !Cmd::execRet 'git rebase --skip'

  # ここまでくれば安心
  stash = BranchFactory::find stashMatch[1]
  root = BranchFactory::find rootMatch[1]
  root.rebase stash.name
  stash.delete

  return true
end

def tryStashCommitSkip(branch)
  if $g.tmp or $g.patch
    return false if !tryStashCommitSkipTo $g.tmp, $g.patch
    $g.backup.delete if $g.backup
  else
    return false if !tryStashCommitSkipFrom branch
  end

  return true
end

# --------------------------------------------------

def tryStashCommitAbortTo(tmp, patch)
  if !$g.backup
    puts "stop, '#{BACKUP_SUFFIX}' is not found, from starting stash-commit --to"
    return false
  end

  # rebase --abort前かもしれない
  Cmd::exec 'git rebase --abort' if Cmd::rebaseInProgress?

  if tmp
    root = BranchFactory::find tmp.name.match(/^#{PREFIX}\/(.+)@.+-#{TMP_SUFFIX}$/)[1]
    root.checkout
    tmp.delete
  end
  if patch
    root = BranchFactory::find patch.name.match(/^#{PREFIX}\/(.+)@.+-#{PATCH_REMAIN_SUFFIX}$/)[1]
    root.checkout
    patch.delete

    # もしかしたらtmpとして削除済み
    patchParent = BranchFactory::find patch.name.match(/^(#{PREFIX}\/.+)-#{PATCH_REMAIN_SUFFIX}$/)[1]
    if patchParent
      patchParent.delete
    end
  end

  # ここまでくれば安心
  root = BranchFactory::find $g.backup.name.match(/^#{PREFIX}\/(.+)@#{BACKUP_SUFFIX}$/)[1]
  root.checkout
  root.cherryPickNoCommit $g.backup.name
  root.reset # cancel 'git add'

  return true
end

def tryStashCommitAbortFrom(branch)
  # tmpが無いので、rebase中の時のみ継続
  return false if !Cmd::rebaseInProgress?

  rootMatch = branch.match(/.+rebasing #{PREFIX}\/(.+)@.+\)$/)
  return false if !rootMatch
  return false if !Cmd::execRet 'git rebase --abort'

  # ここまでくれば安心
  root = BranchFactory::find rootMatch[1]
  root.checkout

  return true
end

def tryStashCommitAbort(branch)
  if $g.tmp or $g.patch
    return false if !tryStashCommitAbortTo $g.tmp, $g.patch
    $g.backup.delete if $g.backup
  else
    return false if !tryStashCommitAbortFrom branch
  end

  return true
end

# --------------------------------------------------

def tryStashCommitRename(branch, renameOld, renameNew)
  Cmd::stashCommitRename renameOld, renameNew
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
  git stash-commit <any args> [-d]
    options : -d | --debug      debug mode, show backtrace
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
      raise
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

$debugMode = false

def main(argv)
  hash = Cmd::revision
  branch = Cmd::branchName
  title = Cmd::title

  commitMessage = "WIP on #{branch}: #{hash} #{title}" # default
  to = nil
  from = nil
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
    when '-a', '--all'
      commit = Commit::ALL
    when '-p', '--patch'
      commit = Commit::PATCH
    when '--continue'
      rebase = Rebase::CONTINUE
    when '--skip'
      rebase = Rebase::SKIP
    when '--abort'
      rebase = Rebase::ABORT
    when '--rename'
      renameOld = itArgv.next
      renameNew = itArgv.next
    when 'help'
      usage
      Kernel.exit true
    when '-d', '--debug'
      $debugMode = true
    else
      puts "* error: unknown option:#{arg}"
      usage
      raise
    end
  end

  # [rebase] --continue | --skip | --abort
  # --------------------------------------
  if rebase != nil
    begin
      raise if !validateRebase
      case rebase
      when Rebase::CONTINUE
        raise if !tryStashCommitContinue branch
      when Rebase::SKIP
        raise if !tryStashCommitSkip branch
      when Rebase::ABORT
        raise if !tryStashCommitAbort branch
      end
      return true
    rescue => e
      puts "* failed: stash-commit #{rebase}"
      raise e
    end
  end

  # --rename
  # --------
  if renameOld != nil
    begin
      raise if !validateRename branch, renameOld, renameNew
      raise if !tryStashCommitRename branch, renameOld, renameNew
      return true
    rescue => e
      puts '* failed: stash-commit --rename'
      raise e
    end
  end

  # stash-commit --from | --to
  # --------------------------
  if from != nil
    begin
      raise if !validateFromTo from or !validateStashCommitFrom branch
      raise if !tryStashCommitFrom branch, from
      return true
    rescue => e
      puts '* failed: stash-commit --from (index | name)'
      raise e
    end
  elsif to != nil
    # --to 指定がある時
    begin
      raise if !validateFromTo to or !validateStashCommitTo branch
      raise if !tryStashCommitToGrow branch, to, commitMessage, commit
      return true
    rescue => e
      puts '* failed: stash-commit --to (index | name)'
      raise e
    end
  else
    # --to 指定がない時
    begin
      raise if !validateStashCommitTo branch
      (MAX+1).times do |i|
        if i == MAX
          puts '* error: branch is too many'
          raise
        end

        stashBranch = Cmd::stashName branch, i
        if Cmd::branchExist? stashBranch
          puts "\"#{stashBranch}\" is already exist"
          next
        end

        raise if !tryStashCommitTo stashBranch, commitMessage, commit
        return true
      end
    rescue => e
      puts '* failed: stash-commit'
      raise e
    end
  end

  raise 'logic error' # ここには来ないはず
end

begin
  raise if !main ARGV
  puts 'done!'
rescue => e
  if $debugMode
    puts "* error: #{e}" if !e.message.empty?
    puts e.backtrace
  end
  puts 'failed'
  Kernel.exit false
end
