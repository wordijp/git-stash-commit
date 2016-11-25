$:.unshift File.dirname(__FILE__)

require 'benchmark'
require 'command.rb'

N = 20

puts ":#{Cmd::branchName}:"
puts ":#{Cmd::revision}:"
puts ":#{Cmd::branchExist? 'develop'}:"
puts ":#{Cmd::branchRefExist? 'develop'}:"
puts ":#{Cmd::getTmp}:"
puts ":#{Cmd::getPatchRemain}:"
puts ":#{Cmd::getBackup}:"
puts ":#{Cmd::changesCount}:"
puts ":#{Cmd::parentChildBranch? 'HEAD', 'HEAD~'}:"
puts ":#{Cmd::sameBranch? 'HEAD', 'HEAD'}:"
puts ":#{Cmd::mergeBaseHash 'develop', 'master'}:"

def registBench(r, title, &cb)
  r.report title do
    for i in 1..N-1
      cb.call
    end
  end
end

Benchmark.bm 20 do |r|
  # 目安: これが限界一番軽い
  registBench(r, 'tune limit'       ){Cmd::tuneLimit}
  #
  registBench(r, 'branchName'       ){Cmd::branchName}
  registBench(r, 'revision'         ){Cmd::revision}
  registBench(r, 'branchExist'      ){Cmd::branchExist? 'develop'}
  registBench(r, 'branchRefExist'   ){Cmd::branchRefExist? 'develop'}
  registBench(r, 'getTmp'           ){Cmd::getTmp}
  registBench(r, 'getPatchRemain'   ){Cmd::getPatchRemain}
  registBench(r, 'getBackup'        ){Cmd::getBackup}
  registBench(r, 'changesCount'     ){Cmd::changesCount}
  registBench(r, 'parentChildBranch'){Cmd::parentChildBranch? 'HEAD', 'HEAD~'}
  registBench(r, 'sameBranch'       ){Cmd::sameBranch? 'HEAD', 'HEAD'}
  registBench(r, 'mergeBaseHash'    ){Cmd::mergeBaseHash 'develop', 'master'}
end
