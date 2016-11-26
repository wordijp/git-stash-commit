# ブランチ操作クラス
# 通常/detachedを等価的に扱えるラッパークラスを提供する

$:.unshift File.dirname(__FILE__)
require 'command.rb' # namespace cmd

module BranchFactory
  extend self

  # ブランチ名をもとに、通常/detachedブランチどちらかを判断し、返す
  def find(name)
    if Cmd::branchExist? name
      Branch.new name
    elsif Cmd::branchRefExist? name
      DetachBranch.new name
    else
      nil
    end
  end

end

module BranchCommon
  module CommitMode
    ALL   = '--all'
    PATCH = '--patch'
  end

  def initialize(name, maketarget='')
    @name = name
    if exist?
      # no-op
    elsif maketarget != ''
      make maketarget
    else
      raise 'Branch instanced failed'
    end
  end

  def name
    @name
  end

  def cherryPickNoCommit(target)
    checkout
    puts "[#{@name}]: git cherry-pick --no-commit \"#{target}\""
    Cmd::exec "git cherry-pick --no-commit \"#{target}\""
  end

  attr_reader :name
end

# 通常ブランチ
class Branch
  include BranchCommon

  def checkout
    Cmd::execQuiet "git checkout \"#{@name}\""
  end
  def delete(deletedBranch='', force=false)
    if deletedBranch != ''
      Cmd::execQuiet "git checkout \"#{deletedBranch}\""
    end
    opt = (force == true) ? '-D' : '-d'
    revision = Cmd::revision @name
    Cmd::execQuiet "git branch #{opt} \"#{@name}\""
    puts "Deleted detached branch #{@name} (was #{revision})"
  end
  def rebase(upstream)
    puts "[#{@name}]: git rebase \"#{upstream}\""
    Cmd::execForRebase @name, "git rebase \"#{upstream}\" \"#{@name}\""
  end
  def rebaseOnto(newbase, upstream)
    puts "[#{@name}]: git rebase --onto \"#{newbase}\" \"#{upstream}\" <SELF>"
    Cmd::execForRebase @name, "git rebase --onto \"#{newbase}\" \"#{upstream}\" \"#{@name}\""
  end
  def reset(target='')
    if target != ''
      checkout
      puts "[#{@name}]: git reset \"#{target}\""
      Cmd::exec "git reset \"#{target}\""
    else
      puts "[#{@name}]: git reset"
      Cmd::exec 'git reset'
    end
  end
  def commit(mode=CommitMode::ALL, _msg='', &onFail)
    msg = (_msg != '') ? "-m \"#{_msg}\"" : ''
    begin
      checkout
      puts "[#{@name}]: git commit #{mode} ..."
      Cmd::exec "git commit #{mode} #{msg}"
    rescue => e
      onFail.call if block_given?
      raise e
    end
  end

  private
    def exist?
      Cmd::branchExist? @name
    end
    def make(target)
      Cmd::execQuiet "git branch \"#{@name}\" \"#{target}\""
      puts "Maked branch #{@name} (was #{Cmd::revision @name})"
    end
end

# detachedブランチ
class DetachBranch
  include BranchCommon

  def checkout
    Cmd::execQuiet "git checkout --detach \"#{@name}\""
  end
  def delete(deletedBranch='', dummy=false)
    if deletedBranch != ''
      Cmd::execQuiet "git checkout \"#{deletedBranch}\""
    end
    revision = Cmd::revision @name
    Cmd::execQuiet "git update-ref -d refs/#{@name}"
    puts "Deleted detached branch #{@name} (was #{revision})"
  end
  def rebase(upstream)
    puts "[#{@name}]: git rebase \"#{upstream}\""
    Cmd::execForRebase @name, "git rebase \"#{upstream}\" \"#{@name}\" --exec \"git update-ref refs/#{@name} HEAD\""
  end
  def rebaseOnto(newbase, upstream)
    puts "[#{@name}]: git rebase --onto \"#{newbase}\" \"#{upstream}\" <SELF>"
    Cmd::execForRebase @name, "git rebase --onto \"#{newbase}\" \"#{upstream}\" \"#{@name}\" --exec \"git update-ref refs/#{@name} HEAD\""
  end
  def reset(target='')
    if target != ''
      checkout
      puts "[#{@name}]: git reset \"#{target}\""
      Cmd::exec "git reset \"#{target}\""
      Cmd::execQuiet "git update-ref refs/#{@name} HEAD"
    else
      puts "[#{@name}]: git reset"
      Cmd::exec 'git reset'
    end
  end
  def commit(mode=CommitMode::ALL, _msg='', &onFail)
    msg = (_msg != '') ? "-m \"#{_msg}\"" : ''
    begin
      checkout
      puts "[#{@name}]: git commit #{mode} ..."
      Cmd::exec "git commit #{mode} #{msg}"
      Cmd::execQuiet "git update-ref refs/#{@name} HEAD"
    rescue => e
      onFail.call if block_given?
      raise e
    end
  end

  private
    def exist?
      Cmd::branchRefExist? @name
    end
    def make(target)
      Cmd::execQuiet "git update-ref refs/#{@name} \"#{target}\""
      puts "Maked detached branch #{@name} (was #{Cmd::revision @name})"
    end
end
