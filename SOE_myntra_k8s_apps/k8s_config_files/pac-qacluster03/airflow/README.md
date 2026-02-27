# Airflow YAML Pack (pac-qacluster03)

This folder is a handoff-ready YAML set for Argo CD users.

## Apply with Argo CD

Point your Argo CD Application source to:

- `SOE_myntra_k8s_apps/k8s_config_files/pac-qacluster03/airflow`

You can use [90-argocd-application-template.yaml](90-argocd-application-template.yaml) as a base template.

## Contents

- `kustomization.yaml`: bundles all manifests in order (Argo CD/Kustomize entrypoint)
- `00-kustomization.yaml`: same content as reference copy
- `01..13`: Airflow multi-namespace control-plane + executor manifests
- `14-monitoring-kube-ops-view.yaml`: monitoring UI deployed in `airflow-core` namespace

## Notes

- Control-plane namespace: `airflow-core`
- Task namespace: `airflow-user`
- Monitoring is not in a separate namespace; it runs in `airflow-core`
