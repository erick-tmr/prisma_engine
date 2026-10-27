class ContactChangeMailerPreview < ActionMailer::Preview
  def previous_address
    ContactChangeMailer.previous_address(User.first, "endereco-antigo@example.com")
  end

  def new_address
    ContactChangeMailer.new_address(User.first)
  end
end
