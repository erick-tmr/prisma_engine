require "application_system_test_case"

class AdminProductionReportTest < ApplicationSystemTestCase
  test "an operator sends a batch to production, prints it, and reprints it from history" do
    order = orders(:confirmed_paid) # payment_confirmed, has a game item → eligible
    login_as_user(users(:admin))

    visit admin_root_path
    find("#gen-production").click

    assert_current_path admin_production_report_path
    assert_selector ".pr-preview"
    assert_text order.number

    find("[data-pr-open]").click
    assert_selector "[data-pr-modal]" # JS removed [hidden] → now visible
    click_button I18n.t("admin.production_report.confirm.submit")

    assert_selector ".pr-order"
    assert_selector ".pr-check"
    assert order.reload.in_production?

    # The batch is archived: it shows in the Relatórios tab and reprints.
    visit admin_root_path
    find('.sb-link[data-view="reports"]').click
    within "#reports-body" do
      assert_selector "tr", count: 1
      find("a.cell-link").click
    end

    assert_selector ".pr-order"
    assert_text order.number
  end
end
