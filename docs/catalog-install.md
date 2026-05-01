# Installing the PTP Operator from the GHCR Catalog

The PTP Operator publishes a **File-Based Catalog (FBC)** image to the GitHub
Container Registry (GHCR) that contains every release version of the operator
(4.12 through 5.0 and beyond). All images are **public** — no pull secret or
authentication is required.

```
ghcr.io/redhat-cne/ptp-operator-catalog:latest
```

## Available Images

All component images are published for every release version (`v4.12` through
`v5.0`). Replace `{VERSION}` with the desired release (e.g., `v4.22`).

| Component | Image |
|---|---|
| PTP Operator | `ghcr.io/redhat-cne/ptp-operator:{VERSION}` |
| LinuxPTP Daemon | `ghcr.io/redhat-cne/ptp:{VERSION}` |
| Cloud Event Proxy | `ghcr.io/redhat-cne/cloud-event-proxy:{VERSION}` |
| Kube RBAC Proxy | `ghcr.io/redhat-cne/kube-rbac-proxy:{VERSION}` |
| Must-Gather | `ghcr.io/redhat-cne/ptp-must-gather:{VERSION}` |
| Operator Bundle | `ghcr.io/redhat-cne/ptp-operator-bundle:{VERSION}.0` |
| Operator Catalog | `ghcr.io/redhat-cne/ptp-operator-catalog:latest` |

## Prerequisites

| Requirement | Notes |
|---|---|
| Cluster admin access | `kubectl` or `oc` with cluster-admin privileges |
| OLM installed | OpenShift ships OLM by default. For vanilla Kubernetes see [Install OLM](#install-olm-on-kubernetes). |

## OpenShift — OLM v0 (4.x)

### 1. Create the CatalogSource

```yaml
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: ptp-operator-catalog
  namespace: openshift-marketplace
spec:
  sourceType: grpc
  displayName: PTP Operator Catalog (GHCR)
  publisher: Red Hat (dev)
  image: ghcr.io/redhat-cne/ptp-operator-catalog:latest
```

Apply it:

```bash
oc apply -f - <<'EOF'
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: ptp-operator-catalog
  namespace: openshift-marketplace
spec:
  sourceType: grpc
  displayName: PTP Operator Catalog (GHCR)
  publisher: Red Hat (dev)
  image: ghcr.io/redhat-cne/ptp-operator-catalog:latest
EOF
```

Wait for the catalog pod to become ready:

```bash
oc -n openshift-marketplace get pods -l olm.catalogSource=ptp-operator-catalog
```

### 2. Create the Subscription

```bash
oc apply -f - <<'EOF'
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: ptp-operator
  namespace: openshift-ptp
spec:
  channel: stable
  name: ptp-operator
  source: ptp-operator-catalog
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic
EOF
```

> **Tip — pin a specific version:** set `startingCSV: ptp-operator.v4.18.0`
> (or any version listed in the catalog) and change `installPlanApproval` to
> `Manual` to prevent automatic upgrades.

### 3. Verify the installation

```bash
oc -n openshift-ptp get csv
oc -n openshift-ptp get pods
```

## OpenShift — OLM v1 (4.18+)

OpenShift 4.18+ ships OLM v1 alongside v0. The v1 API uses `ClusterCatalog`
instead of `CatalogSource`.

### 1. Create the ClusterCatalog

```bash
oc apply -f - <<'EOF'
apiVersion: olm.operatorframework.io/v1
kind: ClusterCatalog
metadata:
  name: ptp-operator-catalog
spec:
  priority: 1000
  source:
    type: Image
    image:
      ref: ghcr.io/redhat-cne/ptp-operator-catalog:latest
EOF
```

### 2. Create the ClusterExtension

```bash
oc apply -f - <<'EOF'
apiVersion: olm.operatorframework.io/v1
kind: ClusterExtension
metadata:
  name: ptp-operator
spec:
  source:
    sourceType: Catalog
    catalog:
      packageName: ptp-operator
      channels:
        - name: stable
  install:
    namespace: openshift-ptp
    serviceAccount:
      name: ptp-operator-installer
EOF
```

### 3. Verify

```bash
oc get clusterextension ptp-operator
oc -n openshift-ptp get pods
```

## Kubernetes (vanilla) with OLM

### Install OLM on Kubernetes

If OLM is not already installed, use the operator-sdk CLI:

```bash
operator-sdk olm install
```

Or install directly from the OLM releases:

```bash
curl -sSL https://github.com/operator-framework/operator-lifecycle-manager/releases/download/v0.28.0/install.sh | bash -s v0.28.0
```

### 1. Create the namespace

```bash
kubectl create namespace openshift-ptp
```

### 2. Create the CatalogSource

```bash
kubectl apply -f - <<'EOF'
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: ptp-operator-catalog
  namespace: olm
spec:
  sourceType: grpc
  displayName: PTP Operator Catalog (GHCR)
  publisher: Red Hat (dev)
  image: ghcr.io/redhat-cne/ptp-operator-catalog:latest
EOF
```

> On vanilla Kubernetes the default OLM namespace is `olm`, not
> `openshift-marketplace`.

### 3. Create an OperatorGroup

```bash
kubectl apply -f - <<'EOF'
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: ptp-operator-group
  namespace: openshift-ptp
spec:
  targetNamespaces:
    - openshift-ptp
EOF
```

### 4. Subscribe to the operator

```bash
kubectl apply -f - <<'EOF'
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: ptp-operator
  namespace: openshift-ptp
spec:
  channel: stable
  name: ptp-operator
  source: ptp-operator-catalog
  sourceNamespace: olm
  installPlanApproval: Automatic
EOF
```

### 5. Verify

```bash
kubectl -n openshift-ptp get csv
kubectl -n openshift-ptp get pods
```

## Selecting a specific version

The catalog `stable` channel contains all released versions. To install a
particular version instead of the latest:

1. Set `installPlanApproval: Manual` in the Subscription.
2. Add `startingCSV: ptp-operator.v<VERSION>` (e.g., `ptp-operator.v4.18.0`).

```yaml
spec:
  channel: stable
  name: ptp-operator
  source: ptp-operator-catalog
  sourceNamespace: openshift-marketplace
  installPlanApproval: Manual
  startingCSV: ptp-operator.v4.18.0
```

Then approve the install plan:

```bash
oc -n openshift-ptp get installplan
oc -n openshift-ptp patch installplan <plan-name> --type merge -p '{"spec":{"approved":true}}'
```

## Upgrading between versions

With `installPlanApproval: Automatic`, OLM upgrades the operator whenever a new
version appears in the catalog channel. The catalog uses `skipRange` so OLM can
jump directly from any older version to the latest without stepping through
every intermediate release.

To upgrade manually:

1. Ensure `installPlanApproval: Manual`.
2. A new `InstallPlan` is created when a newer CSV is available.
3. Approve the plan to trigger the upgrade.

## Listing available versions

```bash
# OLM v0
oc get packagemanifests ptp-operator -o jsonpath='{.status.channels[?(@.name=="stable")].currentCSV}'

# Or query the catalog pod directly
oc -n openshift-marketplace port-forward svc/ptp-operator-catalog 50051:50051 &
grpcurl -plaintext localhost:50051 api.Registry/ListBundles | jq '.csvName'
```

## Uninstalling

### OpenShift (OLM v0)

```bash
oc -n openshift-ptp delete subscription ptp-operator
oc -n openshift-ptp delete csv -l operators.coreos.com/ptp-operator.openshift-ptp
oc -n openshift-marketplace delete catalogsource ptp-operator-catalog
```

### OpenShift (OLM v1)

```bash
oc delete clusterextension ptp-operator
oc delete clustercatalog ptp-operator-catalog
```

### Kubernetes

```bash
kubectl -n openshift-ptp delete subscription ptp-operator
kubectl -n openshift-ptp delete csv -l operators.coreos.com/ptp-operator.openshift-ptp
kubectl -n olm delete catalogsource ptp-operator-catalog
```

## Troubleshooting

### Catalog pod is not running

```bash
oc -n openshift-marketplace get pods -l olm.catalogSource=ptp-operator-catalog
oc -n openshift-marketplace logs -l olm.catalogSource=ptp-operator-catalog
```

Common causes:
- **Image pull error:** Verify the catalog image is reachable:
  `docker pull ghcr.io/redhat-cne/ptp-operator-catalog:latest`
- **OLM not installed:** Ensure OLM pods are running in the `olm` or
  `openshift-operator-lifecycle-manager` namespace.

### Operator not appearing in OperatorHub

- Check that the CatalogSource is in a `READY` state:
  `oc -n openshift-marketplace get catalogsource ptp-operator-catalog`
- Verify the catalog content:
  `oc -n openshift-marketplace get packagemanifests | grep ptp`

### InstallPlan stuck

```bash
oc -n openshift-ptp get installplan
oc -n openshift-ptp describe installplan <plan-name>
```

If `installPlanApproval` is `Manual`, the plan must be explicitly approved.

### Version not found

Ensure the catalog image is up to date. The CI workflow rebuilds the catalog
weekly and on every push to `main`. Pull the latest:

```bash
docker pull ghcr.io/redhat-cne/ptp-operator-catalog:latest
```

Then restart the catalog pod to pick up the new image:

```bash
oc -n openshift-marketplace delete pod -l olm.catalogSource=ptp-operator-catalog
```
