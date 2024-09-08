helm repo add uptime-kuma https://helm.irsigler.cloud
helm repo update

helm upgrade my-uptime-kuma uptime-kuma/uptime-kuma \
  --install \
  --namespace monitoring \
  --create-namespace \
  --values values.yaml