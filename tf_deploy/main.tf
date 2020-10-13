##########################################################################
# Use this configuration to deploy the necessary resources to back an ACI
# deployment of HashiCorp Vault. Use the deploy_script.sh file to proceed
# with setting up the infrastructure and then use the output of this
# module to create the container instance. 
#
# NOTE: This uses a self-signed certificate and is in no way intended for 
# production deployment.
##########################################################################

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 2.0"

    }
  }
}

##########################################################################
# VARIABLES
##########################################################################

variable "prefix" {
    type = string
    default = "aci"
}

variable "location" {
    type = string
    default = "eastus"
}

##########################################################################
# PROVIDER
##########################################################################

provider "azurerm" {
  features {}
}

##########################################################################
# DATA SOURCES and LOCALs
##########################################################################

locals {
    vault_name = "${var.prefix}-vault-${random_integer.id.result}"
    resource_group_name = "${var.prefix}-${random_integer.id.result}"
    storage_account_name = "${var.prefix}sa${random_integer.id.result}"
    key_vault_name = "${var.prefix}-kv-${random_integer.id.result}"
    user_identity_name = "${var.prefix}vault${random_integer.id.result}"
}

data "azurerm_client_config" "current" {}

##########################################################################
# RESOURCES
##########################################################################

# Random ID

resource "random_integer" "id" {
  min     = 10000
  max     = 99999
}

resource "random_string" "token" {
  length = 48
  special = false
}

# Create a self-signed cert

resource "tls_private_key" "private" {
  algorithm = "RSA"
  rsa_bits = 4096
}

resource "tls_self_signed_cert" "cert" {
  key_algorithm   = tls_private_key.private.algorithm
  private_key_pem = tls_private_key.private.private_key_pem

  validity_period_hours = 87600

  # Reasonable set of uses for a server SSL certificate.
  allowed_uses = [
      "key_encipherment",
      "digital_signature",
      "server_auth",
  ]

  dns_names = ["${local.vault_name}.${var.location}.azurecontainer.io"]

  subject {
      common_name  = "${local.vault_name}.${var.location}.azurecontainer.io"
      organization = "Taco Emporium, Inc"
  }
}

resource "local_file" "key" {
    content     = tls_private_key.private.private_key_pem
    filename = "${path.module}/vault-cert.key"
} 

resource "local_file" "cert" {
    content     = tls_self_signed_cert.cert.cert_pem
    filename = "${path.module}/vault-cert.crt"
} 

# Resource group

resource "azurerm_resource_group" "vault" {
    name = local.resource_group_name
    location = var.location
}

# Storage account for persistence

resource_group_name "azurerm_storage_account" "vault" {
    name = local.storage_account_name
    resource_group_name      = azurerm_resource_group.vault.name
    location                 = azurerm_resource_group.vault.location
    account_tier             = "Standard"
    account_replication_type = "LRS"

}

# Storage account share

resource "azurerm_storage_share" "vault" {
  name                 = "vault-data"
  storage_account_name = azurerm_storage_account.vault.name
  quota                = 50

}

# Storage account directory

resource "azurerm_storage_share_directory" "vault" {
  name                 = "certs"
  share_name           = azurerm_storage_share.vault.name
  storage_account_name = azurerm_storage_account.vault.name
}

# User Identity

resource "azurerm_user_assigned_identity" "vault" {
  resource_group_name = azurerm_resource_group.vault.name
  location            = azurerm_resource_group.vault.location

  name = local.user_identity_name
}

# Key Vault

resource "azurerm_key_vault" "example" {
  name                        = local.key_vault_name
  location                    = azurerm_resource_group.vault.location
  resource_group_name         = azurerm_resource_group.vault.name
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  soft_delete_enabled         = true
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false

  sku_name = "standard"

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = azurerm_user_assigned_identity.principal_id

    key_permissions = [
      "get", "list", "create", "delete", "update", "wrapKey", "unwrapKey",
    ]

  }

}

##########################################################################
# OUTPUTS
##########################################################################

# Command to create container instance

output "container_create" {
    value = <<EOF
az container create --resource-group ${azurerm_resource_group.vault.name} \
  --name ${local.vault_name} --image vault:1.5.3 \
  --command-line 'vault server -config /vault/vault-config.hcl' \
  --dns-name-label ${local.vault_name} --ports 8200 \
  --azure-file-volume-account-name ${local.storage_account_name} \
  --azure-file-volume-share-name vault-data \
  --azure-file-volume-account-key ${azurerm_storage_account.vault.primary_access_key} \
  --azure-file-volume-mount-path /vault \
  --assign-identity ${azurerm_user_assigned_identity.id} \
  --environment-variables AZURE_TENANT_ID=${data.azurerm_client_config.current.tenant_id} \
  VAULT_AZUREKEYVAULT_VAULT_NAME=${local.key_vault_name} \
  VAULT_AZUREKEYVAULT_KEY_NAME=vault-key
EOF
}

# Environment variables to set

output "environment_variables" {
    value = <<EOF
export VAULT_ADDR="https://${local.vault_name}.${var.location}.azurecontainer.io:8200"
export VAULT_SKIP_VERIFY=true
EOF
}

output "storage_accountName" {
    value = local.storage_account_name
}

output "container_delete" {
    value = "az container delete --resource-group ${azurerm_resource_group.vault.name} --name ${local.vault_name}"
}