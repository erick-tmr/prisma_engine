Rails.application.routes.draw do
  devise_for :users,
             path: "",
             path_names: {
               sign_in: "entrar",
               sign_out: "sair",
               sign_up: "cadastrar",
               password: "recuperar-senha",
               confirmation: "confirmar",
               edit: "editar"
             },
             controllers: { registrations: "users/registrations" }

  get "up" => "rails/health#show", as: :rails_health_check

  root "pages#home"

  get  "/produtos",          to: "products#index", as: :products
  post "/produtos",          to: "products#index"
  get  "/produtos/:slug",    to: "categories#show", as: :category
  get  "/produto/:slug",     to: "products#show", as: :product

  get  "/carrinho",          to: "cart#show"
  post "/carrinho/items",    to: "cart#create", as: :cart_items

  get  "/pagina/perguntas-frequentes",  to: "pages#perguntas_frequentes",  as: :perguntas_frequentes
  get  "/pagina/recomendacao-de-jogos", to: "pages#recomendacao_de_jogos", as: :recomendacao_de_jogos
  get  "/pagina/reviews",               to: "pages#reviews",               as: :reviews
  get  "/pagina/direitos",              to: "pages#direitos",              as: :direitos
end
