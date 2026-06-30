[
  { url: "https://hyd.neocities.org/",       position: 0 },
  { url: "https://www.ericktakeshi.com.br/", position: 1 }
].each do |attrs|
  recommendation = Recommendation.find_or_initialize_by(url: attrs[:url])
  next unless recommendation.new_record?

  recommendation.position = attrs[:position]
  recommendation.save!

  begin
    Recommendations::Refresh.call(recommendation)
  rescue LinkPreview::Api::Error => error
    warn "Recomendações: falha ao buscar #{recommendation.url}: #{error.message}"
  end
end

puts "Recomendações: #{Recommendation.count} ativa(s)"
