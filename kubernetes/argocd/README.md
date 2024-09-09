helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

kubectl apply -k "https://github.com/argoproj/argo-cd/manifests/crds?ref=v2.4.9"

helm install my-release argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  --values values.yaml