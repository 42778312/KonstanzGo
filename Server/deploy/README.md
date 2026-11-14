# Running KonstanzGo Live

One Docker container on one small Linux VM, reached only through a Cloudflare Tunnel. No open ports.
One instance only: two would double the traffic to EFA-BW.

## On the Mac (local)

```bash
cd Server/deploy
docker compose up --build
curl -s http://127.0.0.1:8080/v1/health
curl -s --compressed http://127.0.0.1:8080/v1/live/snapshot
curl -s http://127.0.0.1:8080/metrics
```

The first sweep takes about 15 s; until then the snapshot says `"upstream":"degraded"` with no trips.

## On the server (once)

Ubuntu 24.04, 2 vCPU / 4 GB, in Germany. SSH key login only, provider firewall with no inbound ports except SSH
from your IP.

```bash
# Docker, from Docker's own apt repository
sudo apt-get update && sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list
sudo apt-get update && sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo usermod -aG docker $USER   # log out and in again

# The app
mkdir -p ~/live && cd ~/live
# copy docker-compose.yml and .env.example here (scp from your Mac), then:
cp .env.example .env && nano .env   # LIVE_TAG=server-v1.0.0, CONTACT_EMAIL, CLOUDFLARE_TUNNEL_TOKEN
docker compose --profile tunnel pull
docker compose --profile tunnel up -d
```

The image is private on GitHub Container Registry until you make it public; to pull a private one, log in once with
a token that has `read:packages`: `docker login ghcr.io -u 42778312`.

## Everyday

| Task | Command |
|---|---|
| Status | `docker compose ps` (the `live` service shows `healthy`) |
| Logs | `docker compose logs -f --tail 200 live` |
| Update | set `LIVE_TAG` in `.env` to the new tag, then `docker compose --profile tunnel up -d` |
| Roll back | set `LIVE_TAG` back to the previous tag, then `docker compose --profile tunnel up -d` |
| Kill switch | `LIVE_UPSTREAM_ENABLED=false` in `.env`, then `docker compose up -d live` |
| Metrics | `curl -s http://127.0.0.1:8080/metrics` (on the server only) |
| Stop | `docker compose --profile tunnel down` |

A release: push a tag `server-vX.Y.Z`; CI builds the image and pushes `ghcr.io/42778312/konstanzgo-live:server-vX.Y.Z`.

## Cloudflare (you, in the dashboard)

1. Add the domain, create a Tunnel (Zero Trust > Networks > Tunnels), route `api.<domain>` to `http://live:8080`, copy
   the token into `.env`.
2. Cache Rule: hostname `api.<domain>` and path starts with `/v1/` → eligible for cache, respect origin cache headers.
3. Rate limiting rule: `/v1/*`, 120 requests per minute per IP, block for 1 minute.
4. WAF custom rule: path equals `/metrics` → block. (The server also refuses `/metrics` when Cloudflare headers are present.)
5. Logs: keep request logging off, or at least don't link IPs to anything, so the app can keep "Data Not Collected".

Check: `curl -sI https://api.<domain>/v1/live/snapshot` twice; the second shows `cf-cache-status: HIT`.

## Monitoring (you)

UptimeRobot or Better Stack: check `https://api.<domain>/v1/health` every minute, with push alerts to your phone.
Add a keyword alert when `snapshotAgeSeconds` is above 120 during service hours (05:00–01:30).
