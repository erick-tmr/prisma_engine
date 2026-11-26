module Admin
  module StoreThemeHelper
    PICKER_FORMAT = "%Y-%m-%dT%H:%M".freeze

    def theme_picker_value(time)
      time&.in_time_zone&.strftime(PICKER_FORMAT)
    end
  end
end
