module Shipping
  class DeliveryWindow
    SPAN_BUSINESS_DAYS = 2

    def self.for(shipment)
      business_days = shipment.delivery_business_days
      return if business_days.blank?

      anchor = (shipment.posted_at || Time.current).to_date
      opens_after = [ business_days - SPAN_BUSINESS_DAYS, 1 ].max
      business_days_after(anchor, opens_after)..business_days_after(anchor, business_days)
    end

    def self.business_days_after(date, count)
      count.times.reduce(date) { |day, _| next_business_day(day) }
    end

    def self.next_business_day(date)
      day = date.next_day
      day = day.next_day while day.saturday? || day.sunday?
      day
    end

    private_class_method :business_days_after, :next_business_day
  end
end
