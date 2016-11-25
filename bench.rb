#$:.unshift File.dirname(__FILE__)

require 'benchmark'
require 'command.rb'

N = 20

puts ":#{Cmd::branchName}:"
puts ":#{Cmd::revision}:"

Benchmark.bm 20 do |r|
  r.report 'branchName' do
    for i in 1..N-1
      Cmd::branchName
    end
  end
  r.report 'revision' do
    for i in 1..N-1
      Cmd::revision
    end
  end
end
