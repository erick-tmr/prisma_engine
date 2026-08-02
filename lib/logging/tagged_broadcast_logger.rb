module Logging
  class TaggedBroadcastLogger < ActiveSupport::BroadcastLogger
    def tagged(*tags, &block)
      return super unless block

      taggable = broadcasts.grep(ActiveSupport::TaggedLogging)
      taggable.reverse.inject(block) { |inner, logger| -> { logger.tagged(*tags) { inner.call } } }.call
    end
  end
end
