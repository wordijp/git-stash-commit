#!ruby

$:.unshift File.dirname(__FILE__)
require 'helper.rb'

MAX=5
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

def f(argv)
  hash=`git revision`
  branch=`git branch-name`
  title=`git title`

  if `git changes-count` == '0' then
    puts 'not need'
    return
  end
  
  # parse argv
  argv.each do |arg|
    puts "arg:#{arg}"
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

f ARGV
