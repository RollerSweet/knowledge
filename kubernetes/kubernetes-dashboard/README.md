# Installing Kubernetes Dashboard

To install the Kubernetes Dashboard, follow these steps:

1. Add the Kubernetes Dashboard Helm repository and Update your Helm repositories:
```bash
helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/
helm repo update
```
2. Install the Kubernetes Dashboard using the provided values.yaml file:

```bash
helm install kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard -f values.yaml --namespace kubernetes-dashboard --create-namespace
```

3. Retrieve the admin user token for accessing the dashboard:
```bash
kubectl get secret admin-user -n kubernetes-dashboard -o jsonpath={.data.token} | base64 -d
```
4. Access the Kubernetes Dashboard by visiting https://kubernetes-dashboard.domain.name and sign in using the admin user token retrieved in the previous step.