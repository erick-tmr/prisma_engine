require "active_storage/service/s3_service"

class ActiveStorage::Service::R2Service < ActiveStorage::Service::S3Service
  def initialize(public_host:, **options)
    @public_host = public_host
    super(**options)
    @upload_options.delete(:acl)
  end

  private

  def public_url(key, **)
    "#{@public_host}/#{key}"
  end
end
