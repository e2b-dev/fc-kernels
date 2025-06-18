-include .env

tf_vars := TF_VAR_gcp_project_id=$(GCP_PROJECT_ID) \
	TF_VAR_prefix=$(PREFIX) \
	TF_VAR_terraform_state_bucket=$(TERRAFORM_STATE_BUCKET)


.PHONY: init
init:
	@ printf "Initializing Terraform\n\n"
	terraform init -reconfigure -input=false -backend-config="bucket=${TERRAFORM_STATE_BUCKET}"

.PHONY: plan
plan:
	@ printf "Planning Terraform\n\n"
	terraform fmt -recursive
	$(tf_vars) terraform plan -out=.tfplan -compact-warnings -detailed-exitcode

.PHONY: apply
apply:
	@ printf "Applying Terraform\n\n"
	$(tf_vars) \
	terraform apply \
	-auto-approve \
	-input=false \
	-compact-warnings \
	-parallelism=20 \
	.tfplan
	@ rm .tfplan
