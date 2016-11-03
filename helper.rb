#!ruby

# NOTE : gitconfig上からは`#{cmd}`と変数を渡せないので(#がコメント開始と被る)
#        rubyソースを経由する
def exec(cmd)
  `#{cmd}`
end
