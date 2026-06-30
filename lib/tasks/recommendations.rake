namespace :recommendations do
  desc "Re-busca título, descrição e favicon de todas as recomendações"
  task refresh: :environment do
    Recommendations::Refresh.call_all
  end
end
