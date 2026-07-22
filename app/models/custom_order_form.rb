class CustomOrderForm < ApplicationRecord
  DEFAULTS = {
    title:             "Detalhes do seu pedido",
    subtitle:          "Produto sob encomenda. Diga qual jogo você quer que a gente produza.",
    game_label:        "Nome do jogo",
    game_placeholder:  "Ex.: Pokémon Unbound (romhack)",
    game_hint:         "Digite o título exato do jogo ou romhack que você quer encomendar.",
    game_error:        "Informe o nome do jogo que você quer encomendar.",
    notes_label:       "Observações",
    notes_placeholder: "Versão ou patch específico, link de referência, região."
  }.freeze

  LIMITS = {
    title: 60, subtitle: 180,
    game_label: 40, game_placeholder: 80, game_hint: 120, game_error: 120,
    notes_label: 40, notes_placeholder: 120
  }.freeze

  belongs_to :product

  LIMITS.each { |field, limit| validates field, length: { maximum: limit } }

  def text(key)
    self[key].presence || DEFAULTS.fetch(key)
  end
end
