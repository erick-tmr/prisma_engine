module Admin
  class Page
    PER = 30
    WINDOW_LIMIT = 7

    attr_reader :total, :number

    def initialize(relation, page_param, per: PER)
      @relation = relation
      @per = per
      @total = relation.except(:order, :select).count(:all)
      @number = clamp(page_param.to_i)
    end

    def rows
      @rows ||= @relation.limit(@per).offset((number - 1) * @per)
    end

    def last
      @last ||= [ (total / @per.to_f).ceil, 1 ].max
    end

    def from
      (number - 1) * @per + 1
    end

    def to
      [ total, number * @per ].min
    end

    def empty?
      total.zero?
    end

    def single?
      last == 1
    end

    def window
      self.class.window(number, last)
    end

    def self.window(current, last)
      return (1..last).to_a if last <= WINDOW_LIMIT

      with_gaps(numbers_around(current, last))
    end

    def self.numbers_around(current, last)
      wanted = [ 1, last, current, current - 1, current + 1 ]
      wanted += [ 2, 3, 4 ] if current <= 3
      wanted += [ last - 3, last - 2, last - 1 ] if current >= last - 2
      wanted.uniq.select { |page| page >= 1 && page <= last }.sort
    end
    private_class_method :numbers_around

    def self.with_gaps(pages)
      pages.each_with_object([]) do |page, out|
        out << :gap if out.any? && page - out.last > 1
        out << page
      end
    end
    private_class_method :with_gaps

    private

    def clamp(value)
      value.clamp(1, last)
    end
  end
end
