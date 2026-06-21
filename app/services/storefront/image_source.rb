module Storefront
  module ImageSource
    module_function

    def call(attachment)
      blob = attachment.blob
      if blob.service.public?
        blob.url
      else
        Rails.application.routes.url_helpers.rails_blob_path(attachment, only_path: true)
      end
    end
  end
end
