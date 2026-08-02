require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "points the canonical url at the configured host, not the one that was requested" do
    request.host = "www.prismagames.com.br"
    request.path = "/produtos/game-boy-color"

    with_canonical_host("prismagames.com.br") do
      assert_equal "http://prismagames.com.br/produtos/game-boy-color", canonical_url
    end
  end

  test "drops the query string so tracking params do not split the canonical url" do
    request.host = "www.prismagames.com.br"
    request.path = "/produtos"

    with_canonical_host("prismagames.com.br") do
      assert_equal "http://prismagames.com.br/produtos", canonical_url
    end
  end

  test "falls back to the requested host when no canonical host is configured" do
    request.host = "localhost"
    request.path = "/"

    with_canonical_host(nil) do
      assert_equal "http://localhost/", canonical_url
    end
  end

  test "reads a distance in the past as pt-BR" do
    assert_equal "há 2 dias", relative_time_ago(2.days.ago)
    assert_equal "há 1 dia", relative_time_ago(1.day.ago)
  end

  test "falls back to the coarse buckets for very recent and very old timestamps" do
    assert_equal "há menos de um minuto", relative_time_ago(10.seconds.ago)
    assert_equal "há 3 meses", relative_time_ago(92.days.ago)
  end
end
