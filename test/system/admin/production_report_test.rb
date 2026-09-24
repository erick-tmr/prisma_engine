require "application_system_test_case"

class AdminProductionReportTest < ApplicationSystemTestCase
  test "an operator sends the waiting orders to production and prints them with the ones already there" do
    waiting = orders(:confirmed_paid)
    producing = orders(:producing)
    login_as_user(users(:admin))

    visit admin_root_path
    find("#gen-production").click

    assert_current_path admin_production_report_path
    assert_selector ".pr-preview"
    assert_text waiting.number
    assert_text producing.number

    find("[data-pr-open]").click
    assert_selector "[data-pr-modal]"
    click_button I18n.t("admin.production_report.confirm.submit")

    assert_selector ".pr-order", count: 2
    assert_selector ".pr-check"
    assert_selector ".pr-order__number", text: waiting.number
    assert_selector ".pr-order__number", text: producing.number
    assert waiting.reload.in_production?
    assert_no_selector ".sb-link", text: "Relatórios"
  end
end
