# GitLab Runner Setup and Usage

## Installation

To install the GitLab Runner using Helm:

```bash
helm install --namespace gitlab-runner --create-namespace \
  --set runnerRegistrationToken=TOKEN \
  gitlab-runner gitlab/gitlab-runner \
  --values values.yaml
```

## Uninstallation

To uninstall the GitLab Runner:

```bash
helm uninstall -n gitlab-runner gitlab-runner
```

## GitLab CI/CD Template

Use this template for your `.gitlab-ci.yml` file:

```yaml
xxxxx:
  stage: xxxxx
  image: rollersweet/nvm-az-kubectl:latest
  before_script:
    - source /usr/local/nvm/nvm.sh
    - docker login -u $DOCKER_USER -p $DOCKER_TOKEN $DOCKER_REGISTRY > /dev/null 2>&1
    - echo $KUBECONFIG_BASE64 | base64 -d > /root/.kube/config
  script:
    - |
      docker build --no-cache -t $CI_REGISTRY_IMAGE:$CI_COMMIT_REF_SLUG .
      docker tag $CI_REGISTRY_IMAGE:$CI_COMMIT_REF_SLUG $DOCKER_REPO:$CI_COMMIT_REF_SLUG
      docker push $DOCKER_REPO:$CI_COMMIT_REF_SLUG
  tags:
    - your-runner-tag
```

Replace `xxxxx` with the appropriate stage name and ensure you're using the correct runner tag.