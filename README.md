# DevOps / SecOps Assessment Solution

This repository provisions GKE clusters with Terraform, builds and deploys a containerized Hello World application via Helm, and automates CI/CD with GitHub Actions. It implements secrets with **GCP Secret Manager** and uses **Workload Identity Federation** (OIDC) for keyless CI auth.

## Repo Layout
```
app/                          # Go "Hello World" web app
helm/app/                     # Helm chart (values per env)
terraform/
  modules/gke/                # Reusable GKE module + GAR + OIDC (optional)
  environments/
    staging/                  # Staging cluster
    production/               # Production cluster
.github/workflows/ci-cd.yaml  # GitHub Actions pipeline
Dockerfile
README.md
```

## Local Run
```bash
go run ./app
# or with Docker
docker build -t helloapp:dev .
docker run -p 8080:8080 -e APP_MESSAGE="Local Dev" -e ENV=local helloapp:dev
curl http://localhost:8080/
```

## Terraform: GKE, Artifact Registry
Each environment deploys a dedicated private-node GKE cluster with RBAC (default). The master endpoint is public to allow GitHub-hosted runners to deploy. For hardened setups, use private endpoint + self-hosted runners.

### Deploy staging
```bash
cd terraform/environments/staging
terraform init
terraform apply -auto-approve
```
Repeat for `production`.

## Secrets
Create two secrets in **Secret Manager**:
- `app-message-staging`
- `app-message-production`

The pipeline reads them and creates/updates a Kubernetes Secret named `app-message` in each namespace.

## Helm
The chart supports:
- `replicaCount`
- `image.repository` / `image.tag`
- `service.type` / `service.port`
- Per-env values in `values-staging.yaml` / `values-production.yaml`

## CI/CD (GitHub Actions)
- **Build**: Docker image pushed to Artifact Registry
- **Deploy to Staging**: on each commit to `main`
- **Approve**: manual gate using **production** environment reviewers; additionally checks that the actor is in `PROD_APPROVERS` repo/org vars and that the ref is a valid **SemVer** tag (`vMAJOR.MINOR.PATCH`)
- **Deploy to Production**: runs only on SemVer tags after approval

### Required repo settings / variables
- Secrets:
  - `GCP_WORKLOAD_IDENTITY_PROVIDER` (full resource name)
  - `GCP_SERVICE_ACCOUNT_EMAIL` (e.g. github-actions-deployer@PROJECT.iam.gserviceaccount.com)
- Variables:
  - `GCP_PROJECT_ID`, `GAR_LOCATION` (e.g. `us-central1`), `ARTIFACT_REPO` (e.g. `app-images`)
  - `STAGING_CLUSTER`, `PRODUCTION_CLUSTER`, `GKE_LOCATION`
  - `PROD_APPROVERS` (comma-separated GitHub usernames)
- Environments:
  - Create an environment **production** and require reviewers (the same users as `PROD_APPROVERS`)

## Verification
- `kubectl -n app-staging get deploy,svc,pods`
- `kubectl -n app-production get deploy,svc,pods`
- `kubectl -n <ns> logs deploy/app` (should be error-free)
- Hitting the Service external IP should show `Hello from <env> (version <appVersion>): <message>`

## Security Notes
- No static JSON keys; OIDC WIF used for short-lived auth
- Secrets never committed; retrieved on-demand and written directly to Kubernetes Secret (no console echo)
- `helm lint` validates manifests before deploy
- Minimal GitHub Actions permissions + concurrency control
