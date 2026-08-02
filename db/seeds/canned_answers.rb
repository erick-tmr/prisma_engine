# Canned replies for the backoffice answer composer: idempotent, keyed on the label.
# These are the six shortcuts the team starts with; operators edit them from the
# "Respostas prontas" manager and the changes stick for everyone.

shortcuts = [
  [ "Compatibilidade GBA",
    "Funciona normalmente no Game Boy Advance e no GBA SP. No Game Boy original e no Pocket roda apenas se for cartucho monocromático, este é exclusivo de Game Boy Color." ],
  [ "Save em FRAM",
    "O save é gravado em memória FRAM, então o progresso não depende da bateria para se manter. A bateria alimenta só o relógio interno, quando o jogo tem um." ],
  [ "Prazo de produção",
    "Cada cartucho é montado e testado sob demanda. A produção leva de 3 a 5 dias úteis depois da confirmação do pagamento, e o prazo dos Correios começa a contar a partir da postagem." ],
  [ "Garantia",
    "Todos os cartuchos têm 90 dias de garantia contra defeito de fabricação. Se der qualquer problema a gente troca ou devolve o valor, é só chamar no WhatsApp com o número do pedido." ],
  [ "Sem previsão",
    "Ainda não temos previsão para esta versão. Cadastre seu e-mail no aviso de reposição da página do produto que você é avisado assim que entrar na fila de produção." ],
  [ "Frete e rastreio",
    "Enviamos para todo o Brasil por PAC, SEDEX e Mini Envios. O código de rastreio é enviado por e-mail no mesmo dia da postagem." ]
]

created = shortcuts.count do |label, body|
  CannedAnswer.find_or_create_by!(label: label) { |shortcut| shortcut.body = body }.previously_new_record?
end

puts "Respostas prontas: #{created} nova(s), #{CannedAnswer.count} no total."
