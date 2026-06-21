module Storage
  class BlobMigrator
    def initialize(destination:, name:)
      @destination = destination
      @name = name.to_s
    end

    def call
      ActiveStorage::Blob.where.not(service_name: @name).find_each.sum do |blob|
        migrate(blob)
      end
    end

    private

    def migrate(blob)
      copy(blob) unless @destination.exist?(blob.key)
      blob.update_column(:service_name, @name)
      1
    end

    def copy(blob)
      blob.open do |file|
        @destination.upload(blob.key, file, checksum: blob.checksum, content_type: blob.content_type)
      end
    end
  end
end
