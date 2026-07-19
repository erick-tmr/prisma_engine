require "application_system_test_case"

class PerguntasFrequentesTest < ApplicationSystemTestCase
  test "renders the FAQ and toggles answers independently" do
    visit perguntas_frequentes_path

    assert_title "Perguntas frequentes — Prisma Games"
    assert_selector ".faq-hero h1", text: "Perguntas frequentes"
    assert_text "O que é a Prisma Games?"
    assert_selector "[data-rail-link]", count: 4
    assert_selector "[data-faq-item]", count: 5

    assert_selector "[data-faq-item].is-open", count: 1

    toggle = all("[data-faq-toggle]").last
    toggle.click
    assert_selector "[data-faq-item].is-open", count: 2

    toggle.click
    assert_selector "[data-faq-item].is-open", count: 1
  end
end
