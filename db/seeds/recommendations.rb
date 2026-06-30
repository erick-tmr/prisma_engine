[
  { url: "https://hyd.neocities.org/",       position: 0 },
  { url: "https://www.ericktakeshi.com.br/", position: 1 }
].each do |attrs|
  recommendation = Recommendation.find_or_create_by!(url: attrs[:url])
  recommendation.update!(position: attrs[:position])

  begin
    Recommendations::Refresh.call(recommendation)
  rescue LinkPreview::Api::Error => error
    warn "Recomendações: falha ao buscar #{recommendation.url}: #{error.message}"
  end
end

puts "Recomendações: #{Recommendation.count} ativa(s)"
