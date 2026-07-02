module Users
  class Mailer < Devise::Mailer
    layout "mailer"
    helper EmailHelper
  end
end
