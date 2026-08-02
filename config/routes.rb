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
               confirmations: "users/confirmations",
               passwords: "users/passwords",
               unlocks: "users/unlocks"
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
    resources :pedidos, controller: "orders", as: :orders, only: %i[index show] do
      member { post :cancelar, action: :cancel }
    end
  end

  scope path: "admin", module: "admin", as: :admin do
    root to: "orders#index"
    get    "clientes",     to: "clients#index", as: :clients
    get    "clientes/:id", to: "clients#show",  as: :client, constraints: { id: /\d+/ }
    delete "clientes/:client_id/strikes/:id", to: "client_strikes#destroy", as: :client_strike,
           constraints: { client_id: /\d+/, id: /\d+/ }
    get    "relatorios", to: "reports#index", as: :reports
    resources :produtos, controller: "products", as: :products,
              only: %i[index new create edit update],
              path_names: { new: "novo", edit: "editar" }
    get    "perguntas",      to: "questions#index", as: :questions
    post   "perguntas/lote", to: "question_bulk_actions#create", as: :question_bulk_actions
    patch  "perguntas/:id",  to: "questions#update", as: :question, constraints: { id: /\d+/ }
    resources :respostas_prontas, controller: "canned_answers", as: :canned_answers,
              only: %i[create update destroy]
    get    "entrar", to: "sessions#new",     as: :login
    post   "entrar", to: "sessions#create",  as: :session
    delete "sair",   to: "sessions#destroy", as: :logout
    get    "relatorio-producao", to: "production_reports#new",    as: :production_report
    post   "relatorio-producao", to: "production_reports#create"
    get    "relatorio-producao/:id", to: "production_reports#show", as: :production_report_batch, constraints: { id: /\d+/ }
    post   "etiquetas",         to: "labels#create_batch", as: :labels
    post   "etiquetas/:number", to: "labels#create",       as: :label, constraints: { number: /PG-\d+/ }
    post   "etiquetas/impressao", to: "labels#print_sheet", as: :print_labels
    get    "pedidos/:number",           to: "orders#show",       as: :order,            constraints: { number: /PG-\d+/ }
    post   "pedidos/lote",              to: "bulk_transitions#create", as: :bulk_transitions
    post   "pedidos/:number/transicao", to: "orders#transition", as: :order_transition, constraints: { number: /PG-\d+/ }
    get    "pedidos/:number/etiqueta",  to: "orders#label",      as: :order_label,      constraints: { number: /PG-\d+/ }
  end

  get "up" => "rails/health#show", as: :rails_health_check

  root "pages#home"

  get  "/produtos",          to: "products#index", as: :products
  post "/produtos",          to: "products#index"
  get  "/produtos/:slug",    to: "categories#show", as: :category
  get  "/produto/:slug",     to: "products#show", as: :product
  post "/produto/:slug/perguntas", to: "products/questions#create", as: :product_questions

  get    "/carrinho",            to: "cart#show",          as: :cart
  post   "/carrinho/items",      to: "cart_items#create",  as: :cart_items
  patch  "/carrinho/items/:id",  to: "cart_items#update",  as: :cart_item
  delete "/carrinho/items/:id",  to: "cart_items#destroy"
  post   "/carrinho/finalizar",  to: "cart#finalize",      as: :cart_finalize
  post   "/carrinho/frete",      to: "cart_quotes#create", as: :cart_quote

  get  "/checkout",          to: "checkout#show",           as: :checkout
  post "/checkout",          to: "checkout#create",         as: :checkout_create
  post "/checkout/endereco", to: "checkout#create_address", as: :checkout_address
  post "/checkout/consolidacao", to: "checkout/merge_quotes#create", as: :checkout_merge_quote
  get  "/checkout/retorno",       to: "checkout/returns#show", as: :checkout_return
  post "/checkout/retorno/pagar", to: "checkout/returns#pay",  as: :checkout_pay
  post "/pagamentos/webhook/:token", to: "payments/webhooks#create", as: :payments_webhook

  get  "/pagina/perguntas-frequentes",  to: "pages#perguntas_frequentes",  as: :perguntas_frequentes
  get  "/pagina/direitos",              to: "pages#direitos",              as: :direitos
end
