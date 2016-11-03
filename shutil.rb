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

# NOTE : gitconfig上からは`#{cmd}`と変数を渡せないので(#がコメント開始と被る)
#        rubyソースを経由する
def exec(cmd)
  `#{cmd}`
end
