Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  root "pages#home"

  get  "/produtos",          to: "products#index"
  post "/produtos",          to: "products#index"
  get  "/produtos/:slug",    to: "categories#show", as: :category
  get  "/produto/:slug/:id", to: "products#show",
       constraints: { id: /\d+-0/ }, as: :product

  get  "/carrinho",          to: "cart#show"
  post "/carrinho/items",    to: "cart#create", as: :cart_items

  get  "/identificacao",     to: "identification#show", as: :identification
  post "/identificacao",     to: "identification#create"

  get  "/pagina/:slug",      to: "pages#show", as: :page,
       constraints: { slug: /perguntas-frequentes|recomendacao-de-jogos|reviews|direitos/ }
end
