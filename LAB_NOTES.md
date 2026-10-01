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

## Lab 2 — Kubernetes (in progress)

`kind` v0.33.0 installed. Next: `kind create cluster --name hello-lab`, then
`kind load docker-image`, `pod.yaml`, `kubectl apply`, `port-forward`,
`kubectl describe` to see schedule → pull → start.

## Lab 3 — Jenkins (not started)

Jenkins in Docker; pipeline with Build App → parallel Lint/Spec → Publish, then
a variant where Publish runs parallel with tests to show CPD overlap.
