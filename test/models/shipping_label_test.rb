require "test_helper"

class ShippingLabelTest < ActiveSupport::TestCase
  setup do
    @label = shipments(:producing).create_shipping_label!
  end

  test "starts pending" do
    assert @label.pending?
  end

  test "mark_prepost_created! advances the state and clears any error" do
    @label.record_error!("boom")
    @label.mark_prepost_created!

    assert @label.prepost_created?
    assert_nil @label.error
    assert_nil @label.errored_at
  end

  test "mark_prepost_confirmed! advances the state and clears any error" do
    @label.record_error!("boom")
    @label.mark_prepost_confirmed!

    assert @label.prepost_confirmed?
    assert_nil @label.error
    assert_nil @label.errored_at
  end

  test "mark_requested! stores the recibo id" do
    @label.mark_requested!("R-1")

    assert @label.requested?
    assert_equal "R-1", @label.recibo_id
  end

  test "mark_ready! stores the filename and base64 PDF" do
    @label.mark_ready!(filename: "label.pdf", pdf: "JVBERi0=")

    assert @label.ready?
    assert_equal "label.pdf", @label.filename
    assert_equal "JVBERi0=", @label.pdf_base64
  end

  test "record_error! captures the message and a timestamp without advancing" do
    @label.record_error!("correios returned 400")

    assert @label.pending?
    assert_equal "correios returned 400", @label.error
    assert_not_nil @label.errored_at
  end

  test "pdf_bytes decodes the stored base64; nil when no PDF yet" do
    assert_nil @label.pdf_bytes

    @label.mark_ready!(filename: "label.pdf", pdf: Base64.strict_encode64("%PDF-1.4"))
    assert_equal "%PDF-1.4", @label.pdf_bytes
  end

  test "reset_for_relabel! rewinds to prepost_confirmed, clears the recibo and counts the attempt" do
    @label.mark_requested!("R-9")
    @label.record_error!("boom")
    @label.reset_for_relabel!

    assert @label.prepost_confirmed?
    assert_nil @label.recibo_id
    assert_nil @label.error
    assert_nil @label.errored_at
    assert_equal 1, @label.relabel_attempts
  end
end
