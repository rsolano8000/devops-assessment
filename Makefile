PROJECT_ID ?= my-gcp-project
REGION ?= us-central1
LOCATION ?= us-central1-a
ARTIFACT_REPO ?= app-images

.PHONY: tf-init-stg tf-apply-stg tf-init-prod tf-apply-prod build run lint

tf-init-stg:
	cd terraform/environments/staging && terraform init

tf-apply-stg:
	cd terraform/environments/staging && terraform apply -auto-approve

tf-init-prod:
	cd terraform/environments/production && terraform init

tf-apply-prod:
	cd terraform/environments/production && terraform apply -auto-approve

build:
	docker build -t helloapp:dev .

run:
	docker run -p 8080:8080 -e APP_MESSAGE="Local Dev" -e ENV=local helloapp:dev

lint:
	helm lint helm/app
