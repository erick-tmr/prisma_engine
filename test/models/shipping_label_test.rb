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

  test "mark_requested! stores the recibo id, last write wins" do
    @label.mark_requested!("R-1")
    assert @label.requested?
    assert_equal "R-1", @label.recibo_id

    @label.mark_requested!("R-2")
    assert_equal "R-2", @label.recibo_id
  end

  test "claim_requesting! moves a confirmed label to requesting and wins only once" do
    @label.mark_prepost_confirmed!

    assert @label.claim_requesting!
    assert @label.requesting?
    assert_not_nil @label.requesting_at
    assert_not @label.claim_requesting!
  end

  test "claim_requesting! loses when the label is not awaiting a request" do
    assert_not @label.claim_requesting!
    assert @label.pending?
  end

  test "unclaim_requesting! rolls a requesting label back to prepost_confirmed" do
    @label.mark_prepost_confirmed!
    @label.claim_requesting!

    @label.unclaim_requesting!
    assert @label.prepost_confirmed?
  end

  test "store_label! parks the label with its PDF, short of ready" do
    @label.store_label!(filename: "label.pdf", pdf: "JVBERi0=")

    assert @label.label_downloaded?
    assert_equal "label.pdf", @label.filename
    assert_equal "JVBERi0=", @label.pdf_base64
    assert_nil @label.dce_base64
  end

  test "store_dce! adds the declaração and only then is the label ready" do
    @label.store_label!(filename: "label.pdf", pdf: "JVBERi0=")
    @label.store_dce!(filename: "declaracao.pdf", pdf: "RENF")

    assert @label.ready?
    assert_equal "declaracao.pdf", @label.dce_filename
    assert_equal "RENF", @label.dce_base64
    assert_equal "JVBERi0=", @label.pdf_base64
  end

  test "both writers clear a recorded error" do
    @label.record_error!("boom")
    @label.store_label!(filename: "l.pdf", pdf: "x")
    assert_nil @label.error

    @label.record_error!("boom again")
    @label.store_dce!(filename: "d.pdf", pdf: "x")
    assert_nil @label.error
    assert_nil @label.errored_at
  end

  test "record_error! captures the message and a timestamp without advancing" do
    @label.record_error!("correios returned 400")

    assert @label.pending?
    assert_equal "correios returned 400", @label.error
    assert_not_nil @label.errored_at
  end

  test "pdf_bytes decodes the stored base64; nil when no PDF yet" do
    assert_nil @label.pdf_bytes

    @label.store_label!(filename: "label.pdf", pdf: Base64.strict_encode64("%PDF-1.4"))
    assert_equal "%PDF-1.4", @label.pdf_bytes
  end

  test "dce_bytes decodes the stored declaração; nil until one is stored" do
    assert_nil @label.dce_bytes

    @label.store_dce!(filename: "declaracao.pdf", pdf: Base64.strict_encode64("%PDF-1.4 dace"))
    assert_equal "%PDF-1.4 dace", @label.dce_bytes
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

  test "ready_for_retry! clears the error and hands back a full set of relabel attempts" do
    @label.reset_for_relabel!
    @label.record_error!("PPN-295 rótulo não gerado")

    @label.ready_for_retry!

    assert_nil @label.error
    assert_nil @label.errored_at
    assert_equal 0, @label.relabel_attempts
    assert @label.prepost_confirmed?
  end
end
