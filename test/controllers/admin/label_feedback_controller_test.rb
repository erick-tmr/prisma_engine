require "test_helper"

module Admin
  class LabelFeedbackControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers

    test "non-admins are sent to the backoffice login" do
      get admin_label_feedback_path
      assert_redirected_to admin_login_path
    end

    test "renders one Correios cell per listed order, without the layout" do
      sign_in users(:admin)
      orders(:producing).shipment.create_shipping_label!(state: :prepost_created)

      get admin_label_feedback_path

      assert_response :success
      assert_no_match(/<html/, response.body)
      assert_select %(div[data-part="correios-#{orders(:producing).number}"][data-cor-state="running"])
      assert_select %(div[data-part="correios-#{orders(:labeled).number}"][data-cor-state="done"])
    end

    test "an emitted label reads as its tracking code, not a second status label" do
      sign_in users(:admin)
      orders(:labeled).shipment.update!(tracking_code: "PG515656027BR")

      get admin_label_feedback_path

      assert_select %(div[data-part="correios-#{orders(:labeled).number}"]) do
        assert_select ".proc-ok .proc-code", "PG515656027BR"
        assert_select ".proc-sub", false
      end
    end

    test "an emitted label with no tracking code yet still says what happened" do
      sign_in users(:admin)

      get admin_label_feedback_path

      assert_select %(div[data-part="correios-#{orders(:labeled).number}"] .proc-ok),
                    text: /#{I18n.t("admin.dashboard.orders.correios.done")}/
    end

    test "carries the order status alongside the cell so the pill cannot go stale" do
      sign_in users(:admin)

      get admin_label_feedback_path

      assert_select %(div[data-part="status-#{orders(:labeled).number}"][data-row-status="label_issued"]) do
        assert_select ".pill.st-label_issued"
      end
    end

    test "honours the list filters so it only reports the rows on screen" do
      sign_in users(:admin)

      get admin_label_feedback_path, params: { status: [ "in_production" ] }

      assert_select %(div[data-part="correios-#{orders(:producing).number}"])
      assert_select %(div[data-part="correios-#{orders(:labeled).number}"]), false
    end

    test "never returns the parts that would clobber the filters or the pager" do
      sign_in users(:admin)

      get admin_label_feedback_path

      %w[table count status period].each do |part|
        assert_select %(*[data-part="#{part}"]), false, "the poll must not replace the #{part} part"
      end
    end

    test "the progress strip stays hidden until a batch is passed" do
      sign_in users(:admin)

      get admin_label_feedback_path

      assert_select %(div[data-part="procbar"][hidden])
    end

    test "reports live batch progress for the submitted order numbers" do
      sign_in users(:admin)
      orders(:producing).shipment.create_shipping_label!(state: :requesting)

      get admin_label_feedback_path, params: { lote: [ orders(:producing).number, orders(:labeled).number ] }

      assert_select %(div[data-part="procbar"][data-total="2"][data-settled="1"][data-in-flight="1"]) do
        assert_select ".pb-t", I18n.t("admin.dashboard.orders.batch.title")
        assert_select ".pb-s", /#{orders(:producing).number}/
      end
    end

    test "shows the finished strip once every label in the batch has settled" do
      sign_in users(:admin)
      orders(:producing).shipment.create_shipping_label!(state: :prepost_confirmed).record_error!("PPN-320")

      get admin_label_feedback_path, params: { lote: [ orders(:producing).number, orders(:labeled).number ] }

      assert_select %(div.procbar.is-done.has-fail[data-failed="1"]) do
        assert_select ".pb-t", I18n.t("admin.dashboard.orders.batch.done_title")
      end
    end

    test "counts the failures alongside the progress while the batch is still running" do
      sign_in users(:admin)
      orders(:producing).shipment.create_shipping_label!(state: :requesting)
      orders(:confirmed_paid).shipment.create_shipping_label!(state: :prepost_confirmed).record_error!("PPN-320")

      get admin_label_feedback_path,
          params: { lote: [ orders(:producing).number, orders(:confirmed_paid).number ] }

      assert_select %(div.procbar.has-fail[data-in-flight="1"][data-failed="1"]) do
        assert_select ".pb-s", /1 com falha/
      end
    end

    test "a batch whose labels have not been created yet never reads as concluded" do
      sign_in users(:admin)

      get admin_label_feedback_path, params: { lote: [ orders(:producing).number ] }

      assert_select %(div.procbar[data-in-flight="1"][data-percent="0"]) do
        assert_select ".pb-t", I18n.t("admin.dashboard.orders.batch.title")
        assert_select ".pb-count", "0%"
      end
      assert_select "div.procbar.is-done", false
    end

    test "a batch that finished clean says so without mentioning failures" do
      sign_in users(:admin)

      get admin_label_feedback_path, params: { lote: [ orders(:labeled).number ] }

      assert_select %(div.procbar.is-done[data-failed="0"]) do
        assert_select ".pb-s", /1 de 1 etiquetas emitidas/
      end
      assert_select "div.procbar.has-fail", false
    end

    test "falls back to a waiting note when no order in the batch is mid-request" do
      sign_in users(:admin)
      orders(:producing).shipment.create_shipping_label!(state: :pending)

      get admin_label_feedback_path, params: { lote: [ orders(:producing).number ] }

      assert_select ".pb-s", /#{I18n.t("admin.dashboard.orders.batch.waiting")}/
    end

    test "caps how many order numbers one poll can ask about" do
      sign_in users(:admin)
      numbers = Array.new(Admin::LabelFeedbackController::BATCH_LIMIT + 5) { |i| "PG-2026060#{i}" }

      get admin_label_feedback_path, params: { lote: numbers + [ orders(:labeled).number ] }

      assert_select %(div[data-part="procbar"][data-total="0"])
    end

    test "non-admins cannot read one order's label feedback" do
      get admin_order_label_feedback_path(orders(:producing).number)
      assert_redirected_to admin_login_path
    end

    test "renders the detail head, status card and history for one order" do
      sign_in users(:admin)
      orders(:producing).shipment.create_shipping_label!(state: :requested)

      get admin_order_label_feedback_path(orders(:producing).number)

      assert_response :success
      assert_select %(div[data-part="head"][data-cor-state="running"]) do
        assert_select ".headpill-proc", I18n.t("admin.orders.detail.label.chip_running")
      end
      assert_select %(div[data-part="status-card"] .act-proc)
      assert_select %(div[data-part="history"])
    end

    test "404s for an order that does not exist" do
      sign_in users(:admin)

      get admin_order_label_feedback_path("PG-20260101999")

      assert_response :not_found
    end
  end
end
