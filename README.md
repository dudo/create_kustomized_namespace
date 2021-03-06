# Kustomized Namespaces

Provide management of infinite namespaced feature branch deployments to a Kubernetes cluster via Kustomize. This is designed to read from a GitHub repository containing your manifests, structured as such ([example](https://github.com/dudo/k8s_colors)):

    .
    ├── blue/
    │   ├── base/
    │   │   ├── kustomization.yaml
    │   │   ├── deployment.yaml
    │   │   ├── service.yaml
    │   │   └── etc...yaml
    │   └── overlays/ # this folder will be created **and managed** for you
    │       ├── development/
    │       │   └── kustomization.yaml
    │       ├── feature-branch-1/
    │       │   └── kustomization.yaml
    │       └── feature-branch-2/
    │           └── kustomization.yaml
    └── red/
        ├── base/
        │   ├── kustomization.yaml
        │   ├── deployment.yaml
        │   ├── service.yaml
        │   └── etc...yaml
        └── overlays/ # this folder will be created **and managed** for you
            ├── development/
            │   └── kustomization.yaml
            ├── feature-branch-1/
            │   └── kustomization.yaml
            └── feature-branch-2/
                └── kustomization.yaml

You only need to tell Kustomize about the files in your base folder, [per kustomize](https://github.com/kubernetes-sigs/kustomize), the rest is managed for you.
Within each services’ base folder, create an appropriate `kustomization.yaml`

    ---
    kind: Kustomization
    apiVersion: kustomize.config.k8s.io/v1beta1

    resources:
    - deployment.yaml
    - service.yaml
    - etc...yaml

## Create

This repository creates a namespace, and ensures that your services play nicely with each other within it.

As you deploy a feature for a given service, all of your other services are "deployed" within that namespace, but pointed to the service running in the default namespace via `ExternalName`. This allows integration tests to be run to ensure that your new features play nicely with existing services. If deploy a second service within the same namespace, it will behave as expected, and deploy the image appropriately.

Ingress are created, to allow any visual testing, as a subdomain matching your feature (but transformed to kebab-case, ie feature-branch-1.localhost).

### Flags

- `-s, --service` - The service to deploy to your cluster
- `-r, --cluster-repo` - GitHub repository that controls your cluster'
- `-i, --target-image` - Remotely hosted target image
- `-n, --namespace` - Desired namespace, or inferred from $GITHUB_REF
- `-t, --tag` - Image tag, or inferred from $GITHUB_SHA
- `-T, --token` - GitHub access token with repos access, _NOT_ $GITHUB_TOKEN
- `--flux` - a manifest is generated to allow [Weave Flux](https://github.com/weaveworks/flux) to deploy your cluster
- `--dry-run` - the yaml files are printed to stdout
- `—-built` - when paired with —-dry-run, will build your kustomizations and output the built manifests

### Demo

Check out the overlays to be created:

    docker build -t kustomized_namespaces/create:latest .
    docker run -rm kustomized_namespaces/create:latest -r dudo/k8s_colors -n feature_branch_1 -s blue -i dudo/blue -t latest --dry-run

And to see Kustomize do its thing:

    docker run -rm kustomized_namespaces/create:latest -r dudo/k8s_colors -n feature_branch_1 -s blue -i dudo/blue -t latest --dry-run --built

Actually commit to your repo!

    docker run -rm kustomized_namespaces/create:latest -r dudo/k8s_colors -n feature_branch_1 -s blue -i dudo/blue -t latest -T YourReposDeployKeyToken

### Example GitHub Actions Workflow

    on:
      pull_request:
        types: [labeled]
    name: Build, push, and deploy
    env:
      TARGET_IMAGE: dudo/blue
    jobs:
      docker:
        if: github.event.label.name == 'deploy'
        name: Build and push Docker Image
        runs-on: ubuntu-latest
        steps:
        - uses: actions/checkout@v1
        - name: Registry
          env:
            DOCKER_PASSWORD: ${{ secrets.DOCKER_PASSWORD }}
            DOCKER_USERNAME: ${{ secrets.DOCKER_USERNAME }}
          run: docker login -u $DOCKER_USERNAME -p $DOCKER_PASSWORD
        - name: Build
          run: docker build -t $TARGET_IMAGE:${GITHUB_SHA::7} .
        - name: Push
          run: docker push $TARGET_IMAGE:${GITHUB_SHA::7}
      deploy:
        name: Deploy to Cluster
        runs-on: ubuntu-latest
        needs: docker
        env:
          SERVICE: blue
          CLUSTER_REPO: dudo/k8s_colors
        steps:
        - name: Kustomized Namespace - Create Overlay
          env:
            TOKEN: ${{ secrets.TOKEN }}
          uses: zyngl/create_kustomized_namespace@v1.3.0
          with:
            args: --flux
