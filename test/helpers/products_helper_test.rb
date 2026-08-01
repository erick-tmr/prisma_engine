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

  test "keeps headings as headings, demoted one level below the section title" do
    html = product_description("<h2>Qualidade</h2><h3>Save em FRAM</h3><h4>Detalhe</h4>")

    assert_equal "<h3>Qualidade</h3><h4>Save em FRAM</h4><h5>Detalhe</h5>", html
  end

  test "demotes each heading only once" do
    html = product_description("<h2>Um</h2><h3>Dois</h3>")

    assert_not_includes html, "<h5>Um</h5>"
    assert_includes html, "<h3>Um</h3>"
    assert_includes html, "<h4>Dois</h4>"
  end

  test "keeps inline markup inside headings" do
    html = product_description("<h2>🎮 <strong>Reprodução</strong> <em>Prisma</em></h2>")

    assert_equal "<h3>🎮 <strong>Reprodução</strong> <em>Prisma</em></h3>", html
  end

  test "strips headings above the supported range" do
    html = product_description("<h1>Topo</h1><p>corpo</p>")

    assert_not_includes html, "<h1"
    assert_not_includes html, "<h2"
    assert_includes html, "Topo"
  end
end
