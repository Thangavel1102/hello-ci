# CI Lab Notes

Running log of this Docker / Kubernetes / Jenkins lab. Update as labs complete.

## Environment gotchas on this machine

- **Container engine is Rancher Desktop**, socket at `~/.rd/docker.sock`. If
  `docker` says "Cannot connect to the Docker daemon", the app simply isn't
  launched. Open it and wait ~40s for the VM.
- **Zscaler intercepts TLS.** The Docker daemon already trusts its CA, but a
  fresh container does not, so HTTPS from inside a build fails. Fixed by
  copying `certs/zscaler.crt` into the image and running `update-ca-certificates`
  *before* `bundle install`.
- **Port 8080 is taken** by an unrelated Java/Jetty process. Use 8081 for the app.
  A Jetty 404 means the request never reached Rails — always read the `Server:`
  response header first.
- **kubectl defaults to a real Intuit cluster** (`payroll-ppd-usw2-k8s`). Always
  run `kubectl config current-context` and confirm `kind-hello-lab` before any
  `kubectl apply`.
- `rg` is not installed; use `grep`.

## Lab 0 — Rails app ✅

Added JSON to `HealthController#show`, removed a duplicate route.

| Command | Purpose |
| --- | --- |
| `bin/rails server -p 3000` | Run the app on the host |
| `curl -i http://localhost:3000/health` | Confirm the endpoint |

## Lab 1 — Docker ✅

Created `Dockerfile` and `.dockerignore`.

| Command | Purpose |
| --- | --- |
| `docker build -t hello-ci:v1 .` | Build image; `.` is the build context |
| `docker images` / `docker ps` | Read-only state inspection |
| `docker run --rm -p 8081:3000 --name hello-ci hello-ci:v1` | Run container, map host:container port |
| `docker build -t hello-ci:v2 .` | Rebuild after a code change (cached layers are fast) |

Key ideas: everything above `CMD` runs at build time, `CMD` at start time. Code
is baked in, so a source edit needs a rebuild, not a restart. A tag is a movable
label on an immutable image — use a new tag per build so rollback stays possible.

## Lab 1.5 — Registries ✅

Pushed to Docker Hub as `thangavelp1102/hello-ci:v2`.

| Command | Purpose |
| --- | --- |
| `docker login -u <user>` | Authenticate (needs a **Read & Write** token) |
| `docker tag hello-ci:v2 <user>/hello-ci:v2` | Rename to include the registry target |
| `docker push <user>/hello-ci:v2` | Upload |
| `docker rmi <name>` | Remove a tag; image dies with its last tag |
| `docker run <user>/hello-ci:v2` | Pulls automatically if missing |

Key idea: the image **name is an address**. No hostname means `docker.io`;
a dot/colon or `localhost` in the first part means that's the registry. Docker
never searches multiple registries. `registry:2` is the same software Docker Hub
runs, so `localhost:5001/...` works identically to ECR or Artifactory.

## Lab 2 — Kubernetes ✅

Cluster `hello-lab` (kind v0.33.0), manifest at `k8s/pod.yaml`.

| Command | Purpose |
| --- | --- |
| `kind create cluster --name hello-lab` | One-node cluster; the node is a container |
| `kubectl config current-context` | **Safety check** — must be `kind-hello-lab` |
| `kubectl apply -f k8s/pod.yaml` | Submit desired state |
| `kubectl get pods` / `-o wide` | Status; `-o wide` adds pod IP and node |
| `kubectl describe pod hello-ci` | Events: the real debugging output |
| `kind load docker-image hello-ci:v2 --name hello-lab` | Copy a local image onto the node |
| `kubectl port-forward pod/hello-ci 8082:3000` | Debug tunnel from host to pod |
| `kubectl logs hello-ci [-f]` | Container stdout |
| `kubectl exec -it hello-ci -- bash` | Shell inside the container |
| `kubectl delete pod hello-ci` | Remove it |

Key ideas: images live on the **node**, not in the pod — `ImagePullBackOff` means
the node couldn't obtain the image reference, and a bare `image: hello-ci:v2`
resolves to `docker.io/library/hello-ci:v2`. The Events list separates the phases
(Scheduled → Pulled → Created → Started), so a slow or stuck deploy can be
attributed to capacity, registry, or app boot. A pod IP (`10.244.x.x`) is
cluster-internal only. A **bare Pod is not self-healing** — delete it and it stays
deleted; a Deployment is what maintains a desired replica count.

## Lab 2.5 — Git ✅

Repo pushed to `https://github.com/Thangavel1102/hello-ci` (private).
Per-repo identity via `git config user.email` (no `--global`) keeps work commits
separate. `gh auth login` stores credentials in the keychain — but it defers to a
`GITHUB_TOKEN` env var if one is set (`~/.zshrc` line 129 had one; `unset` it).
Plain `git` never reads `GITHUB_TOKEN`.

## Lab 2 bonus — Deployment + Service (in progress)

Manifests: `k8s/deployment.yaml`, `k8s/service.yaml`.

| Command | Purpose |
| --- | --- |
| `kubectl apply -f k8s/deployment.yaml` | Desired replica count, not a one-off pod |
| `kubectl get deployments` | `READY`/`UP-TO-DATE`/`AVAILABLE` |
| `kubectl label pod hello-ci app-` | Trailing `-` removes a label |
| `kubectl get pods --show-labels` | See labels |
| `kubectl apply -f k8s/service.yaml` | Stable address in front of the pods |
| `kubectl get endpointslices -l kubernetes.io/service-name=hello-ci` | Which pods the Service found |
| `kubectl exec -it deployment/hello-ci -- curl -s http://hello-ci/health` | Reach the app by DNS name |
| `kubectl port-forward deployment/hello-ci 8082:3000` | Target the Deployment, not a pod name |
| `kubectl get pods -w` | Watch state changes live |

Key ideas: a **label** is a sticky note on an object; a **selector** is a standing
search for it. Pod names are generated and change constantly, so a Service finds
pods by label and new matching pods join the pool automatically. The Deployment
uses the same mechanism (`selector.matchLabels`) to count its own pods. A YAML
file is not a pod — the cluster holds its own copy after `apply`, so deleting the
file changes nothing and editing it changes nothing until re-applied. Note a bare
pod *does* get its container restarted by the kubelet on crash (`RESTARTS` ticked
up); what it lacks is replacement when the pod itself is deleted.
The `readinessProbe` on `/health` in `deployment.yaml` is what gates whether a pod
joins the Service — the basis of zero-downtime deploys.

### Current cluster state

- Deployment `hello-ci`, **1 replica**, image `hello-ci:v2`.
- Service `hello-ci` at `10.96.73.137:80` → pod port 3000.
- Bare pod `hello-ci` from `k8s/pod.yaml` is **deliberately kept** for the team
  demo (contrast: delete it and it stays gone). Its `app` label was removed so
  the Service ignores it.

### Resume here

1. `kubectl scale deployment hello-ci --replicas=3`, then watch the endpoint list
   grow from 1 to 3 without touching the Service.
2. Rolling update: change the message string, `docker build -t hello-ci:v3 .`,
   `kind load docker-image hello-ci:v3 --name hello-lab`,
   `kubectl set image deployment/hello-ci web=hello-ci:v3`, and curl in a loop to
   see zero failed requests while pods are replaced one at a time.
3. `kubectl rollout status` / `kubectl rollout undo` to roll back to v2.

## Lab 3 — Jenkins (not started)

Core, in order:

1. Jenkins in Docker, through the setup wizard.
2. Pipeline: `Build App` → parallel `Lint`/`Spec` → `Publish` (echo steps suffice).
3. Second pipeline with `Publish` parallel to the tests, to compare total time.

Optional, and what would make the strongest team demo — it joins all three tools:

4. Jenkins clones the GitHub repo and builds on commit.
5. Docker Hub credentials in Jenkins' credential store so Publish really pushes.
6. Pipeline runs `kubectl apply` against the kind cluster, so a commit ends as a
   running pod.
