# frozen_string_literal: true

module Querylane
  # An opaque, expiring handle for one group of hits (e.g. a person), so a page
  # can ask for "more records" without the group's key (a member ID) ever
  # reaching HTML. Encrypted and signed with the host app's secret, bound to
  # the definition's name.
  module GroupToken
    module_function

    # @param definition [Querylane::Definition]
    # @param value [String] the group attribute's value
    # @param shown [Array<String>] "index:id" of the group's records already on the page
    # @return [String]
    def write(definition, value, shown, config: Querylane.configuration)
      encryptor.encrypt_and_sign({"v" => value.to_s, "s" => shown}, purpose: purpose(definition), expires_in: config.group_token_ttl)
    end

    # @return [Array(String, Array<String>), nil] nil when tampered, expired or for another definition
    def read(definition, token)
      payload = encryptor.decrypt_and_verify(token.to_s, purpose: purpose(definition))
      [payload.fetch("v"), Array(payload["s"])] if payload.is_a?(Hash)
    rescue ActiveSupport::MessageEncryptor::InvalidMessage, ActiveSupport::MessageVerifier::InvalidSignature
      nil
    end

    def purpose(definition) = "querylane.group.#{definition.name}"

    def encryptor
      ActiveSupport::MessageEncryptor.new(Rails.application.key_generator.generate_key("querylane group token", 32))
    end
  end
end
