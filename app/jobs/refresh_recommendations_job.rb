class RefreshRecommendationsJob < ApplicationJob
  def perform
    Recommendations::Refresh.call_all
  end
end
