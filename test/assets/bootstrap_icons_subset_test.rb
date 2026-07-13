require "test_helper"

class BootstrapIconsSubsetTest < ActiveSupport::TestCase
  VENDOR = Rails.root.join("app/assets/stylesheets/vendor")
  CSS = VENDOR.join("bootstrap-icons.css")
  MANIFEST = VENDOR.join("fonts/bootstrap-icons.subset.txt")
  SEARCH = %w[app/views app/helpers app/javascript
              app/assets/stylesheets/pages app/assets/stylesheets/components].freeze

  test "every used bi-* icon is present in the subset font" do
    real_icons = CSS.read.scan(/\.(bi-[a-z0-9-]+)::before\{content:"\\[0-9a-fA-F]+"\}/).flatten.to_set
    subset = MANIFEST.read.split.to_set

    used = SEARCH.flat_map { |dir| Dir.glob(Rails.root.join(dir, "**/*")) }
                 .select { |path| File.file?(path) }
                 .flat_map { |path| File.read(path).scan(/bi-[a-z0-9-]+/) }
                 .to_set

    missing = (used & real_icons) - subset
    assert_empty missing,
                 "Icons used in the app but missing from the Bootstrap Icons subset: " \
                 "#{missing.to_a.sort.join(', ')}. Run `bin/subset-bootstrap-icons` to regenerate."
  end
end
