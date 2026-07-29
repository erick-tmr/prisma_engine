module Catalog
  module PublishScheduledEditions
    module_function

    def call
      GameOfTheMonth.due_for_publishing.each { |edition| publish(edition) }
    end

    def publish(edition)
      GameOfTheMonth.transaction do
        edition.products.update_all(published: true, updated_at: Time.current)
        edition.update!(published_at: Time.current)
      end
    end
  end
end
