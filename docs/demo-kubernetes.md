# Kubernetes Demo

Six steps. Run from `/Users/tp002/Work/ci-lab/hello-ci`.

Two tabs: one to type in, one running `kubectl get pods -w` so the audience
sees pods appear and disappear live.

---

## Setup (before the audience arrives)

```bash
kubectl get nodes                      # want: hello-lab-control-plane Ready
kubectl config current-context         # MUST say kind-hello-lab

kubectl delete deployment hello-ci --ignore-not-found
kubectl delete service hello-ci --ignore-not-found
kubectl delete pod hello-ci --ignore-not-found

docker build -t hello-ci:v4 .          # build it, but do NOT kind load it yet
```

Set `k8s/pod.yaml` to `image: hello-ci:v4`.
Set `k8s/deployment.yaml` to `image: hello-ci:v3` and `replicas: 1`.

---

## 1. The cluster is a container

```bash
kubectl get nodes
docker ps --filter name=hello-lab
```

**Say:** the same name appears in both lists. kind means "Kubernetes IN
Docker" — the machine running my pods is itself a container on this laptop.
Same API as a real cluster, just one machine.

```bash
kubectl config current-context
```

**Say:** my laptop also has a work cluster configured. This check takes two
seconds and the downside of skipping it is real.

---

## 2. Create a pod — and watch it fail

`k8s/pod.yaml` answers four questions: what kind of object, what to call it,
which image, which port.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: hello-ci
  labels:
    app: hello-ci
spec:
  containers:
    - name: web
      image: hello-ci:v4
      ports:
        - containerPort: 3000
```

**Say:** this is the same information as `docker run -p 8081:3000 hello-ci:v4`.
The difference is that I am *describing* what I want in a file instead of
*commanding* it on a command line.

```bash
kubectl apply -f k8s/pod.yaml
kubectl get pods
```

Run `get pods` a few times. It ends at **`ImagePullBackOff`**.

```bash
kubectl describe pod hello-ci          # read the Events at the bottom
```

**Say two things:**

1. I wrote `hello-ci:v4`, but the node looked for
   `docker.io/library/hello-ci:v4`. An image name is an *address* — with no
   registry hostname, it means Docker Hub. My image was never there.
2. `Scheduled` **succeeded**. The machine was fine; only the image was missing.
   That is how you debug a stuck pod: no `Scheduled` event means no machine had
   room, `Scheduled` plus pull errors means the image or credentials are wrong.

**Say:** my image is in my Mac's Docker. The node is a separate container with
its own image store. They share nothing.

Fix it:

```bash
kind load docker-image hello-ci:v4 --name hello-lab
kubectl delete pod hello-ci
kubectl apply -f k8s/pod.yaml
kubectl get pods                       # 1/1 Running
kubectl describe pod hello-ci
```

**Say:** `kind load` copies the image from my Mac's Docker into the node. No
registry, no download — both are on this laptop. The Events now read
`Pulled: already present on machine`, then `Created`, then `Started`.

**Say:** in production the node pulls from ECR or Artifactory instead. That is
what a pipeline's Publish stage is for. Either way, the image must physically
reach the node.

---

## 3. Reach the app

```bash
kubectl get pods -o wide
```

**Say:** note the pod IP, `10.244.x.x`. That address exists only inside the
cluster — my Mac has no route to it. So I need a tunnel.

```bash
kubectl port-forward pod/hello-ci 8082:3000
```

Other tab:

```bash
curl -s http://localhost:8082/health
kubectl logs hello-ci
```

**Say:** `port-forward` opens port 8082 on my Mac and pipes it to port 3000 in
the pod. Read it as `local:pod`, same as Docker's `-p`.

**Important point to make:** this did **not** start Rails. Rails has been
running since the pod started — look at the timestamp in `kubectl logs`. The
tunnel only gave me a route to something already running, and it dies when I
Ctrl-C.

**Say:** and notice I never ran `docker run`. I described a pod, and the cluster
started the container for me. That is the real shift: with Docker I give a
command; with Kubernetes I state a desired result and the cluster issues the
command, then keeps watching.

Ctrl-C the port-forward.

---

## 4. Pod vs Deployment

```bash
kubectl delete pod hello-ci
kubectl get pods                       # gone, and it STAYS gone
```

**Say:** a bare pod is a one-off instruction. I asked for it once, Kubernetes
ran it, and now the request is finished. Nothing believes it should exist.

Now a Deployment. It is the same pod spec moved inside `template:`, plus a
replica count and a health check. `selector` is how it recognises its own pods.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hello-ci
spec:
  replicas: 1
  selector:
    matchLabels:
      app: hello-ci
  template:
    metadata:
      labels:
        app: hello-ci
    spec:
      containers:
        - name: web
          image: hello-ci:v3
          ports:
            - containerPort: 3000
          readinessProbe:
            httpGet:
              path: /health
              port: 3000
            initialDelaySeconds: 3
            periodSeconds: 5
```

```bash
kubectl apply -f k8s/deployment.yaml
kubectl get pods                       # the name is now generated
```

**Say:** I no longer choose pod names, because the Deployment will be creating
and destroying them for me.

```bash
kubectl delete pod <paste-the-generated-name>
kubectl get pods
```

**Point at the watch tab:** the old pod `Terminating` and a replacement already
being created, with a different suffix. About one second.

**Say:** the Deployment counts pods with the matching label, compares that to
`replicas: 1`, sees 0, and creates one. It never stops checking. That is why
you essentially never see a bare pod in production.

**Say:** and note the pod was not repaired, it was *replaced*. Anything you
need to keep has to live outside the pod.

---

## 5. Service — a stable address

**Say:** pod names change on every crash, deploy and scale-up, so nothing can
address a pod by name. A **label** is a sticky note on a pod. A **Service** is
a standing search for that note, plus a fixed address and a DNS name.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: hello-ci
spec:
  selector:
    app: hello-ci
  ports:
    - port: 80
      targetPort: 3000
```

```bash
kubectl apply -f k8s/service.yaml
kubectl get service hello-ci                    # note the CLUSTER-IP
kubectl get endpointslices -l kubernetes.io/service-name=hello-ci
```

**Say:** the endpoint list is the search result, made visible.

```bash
kubectl exec -it deployment/hello-ci -- curl -s http://hello-ci/health
```

**Say:** that request used the *name* `hello-ci`, resolved by cluster DNS to the
Service, forwarded to a pod. No pod names, no IPs. This is how services talk to
each other in a real cluster.

The full chain, if someone asks:

```
curl http://hello-ci/health
  -> cluster DNS resolves "hello-ci" to the Service ClusterIP
  -> Service forwards to one ready pod on port 3000
  -> Rails matches the /health route
  -> HealthController#show renders the JSON
```

**Why `exec` at all:** the ClusterIP and the name `hello-ci` only exist *inside*
the cluster network — my Mac cannot resolve either. So I need a client that
lives in the cluster, and one of my own pods is a convenient one because it has
`curl` installed. The pod is just a place to stand; the request still goes
through the Service, so the pod that *answers* may be a different one.

Scale up:

```bash
kubectl scale deployment hello-ci --replicas=3
kubectl get pods
kubectl get endpointslices -l kubernetes.io/service-name=hello-ci
```

**Say:** three addresses where there was one. Nobody told the Service about the
new pods — they were born with the right label and its search found them.

**Say:** three reasons for replicas — share the traffic, survive a crash, and
make zero-downtime deploys possible. That last one is next.

**Then edit `k8s/deployment.yaml` to `replicas: 3`.** `kubectl scale` changed
the cluster but not the file, and the next `apply` would scale it back down.
The file is the source of truth.

### 5a. Prove it load balances

Tab 2 — stream logs from all three pods at once (`--prefix` tags each line with
its pod name):

```bash
kubectl logs -f -l app=hello-ci --prefix --tail=1
```

Tab 1 — fire a handful of requests:

```bash
for i in 1 2 3 4 5 6; do kubectl exec deployment/hello-ci -- curl -s -o /dev/null http://hello-ci/health; done
```

**Point at tab 2:** `GET /health` lines appearing under **different pod names**.

**Say:** one address, three workers, distribution for free. Note it is roughly
round-robin, *not* load-aware — the Service has no idea which pod is busy. The
one thing it does respect is readiness: only pods passing their `/health` probe
are in the pool. Load-aware routing is what a service mesh adds on top.

### 5b. Prove a Service beats a port-forward

This is the clearest answer to "why do I need a Service when port-forward
already works".

```bash
kubectl get pods
kubectl port-forward pod/<pick-one-pod> 8082:3000
```

Other tab:

```bash
curl -s http://localhost:8082/health        # works
kubectl delete pod <that-same-pod>
curl -s http://localhost:8082/health        # empty / fails
```

**Say:** the tunnel died. It resolved that one pod once, at startup, and never
re-picks. Note that `port-forward deployment/...` has the same flaw — it just
chooses a pod for you, so you do not know which one to delete. (If you delete a
*different* pod, nothing breaks, which is confusing on stage. Target a named pod
so the break is guaranteed.)

Now the same event through the Service:

```bash
kubectl exec -it deployment/hello-ci -- curl -s http://hello-ci/health
kubectl get endpointslices -l kubernetes.io/service-name=hello-ci
```

**Say:** still works, and the endpoint list already swapped the dead IP for the
replacement's. **The tunnel broke, the Service did not.**

**Say:** and the deeper reason — a port-forward needs kubectl plus cluster
credentials, and only serves me on my laptop. An app calling another app has
none of that. All it can do is make an HTTP request to a name. That name is the
Service.

| | `port-forward` | Service |
| --- | --- | --- |
| For | a human debugging | apps calling each other |
| Lives | while the command runs | permanently |
| Reaches | one pod, picked once | all ready pods, continuously |
| Needs | kubectl + credentials | just an HTTP request |

Three levels of stability, worst to best: **pod IP** changes on every
replacement; **ClusterIP** is stable while the Service exists; the **DNS name**
never changes. Applications use the name.

### 5c. Optional: delete all three pods

```bash
kubectl delete pods -l app=hello-ci
kubectl get pods
```

**Be honest about this one:** with all three gone the Service has zero
endpoints, so requests **do** fail for 10–20 seconds while replacements boot and
pass their probes. Do not claim "it still works".

**Say:** Kubernetes recovered from losing every pod with no human involved —
that is what happens if a node dies at 3am. And the gap you just saw is exactly
why rolling updates exist: replacing everything at once means downtime.

For a genuine zero-downtime claim, delete them **one at a time** and curl
between each — two healthy pods always remain, so every request succeeds.

---

## 6. Rolling update, then rollback

Start a request loop in the second tab, using the CLUSTER-IP from step 5:

```bash
kubectl exec -it deployment/hello-ci -- sh -c \
  'while true; do curl -s http://<CLUSTER-IP>/health; echo; sleep 0.5; done'
```

It prints `"hello from image v3"` twice a second. Leave it running.

Now edit `k8s/deployment.yaml` to `image: hello-ci:v4`, then:

```bash
kind load docker-image hello-ci:v4 --name hello-lab
kubectl apply -f k8s/deployment.yaml
kubectl rollout status deployment/hello-ci
```

**Why both commands:** `apply` only *records* the new desired state and returns
instantly — `configured` does not mean any pod was replaced yet. `rollout
status` blocks until the rollout finishes, and **exits non-zero if it stalls**.
That exit code is what makes a pipeline's deploy stage meaningful; without it a
build goes green even when every new pod is stuck in `ImagePullBackOff`. In CI
you would add `--timeout=120s`.

Caveat worth knowing: `rollout status` reports on the *current* desired state,
so it can say "successfully rolled out" while running the old image. To know
what actually shipped, ask for the image:

```bash
kubectl get deployment hello-ci -o jsonpath='{.spec.template.spec.containers[0].image}'
```

**Point at the loop:** no failed requests, and the message changes v3 → v4. For
a few seconds you see **both**, because old and new pods serve at the same time.

**Say:** that mixed window is why deploys must be backward compatible. For those
seconds, two versions of the app are both live.

**Point at the watch tab:** new pods reach `Running` *before* old ones start
`Terminating`. Kubernetes starts a new pod, waits for its `/health` readiness
check, adds it to the Service, and only then removes an old one.

Roll back:

```bash
kubectl rollout undo deployment/hello-ci
```

**Point at the loop:** back to v3 in seconds. No rebuild, no pipeline run.

**Say:** this works only because v3 and v4 are separate immutable images that
both still exist. Reuse one tag for every build and rollback becomes "revert the
code and wait for CI" — minutes, during an outage.

### Read the warning aloud — it is the drift lesson

`rollout undo` prints:

```
Warning: resource deployments/hello-ci was previously managed with 'kubectl
apply'. Rolling back will not update the kubectl.kubernetes.io/
last-applied-configuration annotation ... Consider using 'kubectl apply' with
your previous configuration file instead.
```

**Say:** the rollback worked — the cluster is on v3. But `undo` only talks to the
cluster; **it did not edit my file**, which still says v4. So the next `apply`
would jump straight back to v4 and silently undo my rollback.

| | Version |
| --- | --- |
| Cluster is running | v3 |
| File on disk says | v4 |

**Say:** the file is a note saying what I want; the cluster is the room. `undo`
rearranged the room and left the note alone. Whoever reads the note next puts
the room back.

**Say:** so in a properly run system a rollback is a **git revert** — change the
tag in the file, commit, let the pipeline apply it. `rollout undo` is the 2am
emergency button: faster, and it works even when CI is broken. The discipline is
to reconcile the file afterwards.

Finish by making them agree again — either roll forward, or apply the file:

```bash
kubectl apply -f k8s/deployment.yaml          # file says v4, so cluster goes to v4
kubectl rollout status deployment/hello-ci
kubectl get deployment hello-ci -o jsonpath='{.spec.template.spec.containers[0].image}'
```

**What you should see:** `hello-ci:v4` — no drift left behind.

---

## Closing line

Jenkins builds and pushes the image. Kubernetes pulls it and keeps it running.
The image is the artifact that joins them: a commit identifies the source, an
image tag identifies the build, a Deployment identifies what is deployed.

---

## If it breaks

- `Unable to connect to the server` → `docker start hello-lab-control-plane`, wait 30s
- Wrong context → `kubectl config use-context kind-hello-lab`
- Unexpected `ImagePullBackOff` → you forgot `kind load` for that tag
- curl loop prints blank lines → use the CLUSTER-IP, not the name
- `apply` says `unchanged` → the file was not saved
- `pods "hello-ci" not found` on `port-forward` → the bare pod was deleted in
  step 4. Either recreate it with `kubectl apply -f k8s/pod.yaml`, or target the
  Deployment instead: `kubectl port-forward deployment/hello-ci 8082:3000`
- `error: unable to forward port ... pod not running` → the pod was replaced
  since you started the tunnel. Ctrl-C and point at the Deployment, not a pod
  name, so it survives pod churn
- `the server doesn't have a resource type "hello-ci-5c45..."` → you left out
  the resource type. Every command is
  `kubectl <verb> <resource-type> <name>`, e.g. `kubectl delete pod <name>`.
  The type is a fixed keyword (`pod`, `deployment`, `service` — see
  `kubectl api-resources`); only the name is yours
- `zsh: no such user or named directory: kubectl` → a stray `~` before the
  command
- `error: you must specify at least one command for the container` → `exec`
  needs a command after `--`, e.g.
  `kubectl exec -it deployment/hello-ci -- curl -s http://<CLUSTER-IP>/health`.
  Also note `-f` is not an `exec` flag; it means "file" for `apply` and
  "follow" for `logs`
- Three objects are all named `hello-ci` (the bare pod, the Deployment, the
  Service). Names only need to be unique per type, so the type word is what
  tells them apart. Prefer the `type/name` form, e.g. `deployment/hello-ci`
