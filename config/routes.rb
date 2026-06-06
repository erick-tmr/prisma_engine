Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  root "pages#home"

  get  "/produtos",          to: "products#index", as: :products
  post "/produtos",          to: "products#index"
  get  "/produtos/:slug",    to: "categories#show", as: :category
  get  "/produto/:slug",     to: "products#show", as: :product

  get  "/carrinho",          to: "cart#show"
  post "/carrinho/items",    to: "cart#create", as: :cart_items

  get  "/identificacao",     to: "identification#show", as: :identification
  post "/identificacao",     to: "identification#create"

  get  "/pagina/perguntas-frequentes",  to: "pages#perguntas_frequentes",  as: :perguntas_frequentes
  get  "/pagina/recomendacao-de-jogos", to: "pages#recomendacao_de_jogos", as: :recomendacao_de_jogos
  get  "/pagina/reviews",               to: "pages#reviews",               as: :reviews
  get  "/pagina/direitos",              to: "pages#direitos",              as: :direitos
end
