locals {
  should_generate_certificates = var.generate_ca_certificates && length(var.kubernetes_certificates) == 0  
  certificates_names = var.generate_ca_certificates ? ["client-ca", "server-ca", "request-header-key-ca"] : []
  certificates_types = { for s in local.certificates_names : index(local.certificates_names, s) => s }
  certificates_by_type = { for s in local.certificates_names : s =>
    try(tls_self_signed_cert.kubernetes_ca_certs[index(local.certificates_names, s)].cert_pem, null)
  }
  certificates_files = flatten(
    [      
      [for s in local.certificates_names :
        flatten([
          { 
            "file_name" = "${s}.key" 
            "file_content" = tls_private_key.kubernetes_ca[index(local.certificates_names, s)].private_key_pem 
          },
          { 
            "file_name" = "${s}.crt" 
            "file_content" = tls_self_signed_cert.kubernetes_ca_certs[index(local.certificates_names, s)].cert_pem
          }
        ])
      ]
      ,var.kubernetes_certificates 
    ]
  )
  cluster_ca_certificate = try(local.certificates_by_type["server-ca"], null)
  client_certificate     = try(tls_locally_signed_cert.master_user[0].cert_pem, null)
  client_key             = try(tls_private_key.master_user[0].private_key_pem, null)
}

# Keys
resource "tls_private_key" "kubernetes_ca" {
  count       = var.generate_ca_certificates ? 3 : 0

  algorithm   = "ECDSA"
  ecdsa_curve = "P384"
}

# certs
resource "tls_self_signed_cert" "kubernetes_ca_certs" {
  for_each              = local.certificates_types

  key_algorithm         = "ECDSA"
  validity_period_hours = 876600 # 100 years
  allowed_uses          = ["critical", "digitalSignature", "keyEncipherment", "keyCertSign"]
  private_key_pem       = tls_private_key.kubernetes_ca[each.key].private_key_pem
  is_ca_certificate     = true

  subject {
    common_name = "kubernetes-${each.value}"
  }
}

# master-login cert
resource "tls_private_key" "master_user" {
  count       = var.generate_ca_certificates ? 1 : 0

  algorithm   = "ECDSA"
  ecdsa_curve = "P384"
}

resource "tls_cert_request" "master_user" {
  count       = var.generate_ca_certificates ? 1 : 0

  key_algorithm   = "ECDSA"
  private_key_pem = tls_private_key.master_user[0].private_key_pem

  subject {
    common_name  = "master-user"
    organization = "system:masters"
  }
}

resource "tls_locally_signed_cert" "master_user" {
  count       = var.generate_ca_certificates ? 1 : 0

  cert_request_pem   = tls_cert_request.master_user[0].cert_request_pem
  ca_key_algorithm   = "ECDSA"
  ca_private_key_pem = tls_private_key.kubernetes_ca[0].private_key_pem
  ca_cert_pem        = tls_self_signed_cert.kubernetes_ca_certs[0].cert_pem

  validity_period_hours = 876600

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "client_auth"
  ]
}
