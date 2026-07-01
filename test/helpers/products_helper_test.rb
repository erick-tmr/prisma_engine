require "test_helper"

class ProductsHelperTest < ActionView::TestCase
  test "keeps allowed formatting and opens links in a new tab" do
    html = product_description('<p>Veja <a href="https://example.test/x">aqui</a></p><ul><li>item</li></ul>')

    assert_includes html, "<ul>"
    assert_includes html, "<li>item</li>"
    anchor = html[/<a[^>]*>/]
    assert_includes anchor, 'href="https://example.test/x"'
    assert_includes anchor, 'target="_blank"'
    assert_includes anchor, 'rel="noopener noreferrer"'
  end

  test "strips disallowed tags and attributes" do
    html = product_description(
      '<span style="color:red">x</span><script>alert(1)</script><a href="/y" onclick="evil()">y</a>'
    )

    assert_not_includes html, "<span"
    assert_not_includes html, "<script"
    assert_not_includes html, "onclick"
    assert_not_includes html, "style="
  end

  test "returns an empty string for blank input" do
    assert_equal "", product_description(nil)
    assert_equal "", product_description("")
  end
end
