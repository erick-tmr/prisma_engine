module Storage
  class AssetUpload
    PRE_ANALYZED = { identified: true, analyzed: true }.freeze

    Result = Data.define(:key, :filename, :content_type, :byte_size, :checksum, :service_name, :url) do
      def console_snippet
        attrs = { key:, filename:, content_type:, byte_size:, checksum:, service_name:, metadata: PRE_ANALYZED }
        args = attrs.map { |name, value| "#{name}: #{value.inspect}" }.join(", ")
        "blob = ActiveStorage::Blob.create!(#{args})"
      end
    end

    def self.call(path, service: ActiveStorage::Blob.service)
      new(Pathname(path), service).call
    end

    def initialize(file, service)
      @file = file
      @service = service
    end

    def call
      key = ActiveStorage::Blob.generate_unique_secure_token
      @file.open("rb") { |io| @service.upload(key, io, checksum:, content_type:) }

      Result.new(key:, filename: @file.basename.to_s, content_type:, byte_size: @file.size,
                 checksum:, service_name: @service.name.to_s, url: public_url(key))
    end

    private

    def checksum
      @checksum ||= OpenSSL::Digest::MD5.file(@file).base64digest
    end

    def content_type
      @content_type ||= Marcel::MimeType.for(@file, name: @file.basename.to_s)
    end

    def public_url(key)
      @service.url(key) if @service.public?
    end
  end
end
