require "test_helper"

class PhonesTest < ActiveSupport::TestCase
  test "e164 strips formatting and prefixes the Brazil country code" do
    assert_equal "+5511987654321", Phones.e164("(11) 98765-4321")
  end

  test "e164 keeps a number that already carries the +55 country code" do
    assert_equal "+5511932458443", Phones.e164("+55 (11) 93245-8443")
  end

  test "e164 returns nil for a blank phone" do
    assert_nil Phones.e164("")
    assert_nil Phones.e164(nil)
  end
end
