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
    Cmd::execQuiet "git branch #{opt} \"#{@name}\""
  end
  def rebase(upstream)
    Cmd::exec "git rebase \"#{upstream}\" \"#{@name}\""
  end
  def rebaseOnto(newbase, upstream)
    Cmd::exec "git rebase --onto \"#{newbase}\" \"#{upstream}\" \"#{@name}\""
  end
  def reset(target='')
    if target != ''
      checkout
      Cmd::exec "git reset \"#{target}\""
    else
      Cmd::exec 'git reset'
    end
  end
  def commit(mode=CommitMode::ALL, _msg='', &onFail)
    msg = (_msg != '') ? "-m \"#{_msg}\"" : ''
    begin
      checkout
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
      Cmd::exec "git branch \"#{@name}\" \"#{target}\""
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
    Cmd::execQuiet "git update-ref -d refs/#{@name}"
  end
  def rebase(upstream)
    Cmd::exec "git rebase \"#{upstream}\" \"#{@name}\" --exec \"git update-ref refs/#{@name} HEAD\""
  end
  def rebaseOnto(newbase, upstream)
    Cmd::exec "git rebase --onto \"#{newbase}\" \"#{upstream}\" \"#{@name}\" --exec \"git update-ref refs/#{@name} HEAD\""
  end
  def reset(target='')
    if target != ''
      checkout
      Cmd::exec "git reset \"#{target}\""
      Cmd::exec "git update-ref refs/#{@name} HEAD"
    else
      Cmd::exec 'git reset'
    end
  end
  def commit(mode=CommitMode::ALL, _msg='', &onFail)
    msg = (_msg != '') ? "-m \"#{_msg}\"" : ''
    begin
      checkout
      Cmd::exec "git commit #{mode} #{msg}"
      Cmd::exec "git update-ref refs/#{@name} HEAD"
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
    end
end
