#!ruby

# 外部コマンドステータスの拡張メソッド
# usage) $?.ok?
class NilClass
  def ok?
    true
  end
end
class Process::Status
  def ok?
    !!("#{self}" =~ /exit 0$/)
  end
end


MAX=4
def tryCheckoutB(i, branch, hash, title)
  stash="stash-commit/#{branch}@#{i}"

  Kernel.system("git checkout -b \"#{stash}\"")
  if $?.ok? then
    Kernel.system('git add .')
    Kernel.system("git commit -m \"WIP on #{branch}: #{hash} #{title}\"")
    Kernel.system("git checkout #{branch}")
    return true
  end
  return false
end

def f
  hash=`git revision`
  branch=`git branch-name`
  title=`git title`

  if `git changes-count` == '0' then
    puts 'not need'
    return
  end
  
  MAX.times do |i|
    okng = tryCheckoutB i, branch, hash, title
    if okng then
      puts 'success'
      return true
    end
  end

  puts '* failed: stash-commit branch is too many'
  return false
end

f
