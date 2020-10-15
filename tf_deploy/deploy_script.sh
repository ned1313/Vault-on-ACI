# Login and select subscription
az login
az account set -s SUB_NAME

# Deploy Terraform stuff
terraform init
terraform apply -auto-approve

#Update the storage account name from the Terraform output
sa_name=STORAGE_ACCOUNT_NAME

az storage file upload --account-name $sa_name --share-name vault-data --source vault-config.hcl 
az storage file upload --account-name $sa_name --share-name vault-data --source vault-cert.crt --path certs
az storage file upload --account-name $sa_name --share-name vault-data --source vault-cert.key --path certs

# Launch the container using the Terraform output

# Set the environment variables using the Terraform output

# Verify Vault connectivity
vault status

# If this is the first launch, initialize the Vault
vault operator init -recovery-shares=1 -recovery-threshold=1 

vault operator unseal

# Make note of the Recovery Key and Root Token

vault login

vault secrets enable kv

vault kv put kv/tacos meat=chicken

vault kv get kv/tacos

# Delete the container using the Terraform output when you're done

# Delete the files in the cert directory if you plan to delete everything
az storage file delete --account-name $sa_name --share-name vault-data --path certs/vault-cert.crt
az storage file delete --account-name $sa_name --share-name vault-data --path certs/vault-cert.key

# Destroy the terraform resources
terraform destroy -auto-approve