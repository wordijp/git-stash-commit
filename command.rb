# ラッパーコマンド群

$:.unshift File.dirname(__FILE__)
require 'define.rb'
require 'open3'

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
  private
    _memo_gitdir = nil
    def gitdir
      @_memo_gitdir = @_memo_gitdir || `git rev-parse --git-dir`.chomp
    end
  public

  def revision(target='HEAD')
    `git rev-parse --short #{target}`.chomp
  end
  def title
    `git log -1 --pretty=format:\"%s\"`
  end
  def branchName
    `git branch`.each_line do |line|
      return line[1..-1].strip if line[0] == '*'
    end
  end

  # 引数のブランチは存在してるか?
  def branchExist?(branch)
    `git branch`.each_line do |_line|
      line = _line
      line = line[1..-1] if line[0] == '*'
      line = line.strip
      return true if line == branch
    end

    return false
  end
  # 引数のdetached branchは存在してるか?
  def branchRefExist?(branch)
    execRetQuiet "test -f \"#{gitdir}/refs/#{branch}\""
  end
  # ----------------
  # stash-commit ---
  # stash-commmitのbranch一覧
  def listup(_branchName, all)
    preCmd = "git branch | sed -E 's/^\\*/ /' | awk '{print $1}' | grep -E '^#{PREFIX}/'"
    if all
      print `#{preCmd}`
    else
      # グループ表示
      rootBranch = _branchName.match(/^(#{PREFIX}\/)?(.+?)(@.+)?$/)[2]
      print `#{preCmd} | grep "#{rootBranch}"`
    end
  end
  def getTmp
    findFirstCommitStashRef(){|line| line.match(/#{TMP_SUFFIX}$/)}
  end
  def getPatchRemain
    findFirstCommitStashRef(){|line| line.match(/#{PATCH_REMAIN_SUFFIX}$/)}
  end
  def getBackup
    findFirstCommitStashRef(){|line| line.match(/#{BACKUP_SUFFIX}$/)}
  end
  private
    def findFirstCommitStashRef(&pred)
      `find #{gitdir}/refs/#{PREFIX} -type f`.each_line do |_line|
        line = _line.strip
        line = line.sub(/^.*\.git\/refs\//, '')
        return line if pred.call line
      end
      return ''
    end
  public
  def stashName(branch, no)
    "#{PREFIX}/#{branch}@#{no}"
  end
  def stashCommitRename(renameOld, renameNew)
    # NOTE : 利用頻度低いので未tuning

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
  public
  # ----------------

  # trackedファイルの変更数
  def changesCount
    count = 0
    `git status --untracked-files=no --short`.each_line {count += 1}
    "#{count}"
  end
  # rebase中?
	# http://stackoverflow.com/questions/3921409/how-to-know-if-there-is-a-git-rebase-in-progress
	# rebase-apply : rebase
	# rebase-merge : rebase -i
  def rebaseInProgress?
		git_dir = gitdir
    execRetQuiet "test -d \"#{git_dir}/rebase-merge\" -o -d \"#{git_dir}/rebase-apply\""
  end
  # 引数のブランチは親子?
  def parentChildBranch?(a, b='HEAD')
    hashs = `git rev-parse \"#{a}\" \"#{b}\" \"#{a}~\" \"#{b}~\"`.split

    hash_a_parent = hashs[0] || ''
    hash_b_parent = hashs[1] || ''
    hash_a_child  = hashs[2] || ''
    hash_b_child  = hashs[3] || ''

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
    hashs = `git rev-parse \"#{a}\" \"#{b}\"`.split

    hash_a = hashs[0] || ''
    hash_b = hashs[1] || ''

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
    `git show-branch --merge-base \"#{a}\" \"#{b}\"`.chomp
  end

  # ----------

  # rebase専用コマンド
  def execForRebase(name, rebaseCmd)
    o, e, s = Open3::capture3 rebaseCmd
    puts o if o != ''
    if !s.success?
      # NOTE : コンフリクト時、
      #        標準出力にコンフリクトメッセージ
      #        標準エラー出力に--continue | --skip | --abortについて
      if o.match('CONFLICT') and o.match('Merge conflict')
        STDERR.puts <<-EOS
error: could not apply #{revision name}...

problem resolved, run "git stash-commit --continue".
skip this patch, run "git stash-commit --skip".
cancel this time, run "git stash-commit --abort".
EOS
      else
        STDERR.puts e
      end
      raise "failed, cmd:#{rebaseCmd}"
    end
  end

  # ----------

  def tuneLimit
    # 一番軽いと思われる外部コマンド
    `echo tuneLimit`
  end
end
