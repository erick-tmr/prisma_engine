Rails.application.routes.draw do
  if Rails.env.development?
    mount LetterOpenerWeb::Engine, at: "/cartas"
  end

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
             controllers: {
               registrations: "users/registrations",
               confirmations: "users/confirmations"
             }

  scope path: "minha-conta", module: "account", as: :account do
    root to: redirect("/minha-conta/perfil")
    get   "perfil", to: "profiles#edit",  as: :profile
    patch "perfil", to: "profiles#update"
    get   "senha",  to: "passwords#edit", as: :password
    patch "senha",  to: "passwords#update"
    resources :enderecos, controller: "addresses", as: :addresses, except: :show do
      member { patch :default }
      collection { get "cep/:cep", action: :lookup_cep, as: :lookup_cep, constraints: { cep: /[\d-]{8,9}/ } }
    end
    resources :pedidos, controller: "orders", as: :orders, only: %i[index show]
  end

  get "up" => "rails/health#show", as: :rails_health_check

  root "pages#home"

  get  "/produtos",          to: "products#index", as: :products
  post "/produtos",          to: "products#index"
  get  "/produtos/:slug",    to: "categories#show", as: :category
  get  "/produto/:slug",     to: "products#show", as: :product

  get    "/carrinho",            to: "cart#show",          as: :cart
  post   "/carrinho/items",      to: "cart_items#create",  as: :cart_items
  patch  "/carrinho/items/:id",  to: "cart_items#update",  as: :cart_item
  delete "/carrinho/items/:id",  to: "cart_items#destroy"
  post   "/carrinho/finalizar",  to: "cart#finalize",      as: :cart_finalize
  post   "/carrinho/frete",      to: "cart_quotes#create", as: :cart_quote

  get  "/checkout",          to: "checkout#show",           as: :checkout
  post "/checkout",          to: "checkout#create",         as: :checkout_create
  post "/checkout/endereco", to: "checkout#create_address", as: :checkout_address
  get  "/checkout/retorno",       to: "checkout/returns#show", as: :checkout_return
  post "/checkout/retorno/pagar", to: "checkout/returns#pay",  as: :checkout_pay
  post "/pagamentos/webhook/:token", to: "payments/webhooks#create", as: :payments_webhook

  get  "/pagina/perguntas-frequentes",  to: "pages#perguntas_frequentes",  as: :perguntas_frequentes
  get  "/pagina/recomendacao-de-jogos", to: "pages#recomendacao_de_jogos", as: :recomendacao_de_jogos
  get  "/pagina/reviews",               to: "pages#reviews",               as: :reviews
  get  "/pagina/direitos",              to: "pages#direitos",              as: :direitos
end
