# Variáveis do Bitbucket Pipelines

Depois do `terraform apply`, copie os outputs e configure no Bitbucket:

**Repository settings → Pipelines → Repository variables**

Não versionar access keys. Marque `AWS_SECRET_ACCESS_KEY` (e de preferência também o access key id) como **Secured**.

Policy de referência: `docs/pipeline-iam-policy.json`.
