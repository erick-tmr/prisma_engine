module HasMoney
  def self.format(cents)
    "R$ %0.2f" % (cents.to_i / 100.0)
  end
end
