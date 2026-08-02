require "test_helper"

class OpenGraphHelperTest < ActionView::TestCase
  include ApplicationHelper

  test "falls back to the site defaults when a page sets nothing" do
    assert_equal "website", og_type
    assert_equal OpenGraphHelper::SITE_NAME, og_title
    assert_equal OpenGraphHelper::SITE_DESCRIPTION, og_description
  end

  test "reuses the page title and description when no og-specific value is set" do
    content_for(:title, "Jogos | Prisma Games")
    content_for(:description, "Catálogo completo.")

    assert_equal "Jogos | Prisma Games", og_title
    assert_equal "Catálogo completo.", og_description
  end

  test "an og-specific value wins over the page title and description" do
    content_for(:title, "Pokemon Silver | Prisma Games")
    content_for(:description, "página")
    content_for(:og_title, "Pokemon Silver")
    content_for(:og_description, "compartilhado")

    assert_equal "Pokemon Silver", og_title
    assert_equal "compartilhado", og_description
  end

  test "the default share image is absolute against the canonical host" do
    request.host = "www.prismagames.com.br"

    with_canonical_host("prismagames.com.br") do
      assert_equal "http://prismagames.com.br#{OpenGraphHelper::DEFAULT_IMAGE}", og_image_url
    end
  end

  test "an image that is already absolute is left alone" do
    content_for(:og_image, "https://cdn.example.com/photo.jpg")

    with_canonical_host("prismagames.com.br") do
      assert_equal "https://cdn.example.com/photo.jpg", og_image_url
    end
  end

  test "a relative page image is made absolute" do
    request.host = "prismagames.com.br"
    content_for(:og_image, "/rails/active_storage/blobs/abc/photo.jpg")

    with_canonical_host("prismagames.com.br") do
      assert_equal "http://prismagames.com.br/rails/active_storage/blobs/abc/photo.jpg", og_image_url
    end
  end

  test "meta_description_from strips markup, collapses whitespace and truncates" do
    assert_equal "Cartucho reproduzido com bateria nova.",
                 meta_description_from("<p>Cartucho <b>reproduzido</b>\n  com bateria nova.</p>")
    assert_nil meta_description_from("")
    assert_nil meta_description_from(nil)
  end

  test "meta_description_from keeps a space where a block tag separated two words" do
    assert_equal "usa FRAM Os saves duram",
                 meta_description_from("<p>usa FRAM</p><p>Os saves duram</p>")
  end

  test "meta_description_from keeps the result within the limit" do
    long = "palavra " * 200

    assert_operator meta_description_from(long).length, :<=, OpenGraphHelper::DESCRIPTION_LIMIT
  end
end
