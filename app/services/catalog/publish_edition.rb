module Catalog
  module PublishEdition
    module_function

    def call(edition)
      GameOfTheMonth.transaction do
        edition.products.update_all(published: true, updated_at: Time.current)
        edition.update!(published_at: Time.current, publish_job_id: nil)
      end
    end
  end
end
