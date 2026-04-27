require "test_helper"

class ApplicationTest < ActiveSupport::TestCase
  test "Rails environment boots" do
    assert Rails.application.initialized?
  end
end
