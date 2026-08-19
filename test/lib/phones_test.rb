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

  test "whatsapp_url points the click-to-chat link at the number with its country code" do
    assert_equal "https://web.whatsapp.com/send?phone=5511968188483",
                 Phones.whatsapp_url("(11) 96818-8483")
  end

  test "whatsapp_url refuses a landline, which can hold no WhatsApp account" do
    assert_nil Phones.whatsapp_url("(11) 3333-4444")
  end

  test "whatsapp_url refuses a phone it cannot read as Brazilian" do
    assert_nil Phones.whatsapp_url("99942-4875")
    assert_nil Phones.whatsapp_url("")
    assert_nil Phones.whatsapp_url(nil)
  end

  test "e164 accepts a landline" do
    assert_equal "+551133334444", Phones.e164("(11) 3333-4444")
  end

  test "e164 keeps DDD 55 intact instead of reading it as the country code" do
    assert_equal "+5555999998888", Phones.e164("(55) 99999-8888")
    assert_equal "+555533334444", Phones.e164("(55) 3333-4444")
  end

  test "e164 rejects a number missing its area code rather than shipping a short one" do
    assert_nil Phones.e164("99942-4875")
  end

  test "e164 rejects the country code swallowed by a fixed-width mask" do
    assert_nil Phones.e164("(55) 21976-0285")
  end

  test "e164 rejects an area code containing a zero" do
    assert_nil Phones.e164("(01) 99999-8888")
    assert_nil Phones.e164("(10) 99999-8888")
  end

  test "e164 rejects an eleven digit number that is not a mobile" do
    assert_nil Phones.e164("(11) 83333-4444")
  end

  test "e164 rejects anything longer than a country code plus a mobile" do
    assert_nil Phones.e164("+55 (11) 98765-43210")
  end

  test "national hands back the bare digits" do
    assert_equal "11987654321", Phones.national("+55 (11) 98765-4321")
    assert_nil Phones.national("123")
  end
end
