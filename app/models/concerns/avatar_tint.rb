module AvatarTint
  COUNT = 8

  def self.index_for(name)
    hash = 0
    name.to_s.each_char { |char| hash = (hash * 31 + char.ord) & 0xffffffff }
    hash % COUNT
  end
end
