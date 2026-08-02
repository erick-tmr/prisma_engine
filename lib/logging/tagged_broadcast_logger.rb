module Logging
  class TaggedBroadcastLogger < ActiveSupport::BroadcastLogger
    def tagged(*tags, &block)
      return super unless block

      taggable = broadcasts.select { |logger| logger.respond_to?(:tagged) }
      taggable.reverse.inject(block) { |inner, logger| -> { logger.tagged(*tags) { inner.call } } }.call
    end
  end
end
