# Product Q&A demo data: idempotent. Keyed on (produto, cliente, pergunta) so re-running never
# duplicates. Reuses the customers backoffice_demo.rb creates and writes nothing when they are
# absent, which is what keeps it inert outside development. Test fixtures stay separate.

zelda = "the-legend-of-zelda-oracle-of-ages"
kirby = "kirbys-dream-land-2"

threads = [
  [ zelda, "Ana Beatriz Cardoso", 2, 1,
    "Esse cartucho funciona no Game Boy Advance SP e no Super Game Boy? Quero jogar na TV com o meu SNES.",
    "Funciona no GBA e no GBA SP normalmente. No Super Game Boy também roda, mas Oracle of Ages não tem borda nem paleta especial, a imagem sai em tons de verde padrão do SGB." ],
  [ zelda, "Bruno Tanaka", 4, 4,
    "A senha de conexão com o Oracle of Seasons funciona entre dois cartuchos de vocês?",
    "Funciona sim. As duas placas gravam save em FRAM, então a senha longa de linked game passa sem problema entre os dois cartuchos Prisma." ],
  [ zelda, "Carla Menezes", 6, 5,
    "Quanto tempo dura a bateria? Já perdi save de cartucho original antigo e fiquei traumatizada.",
    "A memória é FRAM, então o save não depende da bateria para se manter, ela só alimenta o relógio interno. Na prática você não perde progresso mesmo se a bateria acabar." ],
  [ zelda, "Eduarda Lima", 7, 6,
    "Dá para pedir a etiqueta em padrão japonês com a caixa americana?",
    "Dá sim, é só escolher etiqueta JP e caixa US nas opções acima. Se quiser algo fora das combinações padrão, chama no WhatsApp que a gente monta." ],
  [ zelda, "Felipe Andrade", 9, 8,
    "Vocês enviam para Manaus? Qual o prazo médio depois que o pedido é produzido?",
    "Enviamos para todo o Brasil pelos Correios. Para Manaus o PAC costuma levar de 9 a 14 dias úteis depois da produção, e o SEDEX de 4 a 6. O rastreio sai no mesmo dia da postagem." ],
  [ zelda, "Henrique Sales", 12, 11,
    "A caixa vem com o encarte interno impresso ou só a capa?",
    "A caixa rígida vem com capa impressa em papel couché e o berço interno em plástico. Encarte de manual é vendido à parte, na seção de acessórios." ],
  [ zelda, "Isabela Cunha", 15, nil,
    "Tem previsão de sair a versão em português desse Oracle of Ages?", nil ],
  [ zelda, "Diego Fontes", 5, nil,
    "Aceita cartão parcelado? E tem desconto se eu levar os dois Oracle juntos?",
    "Parcelamos em até 4x sem juros no cartão e no Pix sai com 5% de desconto. Levando os dois Oracle no mesmo pedido o frete fica por nossa conta." ],
  [ kirby, "João Pedro Nunes", 3, 2,
    "Esse é o Dream Land 2 mesmo, com os amigos animais?",
    "É o Dream Land 2 sim, com Rick, Coo e Kine. Roda em Game Boy, Game Boy Color e Game Boy Advance." ],
  [ kirby, "Natália Prado", 1, nil,
    "Vocês emitem nota fiscal para pessoa jurídica?", nil ]
]

moderated = [
  [ zelda, "Marcos Aurélio", 20, "spam",
    "Acesse meu site de promoções agora mesmo e ganhe dinheiro rápido sem sair de casa." ],
  [ zelda, "Otávio Bittencourt", 40, "archived",
    "Pergunta duplicada, já respondida em outro cartucho da loja." ]
]

def demo_customer(name)
  User.find_by(email: "#{name.parameterize}@prismagames.dev")
end

def seed_question(slug, name, days_ago, body, attributes)
  product = Product.find_by(slug: slug)
  user = demo_customer(name)
  return 0 unless product && user

  question = Question.find_or_initialize_by(product: product, user: user, body: body)
  return 0 unless question.new_record?

  asked_at = days_ago.days.ago
  question.assign_attributes(attributes.merge(created_at: asked_at, updated_at: asked_at))
  question.save!
  1
end

def thread_status(answer, answered_days)
  return "awaiting_answer" unless answer
  answered_days ? "answered" : "draft"
end

created = threads.sum do |slug, name, asked_days, answered_days, body, answer|
  seed_question(slug, name, asked_days, body,
                answer_body: answer,
                status: thread_status(answer, answered_days),
                answered_at: answered_days&.days&.ago)
end

created += moderated.sum do |slug, name, days_ago, status, body|
  seed_question(slug, name, days_ago, body, status: status)
end

puts "Perguntas: #{created} nova(s), #{Question.answered.count} respondida(s), " \
     "#{Question.awaiting_answer.count} aguardando, #{Question.draft.count} em rascunho, " \
     "#{Question.where(status: %w[spam archived]).count} moderada(s)."
