# Hardened three-tier NGINX Compose stack

This is a runnable demonstration with three NGINX services named `frontend`, `backend`, and `database`. The third service is **not a real database**—NGINX cannot safely replace PostgreSQL, MySQL, or another database engine. It exists only to demonstrate data-tier network isolation. Replace it with the real database image and grant only the backend access to the `data` network.

## Run

Requirements: Docker Engine with Compose v2.

```sh
docker compose config --quiet
docker compose pull
docker compose up -d
docker compose ps
curl --fail http://127.0.0.1:8080/
curl --fail http://127.0.0.1:8080/api/
curl --fail http://127.0.0.1:8080/api/data/
```

Stop it with:

```sh
docker compose down
```

Set another loopback port with `FRONTEND_PORT=8081 docker compose up -d`. The default bind is deliberately `127.0.0.1`, not every host interface. To expose this publicly, terminate TLS in a trusted ingress/load balancer and apply its firewall policy; do not simply change the bind address without doing that work.

## Security properties

- Runs as fixed non-root UID/GID `101:101` on unprivileged port 8080.
- Drops every Linux capability and forbids privilege escalation.
- Uses read-only root filesystems and read-only bind mounts; only a small `noexec,nosuid,nodev` tmpfs is writable.
- Applies CPU, memory, process, log-size, timeout, and request-size limits.
- Publishes only the frontend, on loopback. Backend and data tier use `expose`, which does not publish host ports.
- Uses two `internal` networks. Frontend has no route to the data tier; the data tier has no route to the edge tier or outside networks. Backend is the only bridge between tiers.
- Uses Docker's default seccomp and AppArmor/SELinux integration instead of disabling either.
- Pins the multi-platform NGINX image by digest. The selected digest resolved to NGINX 1.31.6 / Alpine 3.24 when this project was created on 2026-09-22.

## Production checklist

1. Replace the demo `database` service with an actual database, keep it only on `data`, use a named volume with narrowly scoped ownership, and load credentials through Compose secrets—not environment variables or source control.
2. Authenticate and authorize backend requests. Network segmentation is not application authorization.
3. Terminate TLS at the frontend or an external ingress. Configure trusted proxy IPs before trusting forwarded client headers.
4. Scan the exact image digest in CI, generate an SBOM, and update the digest on a defined patch cadence. A digest prevents surprise changes; it does not make an old image safe forever.
5. Enable Docker rootless mode or user-namespace remapping on the host where feasible, keep Docker Engine and the kernel patched, and restrict access to the Docker socket.
6. Add an explicit host firewall policy. Compose network isolation does not replace host/network firewalls.
7. Tune the sample resource and rate limits against measured traffic before production use.

## Useful verification

```sh
# Effective Compose model
docker compose config

# User, capabilities, read-only root, and security options
docker inspect secure-nginx-stack-frontend-1 \
  --format '{{json .Config.User}} {{json .HostConfig.CapDrop}} {{.HostConfig.ReadonlyRootfs}} {{json .HostConfig.SecurityOpt}}'

# Only the frontend should have a published port
docker compose ps

# Frontend is not attached to the data network; database is not attached to edge
docker inspect secure-nginx-stack-frontend-1 --format '{{json .NetworkSettings.Networks}}'
docker inspect secure-nginx-stack-database-1 --format '{{json .NetworkSettings.Networks}}'
```

Compose project-derived container names can differ if you use `--project-name`; use `docker compose ps -q SERVICE` to obtain exact IDs in scripts.
