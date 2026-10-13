# Docker Demo — Image Lifecycle

Build → run → tag → push → delete → pull → run. About 8 minutes.

Run everything from `/Users/tp002/Work/ci-lab/hello-ci`.

---

## Before you present

```bash
# Rancher Desktop must be running
docker version                       # must print a Server: section

# Warm the cache so the live build takes seconds, not minutes
docker build -t hello-ci:v4 .

# Then set the message back to v3 so the edit is visible on stage:
# app/controllers/health_controller.rb -> message: "hello from image v3"

# Port must be free (a stray Java/Jetty process likes 8080; we use 8081)
lsof -nP -iTCP:8081 -sTCP:LISTEN     # must print nothing

# Still logged in to Docker Hub?
docker login -u thangavelp1102       # only if the push later asks
```

Big terminal font. Two tabs: **left** for commands, **right** spare.

---

## 1. What we already have (30s)

```bash
docker images | grep hello-ci
```

**Say:** three versions of the same app, side by side. Each is a separate,
immutable artifact. This is what makes a rollback instant instead of a rebuild.

---

## 2. Build a new version (90s)

Show `Dockerfile` on screen. Edit the message live:

```ruby
message: "hello from image v4"
```

```bash
docker build -t hello-ci:v4 .
```

**Point at:** the `CACHED` lines flying past. Only the layer that copies code
was rebuilt — `bundle install` was reused.

**Say:** everything in the Dockerfile ran now, at build time. The last line,
`CMD`, is the only thing that runs when a container starts.

---

## 3. Run it and look inside (2 min)

```bash
docker run -d -p 8081:3000 --name hello hello-ci:v4
docker ps
curl -s http://localhost:8081/health
docker logs hello
```

**Say:** `-d` runs it in the background. `-p 8081:3000` maps port 8081 on my
Mac to port 3000 inside the container.

**Point at:** `PID: 1` in the logs — inside its own container, the app is
process number one. And nothing for this app is installed on this laptop: no
Ruby, no gems.

Optional, if asked how to debug a container:

```bash
docker exec -it hello bash           # ls, cat app/controllers/health_controller.rb, exit
```

The code inside is the frozen copy from build time, not the file on my Mac.

---

## 4. Retag for the registry (60s)

```bash
docker tag hello-ci:v4 thangavelp1102/hello-ci:v4
docker images | grep hello-ci
```

**Point at:** both names share the same IMAGE ID. Two labels, one image —
nothing was copied.

**Say:** the image name is an *address*. No registry hostname means Docker Hub.
A dot, a colon, or `localhost` in the first part names the registry — that is
how the same commands target ECR or Artifactory.

---

## 5. Push (90s)

```bash
docker push thangavelp1102/hello-ci:v4
```

**Point at:** layers marked `Mounted from library/ruby` finish instantly —
Docker Hub already stores those base layers, so only my own layers upload.
Ends with a `digest: sha256:...` line.

---

## 6. Delete every local copy (60s)

```bash
docker stop hello && docker rm hello
docker rmi hello-ci:v4 thangavelp1102/hello-ci:v4
docker images | grep hello-ci
```

**Point at:** the first `rmi` prints only `Untagged`. The second prints
`Untagged` **and** `Deleted` — an image survives until its last tag is gone.

`v4` is now gone from this machine. `v1`, `v2`, `v3` are still here.

---

## 7. Pull it back and run (2 min)

```bash
docker run --rm -p 8081:3000 thangavelp1102/hello-ci:v4
```

**Point at:** `Unable to find image 'thangavelp1102/hello-ci:v4' locally`, then
the pull, then Puma booting.

```bash
curl -s http://localhost:8081/health
```

**Closing line:** build once, push once, and any machine with Docker can run
it. No Ruby, no gems, no source code. That is the whole deployment model —
and it is exactly what Kubernetes does for you on every node.

Ctrl-C to finish (`--rm` cleans up the container).

---

## If something breaks

| Symptom | Cause | Fix |
| --- | --- | --- |
| `Cannot connect to the Docker daemon` | Rancher Desktop not running | Open it, wait ~40s |
| `curl` returns HTML with `Server: Jetty` | Another process owns the port | Use 8084 everywhere |
| `denied: requested access to the resource is denied` | Not logged in, or token is read-only | `docker login -u thangavelp1102` with a Read & Write token |
| Push hangs | Slow corporate network | Skip to step 7 using the already-pushed `:v2` tag |

Worst case, narrate from screenshots. The two that carry the demo are the
`CACHED` build output and `Unable to find image locally` followed by the pull.
