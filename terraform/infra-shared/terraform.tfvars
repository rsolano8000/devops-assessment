# GCP project
project_id = "directed-craft-469416-u3"

# Your GitHub repo selector
github_org         = "rsolano8000"
github_repo        = "devops-assessment"
github_ref         = "refs/heads/main"
github_environment = "" # set to "production" if you require env=production

# New pool/provider to create
pool_id               = "pool-github1"
pool_display_name     = "GitHub Pool 1"
provider_id           = "github"
provider_display_name = "GitHub OIDC"

# CI Service Account short name
ci_sa_name = "pool-github1"
