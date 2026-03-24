module SslConfigurable
  extend ActiveSupport::Concern

  private
    def build_cert_store
      OpenSSL::X509::Store.new.tap do |store|
        store.set_default_paths
        store.flags = 0
      end
    end
end
