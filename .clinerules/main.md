# HOMELAB CONTEXT & RULES

## Global Rules & Hardware Constraints
- **Local Machine:** MacBook Pro (Intel Core i7, 16GB RAM). Prefer cloud APIs or remote hosting over local heavy LLMs.
- **Physycs Infrastructure:** 2x Mini PCs GMKTec M7 Ultra running Proxmox VE; Each one with Ryzen 7 Pro 6850U (8C / 16T), 32GB RAM and 1 TB NVMe.
- **Automation Entrypoint:** Always check the root `Makefile` for available shortcuts before writing custom scripts.
- **Cluster:** Kubernetes managed natively via Talos Linux (immutable/declarative configs).
- **Secrets:** HashiCorp Vault running inside a dedicated Proxmox LXC container.

## Repository Structure & Architecture
- `/terraform`: Infrastructure as Code for Proxmox provisioning.
- `/k8s`: Kubernetes manifests to bootstrap the cluster and bring it to a "Ready to use" state.
- `/talos/patches/init`: Custom patches for Talos node initialization.
- `/vault/policies`: HashiCorp Vault policies and access controls.
- `/tests`: Automated testing scripts for infrastructure/app validation.
- `Makefile`: Entrypoint for common automation tasks.

## Versions
- Proxmox v9.2
- Talos v1.13.4
- Kubernetes 1.36
- HashiCorp Vault v2.0.4 (sobre un LXC con Debian 12)
- Terraform v1.15.6
- Helm v1.4

## Agent Behavioral Rules (Token-Saving & Accuracy)
1. **No Hallucinations on Versions:** We work with especifics versions of Talos Linux, Terraform, Kubernetes, and Vault. If you do not know the syntax of the latest version, YOU MUST CALL YOUR ACTIVE MCP TOOL (`tavily`) to check the official documentation first. Do not guess. Explicitly state in your thinking process that you are executing a web search via MCP to ensure version compliance. If you need to generate a code snippet for something but I haven't specified the version, do not assume it; ask me before you start generating or searching for code online (for example, for the `values.yaml` of a Helm chart I need to install on my Kubernetes cluster). Do not guess.
2. **On-Demand Reading:** Do not attempt to read all scripts or YAMLs at once. Read the specific file required for the current sub-task (e.g., read `VAULT_README.md` only when working with Vault policies).
3. **Incremental Edits:** When modifying Kubernetes manifests, Terraform files or Shell scripts, use targeted line-by-line block edits. Avoid rewriting entire multi-line deployment files.
4. **DevOps Security:** Never expose Vault tokens, certificates, or plain-text credentials in the code or git history. Use references to Vault policies or Kubernetes Secrets, or you could let me know if I should create an environment variable in my ".env" file or in my "terraform/terraform.tfvars" file.
