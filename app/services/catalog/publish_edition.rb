module Catalog
  module PublishEdition
    module_function

    def call(edition)
      product_ids = edition.product_ids
      GameOfTheMonth.transaction do
        edition.products.update_all(published: true, updated_at: Time.current)
        edition.update!(published_at: Time.current, publish_job_id: nil)
      end
      SyncGameOfTheMonthCatalogJob.perform_later(product_ids)
    end
  end
end
