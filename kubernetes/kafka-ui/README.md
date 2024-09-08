helm repo add kafka-ui https://provectus.github.io/kafka-ui-charts
helm install helm-release-name kafka-ui/kafka-ui -f values.yml --namespace monitoring