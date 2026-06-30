[
  { url: "https://hyd.neocities.org/",       position: 0 },
  { url: "https://www.ericktakeshi.com.br/", position: 1 }
].each do |attrs|
  recommendation = Recommendation.find_or_create_by!(url: attrs[:url])
  recommendation.update!(position: attrs[:position])
end

RefreshRecommendationsJob.perform_later

puts "Recomendações: #{Recommendation.count} ativa(s)"
