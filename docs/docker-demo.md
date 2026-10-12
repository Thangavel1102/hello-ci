# Docker Live Demo — Runbook

A 7-minute demo. Four beats: build, run, prove immutability, publish.

## Before you present

Do these so nothing slow or surprising happens on stage.

```bash
# 1. Rancher Desktop must be running (~40s to boot the VM)
docker version          # must print a Server: section

# 2. Warm the cache so the live build is seconds, not minutes
cd ~/Work/ci-lab/hello-ci
docker build -t hello-ci:demo .

# 3. Free the ports we use
lsof -nP -iTCP:8081 -sTCP:LISTEN     # must print nothing

# 4. Make the message obviously "before"
#    app/controllers/health_controller.rb -> message: "hello from laptop"

# 5. Big terminal font. Light theme if the projector is washed out.
```

Have two terminal tabs open: **left** for commands, **right** for the running
container.

---

## Beat 1 — Build the image (90s)

Show `Dockerfile` on screen first, then:

```bash
docker build -t hello-ci:demo .
```

Say: every line became a layer; all of it ran now, at build time. The last
line, `CMD`, is the only one that runs when the container starts.

```bash
docker images hello-ci
```

**Point at:** the size (~628MB) and the fact that it is one artifact.

---

## Beat 2 — Run it (60s)

In the **right** tab:

```bash
docker run --rm -p 8081:3000 hello-ci:demo
```

**Point at:** `Listening on http://0.0.0.0:3000` and `PID: 1`. Inside its own
container, your app is process number one.

In the **left** tab:

```bash
curl -s http://localhost:8081/health
```

Say: port 8081 on my Mac forwards to 3000 inside the container. Nothing is
installed on this laptop for this app — no Ruby, no gems.

---

## Beat 3 — The immutability proof (2 min) — the key moment

Leave the container running. Edit the message in
`app/controllers/health_controller.rb` live, on screen:

```ruby
message: "hello from the rebuilt image"
```

Save, then immediately:

```bash
curl -s http://localhost:8081/health
```

**It still returns the OLD string.** Pause here and let that land. Ask the
room why.

Then rebuild and swap:

```bash
docker build -t hello-ci:demo2 .          # watch the CACHED lines fly by
# Ctrl-C the running container in the right tab
docker run --rm -p 8081:3000 hello-ci:demo2
curl -s http://localhost:8081/health      # now the new string
```

Two takeaways to say out loud: code is baked in, so a change needs a rebuild,
not a restart. And the rebuild took seconds because only the layer that copies
code was invalidated — `bundle install` was cached.

---

## Beat 4 — Publish and retrieve (2 min)

```bash
docker tag hello-ci:demo2 thangavelp1102/hello-ci:demo
docker push thangavelp1102/hello-ci:demo
```

Say: the name is an address. No registry hostname means Docker Hub.

Then delete every local copy and bring it back:

```bash
docker rmi hello-ci:demo2 thangavelp1102/hello-ci:demo
docker images | grep hello-ci             # gone
docker run --rm -p 8081:3000 thangavelp1102/hello-ci:demo
```

**Point at:** `Unable to find image ... locally`, then the pull, then the app
booting. That is the whole deployment model: build once, push, and any machine
with Docker can run it.

---

## Closing line

Jenkins runs the build and the push. Kubernetes does the pull and the run.
The image is the artifact that connects them.

---

## Fallback if the live demo breaks

Have the screenshots below on standby and narrate from them. Most likely
failures: the daemon is not running (open Rancher Desktop), port 8081 is taken
(use 8084 everywhere), or the network is down (skip Beat 4 entirely).

## Screenshots to capture in advance

Put these in `docs/img/`. Crop to the terminal; no desktop clutter.

| # | Capture | Slide it supports |
| --- | --- | --- |
| 1 | `docker build` output, first run, `bundle install` taking minutes | Layers and build time |
| 2 | `docker build` output, second run, many `CACHED` lines | Build caching payoff |
| 3 | `docker images` showing v1 and v2 side by side | Tags are labels on images |
| 4 | Container boot log, with `PID: 1` visible | What running in a container means |
| 5 | The two curls around the edit: old string, then new | **The immutability moment** |
| 6 | `docker push` with layers and the final digest line | Publishing |
| 7 | `Unable to find image locally` followed by the pull | Pull-and-run on a fresh machine |
| 8 | The Zscaler `CertificateFailureError` from the failed build | War story (a) |
| 9 | `curl -i` returning the Jetty 404 with its `Server:` header | War story (b) |

Screenshots 5, 8, and 9 matter most. 5 is the conceptual core; 8 and 9 are the
ones people remember because they have hit the same walls.
