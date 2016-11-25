# ラッパーコマンド群

$:.unshift File.dirname(__FILE__)
require 'define.rb'

module Cmd
  extend self

  # 成否を戻り値か例外で知らせる
  def exec(cmd)
    raise "failed, cmd:#{cmd}" if !execRet cmd
  end
  
  def execRet(cmd)
    Kernel.system(cmd)
    $?.success?
  end

  def execQuiet(cmd)
    raise "failed, cmd:#{cmd}" if !execRetQuiet cmd
  end

  def execRetQuiet(cmd)
    execRet "#{cmd} > /dev/null 2>&1"
  end
  
  # 他のコマンド
  
  def gitdirExist?
    execRetQuiet 'git rev-parse --git-dir'
  end

  def revision(target='HEAD')
    `git rev-parse --short #{target} | tr -d '\n'`
    #`git rev-parse --short #{target}`.chomp
  end
  def title
    `git log -1 --pretty=format:\"%s\"`
  end
  def branchName
	  `git branch | grep -E '^\\*' | sed -E 's/^\\* //' | tr -d '\n'`
    # tuninged
    #`git branch`.each_line {|line|
    #  return line.chomp[2..-1] if line[0] == '*'
    #}
  end

  # 引数のブランチは存在してるか?
  def branchExist?(branch)
		`git branch | sed -E 's/^\\*/ /' | awk '{print $1}' | grep -E \"^#{branch}$\" | wc -l | tr -d '\n'` != '0'
  end
  # 引数のdetached branchは存在してるか?
  def branchRefExist?(branch)
		git_dir = `git rev-parse --git-dir | tr -d '\n'`
    execRetQuiet "test -f \"#{git_dir}/refs/#{branch}\""
  end
  # ----------------
  # stash-commit ---
  # stash-commmitのbranch一覧
  def stashCommitListAll
    `git branch | sed -E 's/^\\*/ /' | awk '{print $1}' | grep -E '^#{PREFIX}/'`
  end
  # stash-commmitのdetached branch一覧
  def stashCommitListAllRef
    `#{stashCommitListAllRefString}`
  end
  def getTmp
    `#{stashCommitListAllRefString} | grep -E '#{TMP_SUFFIX}$' | head -n 1 | tr -d '\n'`
  end
  def getPatchRemain
    `#{stashCommitListAllRefString} | grep -E '#{PATCH_REMAIN_SUFFIX}$' | head -n 1 | tr -d '\n'`
  end
  def getBackup
    `#{stashCommitListAllRefString} | grep -E '#{BACKUP_SUFFIX}$' | head -n 1 | tr -d '\n'`
  end
  def stashName(branch, no)
    "#{PREFIX}/#{branch}@#{no}"
  end
  def stashCommitRename(renameOld, renameNew)
    # 名前被りチェック
    preCmd = "#{stashCommitListAllString} | sed -E 's/^#{PREFIX}\\/(.+)@.+$/\\1/g' | sort | uniq"

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
    execRet <<-EOS
#{stashCommitListAllString} | \
  grep -E "^.+#{renameOld}@.+$" | \
  awk '{old=$0; new=$0; sub("#{renameOld}", "#{renameNew}", new); print old; print new;}' | \
  xargs -L 2 git branch -m
EOS
  end
  private
    def stashCommitListAllString
      "git branch | sed -E 's/^\\*/ /' | awk '{print $1}' | grep -E '^#{PREFIX}/'"
    end
    def stashCommitListAllRefString
      git_dir = `git rev-parse --git-dir | tr -d '\n'`
      "find #{git_dir}/refs/#{PREFIX} -type f | sed -E 's/^.*\\.git\\/refs\\///'"
    end
  public
  # ----------------

  # trackedファイルの変更数
  def changesCount
    `git status --untracked-files=no --short | wc -l | tr -d '\n'`
  end
  # rebase中?
	# http://stackoverflow.com/questions/3921409/how-to-know-if-there-is-a-git-rebase-in-progress
	# rebase-apply : rebase
	# rebase-merge : rebase -i
  def rebaseInProgress?
		git_dir = `git rev-parse --git-dir | tr -d '\n'`
    execRetQuiet "test -d \"#{git_dir}/rebase-merge\" -o -d \"#{git_dir}/rebase-apply\""
  end
  # 引数のブランチは親子?
  def parentChildBranch?(a, b='HEAD')
		hash_a_parent = `git rev-parse --short #{a}  | tr -d '\n'`
		hash_a_child  = `git rev-parse --short #{a}~ | tr -d '\n'`
		hash_b_parent = `git rev-parse --short #{b}  | tr -d '\n'`
		hash_b_child  = `git rev-parse --short #{b}~ | tr -d '\n'`
		if hash_a_parent == ''
      puts 'illegal branch'
      return false
    end
    if hash_b_parent == ''
      puts 'illegal branch'
      return false
    end
    
    hash_a_parent == hash_b_child or hash_b_parent == hash_a_child
  end
  # 引数のブランチは同じ?
  def sameBranch?(a, b='HEAD')
		hash_a = `git rev-parse --short #{a} | tr -d '\n'`
		hash_b = `git rev-parse --short #{b} | tr -d '\n'`
		if hash_a == ''
      puts 'illegal branch'
      return false
    end
    if hash_b == ''
      puts 'illegal branch'
      return false
    end
    
    hash_a == hash_b
  end
  # 2つのブランチの交差点をcommit hashで返す
  def mergeBaseHash(a, b)
   `git show-branch --merge-base "#{a}" "#{b}" | tr -d '\n'`
  end
end
