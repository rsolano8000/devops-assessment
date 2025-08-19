#!/usr/bin/env bash
set -euo pipefail

# ---------- Usage ----------
# ./validate_gcp_ci.sh \
#   --project-id directed-craft-469416-u3 \
#   --project-number 276959457448 \
#   --region us-central1 \
#   --github-owner rsolano8000 \
#   --github-repo devops-assessment \
#   --sa-email github-actions-deployer@directed-craft-469416-u3.iam.gserviceaccount.com
#
# Notes:
# - Requires: gcloud
# - Optional: gh (GitHub CLI) to validate GitHub secrets/variables; must be authenticated: `gh auth status`
# - The script is SAFE to run multiple times; it only reads state and exits non-zero on missing/invalid items.

PROJECT_ID=""
PROJECT_NUMBER=""
REGION="us-central1"
GITHUB_OWNER=""
GITHUB_REPO=""
SA_EMAIL=""

# Colors
GRN=$(tput setaf 2 || true); RED=$(tput setaf 1 || true); YEL=$(tput setaf 3 || true); BLU=$(tput setaf 4 || true); RST=$(tput sgr0 || true)
ok() { echo "${GRN}✔${RST} $*"; }
warn() { echo "${YEL}⚠${RST} $*"; }
err() { echo "${RED}✖${RST} $*"; }
info() { echo "${BLU}➜${RST} $*"; }

die() { err "$*"; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-id) PROJECT_ID="$2"; shift 2 ;;
    --project-number) PROJECT_NUMBER="$2"; shift 2 ;;
    --region) REGION="$2"; shift 2 ;;
    --github-owner) GITHUB_OWNER="$2"; shift 2 ;;
    --github-repo) GITHUB_REPO="$2"; shift 2 ;;
    --sa-email) SA_EMAIL="$2"; shift 2 ;;
    -h|--help) sed -n '1,80p' "$0"; exit 0 ;;
    *) die "Unknown arg: $1" ;;
  esac
done

[[ -z "${PROJECT_ID}" ]] && die "--project-id is required"
[[ -z "${PROJECT_NUMBER}" ]] && die "--project-number is required"

# ---------- Checks begin ----------
require_cmd gcloud

info "Checking gcloud auth..."
ACTIVE_ACCT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" || true)
[[ -n "${ACTIVE_ACCT}" ]] && ok "gcloud active account: ${ACTIVE_ACCT}" || die "No active gcloud account. Run: gcloud auth login"

info "Verifying gcloud project config..."
CUR_PROJ=$(gcloud config get-value project 2>/dev/null || true)
if [[ "${CUR_PROJ}" != "${PROJECT_ID}" ]]; then
  warn "gcloud configured project is '${CUR_PROJ}', expected '${PROJECT_ID}'"
  info "You can set it with: gcloud config set project ${PROJECT_ID}"
else
  ok "gcloud project is set to ${PROJECT_ID}"
fi

info "Confirming project exists and matches the number..."
DESC_JSON=$(gcloud projects describe "${PROJECT_ID}" --format=json) || die "Project not found: ${PROJECT_ID}"
NUM=$(echo "${DESC_JSON}" | python3 - <<'PY'
import sys,json; d=json.load(sys.stdin); print(d.get("projectNumber",""))
PY
)
[[ "${NUM}" == "${PROJECT_NUMBER}" ]] && ok "Project number matches: ${PROJECT_NUMBER}" || die "Project number mismatch. Got: ${NUM}, expected: ${PROJECT_NUMBER}"

REQUIRED_APIS=(
  container.googleapis.com
  artifactregistry.googleapis.com
  secretmanager.googleapis.com
  iam.googleapis.com
  iamcredentials.googleapis.com
  cloudresourcemanager.googleapis.com
  compute.googleapis.com
  serviceusage.googleapis.com
)

info "Checking required Google APIs are enabled..."
MISSING=()
for api in "${REQUIRED_APIS[@]}"; do
  if gcloud services list --enabled --format="value(config.name)" | grep -qx "${api}"; then
    ok "API enabled: ${api}"
  else
    MISSING+=("${api}")
  fi
done
if [[ ${#MISSING[@]} -gt 0 ]]; then
  err "Missing APIs: ${MISSING[*]}"
  info "Enable with:\n  gcloud services enable ${MISSING[*]}"
  exit 1
fi

info "Checking Cloud NAT for region '${REGION}' (required for private GKE nodes)..."
# It's OK if NAT name differs; we just need at least one NAT in the region.
NAT_COUNT=$(gcloud compute routers nats list --regions="${REGION}" --format="value(name)" | wc -l | tr -d ' ')
if [[ "${NAT_COUNT}" -ge 1 ]]; then
  ok "Found ${NAT_COUNT} Cloud NAT(s) in ${REGION}"
else
  err "No Cloud NAT found in ${REGION}."
  info "Create one:\n  gcloud compute routers create nat-router --network=default --region=${REGION}\n  gcloud compute routers nats create nat-config --router=nat-router --region=${REGION} --nat-all-subnet-ip-ranges --auto-allocate-nat-external-ips"
  exit 1
fi

info "Checking Secret Manager entries (app-message-staging / app-message-production)..."
for s in app-message-staging app-message-production; do
  if gcloud secrets describe "$s" --format="value(name)" >/dev/null 2>&1; then
    if gcloud secrets versions list "$s" --filter="state=ENABLED" --format="value(name)" --limit=1 | grep -q .; then
      ok "Secret exists and has an enabled version: $s"
    else
      err "Secret exists but has no ENABLED version: $s"
      info "Add one:\n  printf \"Hello from ...\\n\" | gcloud secrets versions add $s --data-file=-"
      exit 1
    fi
  else
    err "Secret not found: $s"
    info "Create it:\n  gcloud secrets create $s --replication-policy=automatic\n  printf \"Hello from ...\\n\" | gcloud secrets versions add $s --data-file=-"
    exit 1
  fi
done

info "Checking Workload Identity Federation (OIDC) pool and provider..."
POOL_RES="projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/github-pool"
PROV_RES="${POOL_RES}/providers/github-provider"
if gcloud iam workload-identity-pools describe "${POOL_RES}" --location="global" >/dev/null 2>&1; then
  ok "Found WIF pool: ${POOL_RES}"
else
  err "WIF pool not found: ${POOL_RES}"
  exit 1
fi
if gcloud iam workload-identity-pools providers describe "${PROV_RES}" --location="global" >/dev/null 2>&1; then
  ok "Found WIF provider: ${PROV_RES}"
else
  err "WIF provider not found: ${PROV_RES}"
  exit 1
fi

if [[ -n "${SA_EMAIL}" ]]; then
  info "Checking CI service account exists: ${SA_EMAIL}"
  if gcloud iam service-accounts describe "${SA_EMAIL}" >/dev/null 2>&1; then
    ok "Service account exists"
  else
    err "Service account not found: ${SA_EMAIL}"
    exit 1
  fi

  info "Checking IAM roles bound to the CI service account..."
  declare -a ROLES=(
    roles/container.admin
    roles/artifactregistry.writer
    roles/secretmanager.secretAccessor
  )
  POLICY_JSON=$(gcloud projects get-iam-policy "${PROJECT_ID}" --format=json)
  missing_roles=()
  for role in "${ROLES[@]}"; do
    python3 - "$SA_EMAIL" "$role" <<<"$POLICY_JSON" >/dev/null 2>&1 || true
    if ! python3 - "$SA_EMAIL" "$role" <<<"$POLICY_JSON" <<'PY'
import sys,json
pol=json.load(sys.stdin)
sa=sys.argv[1]
role=sys.argv[2]
for b in pol.get("bindings",[]):
    if b.get("role")==role and f"serviceAccount:{sa}" in b.get("members",[]):
        print("FOUND")
        sys.exit(0)
sys.exit(1)
PY
    then
      missing_roles+=("$role")
    else
      ok "Role present: $role"
    fi
  done
  if [[ ${#missing_roles[@]} -gt 0 ]]; then
    err "Missing roles on ${SA_EMAIL}: ${missing_roles[*]}"
    info "Grant with:\n  for r in ${missing_roles[*]}; do gcloud projects add-iam-policy-binding ${PROJECT_ID} --member=serviceAccount:${SA_EMAIL} --role=$r; done"
    exit 1
  fi
else
  warn "Skipping service account & IAM role checks (no --sa-email provided)"
fi

info "Checking Artifact Registry repo (optional; Terraform creates it if missing)..."
if gcloud artifacts repositories describe app-images --location="${REGION}" >/dev/null 2>&1; then
  ok "Artifact Registry repository exists: app-images (${REGION})"
else
  warn "Artifact Registry repo 'app-images' not found in ${REGION}. Terraform will create it."
fi

info "Checking GKE clusters (optional; expected absent before Terraform apply)..."
for c in gke-staging gke-production; do
  if gcloud container clusters describe "$c" --region "${REGION}" >/dev/null 2>&1; then
    ok "Cluster exists: $c"
  else
    warn "Cluster not found yet (expected before apply): $c"
  fi
done

# Optional: GitHub secrets/vars validation (if gh is available and you are authenticated)
if command -v gh >/dev/null 2>&1 && [[ -n "${GITHUB_OWNER}" && -n "${GITHUB_REPO}" ]]; then
  info "Checking GitHub Actions secrets/vars via gh (repo: ${GITHUB_OWNER}/${GITHUB_REPO})..."
  if gh auth status >/dev/null 2>&1; then
    # Secrets
    missing_gh_secrets=()
    for s in GCP_WORKLOAD_IDENTITY_PROVIDER GCP_SERVICE_ACCOUNT_EMAIL; do
      if gh secret list -R "${GITHUB_OWNER}/${GITHUB_REPO}" | awk '{print $1}' | grep -qx "$s"; then
        ok "GitHub secret exists: $s"
      else
        missing_gh_secrets+=("$s")
      fi
    done
    if [[ ${#missing_gh_secrets[@]} -gt 0 ]]; then
      err "Missing GitHub repo secrets: ${missing_gh_secrets[*]}"
      info "Add them in GitHub → Settings → Secrets and variables → Actions"
    fi

    # Variables (optional)
    for v in GCP_PROJECT_ID GAR_LOCATION ARTIFACT_REPO STAGING_CLUSTER PRODUCTION_CLUSTER GKE_LOCATION PROD_APPROVERS; do
      if gh variable list -R "${GITHUB_OWNER}/${GITHUB_REPO}" | awk '{print $1}' | grep -qx "$v"; then
        ok "GitHub variable exists: $v"
      else
        warn "GitHub variable not set (optional): $v"
      fi
    done
  else
    warn "gh CLI not authenticated; skipping GitHub checks. Run: gh auth login"
  fi
else
  warn "Skipping GitHub checks (gh CLI not found or owner/repo not provided)"
fi

echo
ok "All critical checks passed! You can proceed with Terraform apply and CI/CD."
