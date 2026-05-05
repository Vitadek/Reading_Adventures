# Reading Adventures — Setup & Deployment

A quick guide to getting this running, whether on your laptop or a real server.

---

## 1. Set up your `.env`

```bash
cp .env.example .env
```

Now edit `.env`. Here's what each value is for:

### `DB_NAME`, `DB_USER`, `DB_PASSWORD`
Postgres credentials. The container creates the database from these on first boot.

- `DB_NAME` and `DB_USER` can be anything (`reading_adventures` / `parent` is fine).
- `DB_PASSWORD` should be a real password. Generate one with:
  ```bash
  openssl rand -base64 24
  ```
- **You only need to set these once.** If you change `DB_PASSWORD` later, Postgres won't accept it because the password got baked in on first boot — you'd need to either reset the volume (`docker compose down -v`, which deletes data) or change the password from inside Postgres with `ALTER USER`.

### `OPENAI_API_KEY`
Get one at [platform.openai.com/api-keys](https://platform.openai.com/api-keys). Make sure your account has a few dollars of credit — generating a worksheet costs roughly **$0.001 with `gpt-4o-mini`**, so $5 of credit is thousands of worksheets.

### `OPENAI_MODEL`
- `gpt-4o-mini` (default) — fast, cheap, plenty good for kid worksheets.
- `gpt-4o` — noticeably more thoughtful questions, ~10x the cost. Try this if the mini-model's questions feel generic.

You can change this any time and just restart the `web` container — no rebuild needed.

### `MAX_BOOK_WORDS`
Hard cap on how much of a book gets sent to the LLM. Default `100000` fits any kids' chapter book whole. Don't raise this above ~110,000 unless you're using a model with a bigger context window.

### `FLASK_SECRET_KEY`
Used to sign Flask session cookies (mainly for flash messages here). Generate a real one:

```bash
python3 -c "import secrets; print(secrets.token_hex(32))"
```

Paste the output as the value. Never commit this.

---

## 2. Run it locally

```bash
docker compose up --build
```

Open <http://localhost:5000>.

The first boot takes a minute (Postgres initializing, Python deps installing). Subsequent starts are quick:

```bash
docker compose up        # foreground
docker compose up -d     # background
docker compose logs -f web   # follow web logs
docker compose down      # stop everything
```

Your data lives in:
- `./uploads/` — uploaded EPUBs
- A Docker named volume `postgres_data` — quizzes & book records

---

## 3. Deploy to a server

This is a small app for personal use, so a single cheap VPS is the right shape. The cheapest tier on Hetzner, DigitalOcean, or similar (~$5/month) is more than enough.

### Option A — Just you and your family (simplest)

Use **[Tailscale](https://tailscale.com)**. The app stays on a private network only your devices can reach. No HTTPS cert, no domain, no reverse proxy needed.

1. Spin up any small Linux VPS.
2. Install Docker:
   ```bash
   curl -fsSL https://get.docker.com | sh
   ```
3. Install Tailscale on the server **and** on each device that should access it:
   ```bash
   curl -fsSL https://tailscale.com/install.sh | sh
   sudo tailscale up
   ```
4. `git clone` (or `scp`) the project to the server, set up `.env`, and run:
   ```bash
   docker compose up -d
   ```
5. From any device on your tailnet, visit `http://<server-tailscale-name>:5000`. Done.

This is genuinely the path of least resistance for a "just for my family" app.

### Option B — Public on the internet with HTTPS

If you want a real domain like `reading.yourdomain.com`, put **Caddy** in front. Caddy gets you HTTPS automatically.

1. Point your domain's DNS A record at the server's IP.
2. Add a `Caddyfile` next to `docker-compose.yml`:
   ```caddy
   reading.yourdomain.com {
       reverse_proxy web:5000
   }
   ```
3. Add a Caddy service to `docker-compose.yml`:
   ```yaml
     caddy:
       image: caddy:2-alpine
       restart: unless-stopped
       ports:
         - "80:80"
         - "443:443"
       volumes:
         - ./Caddyfile:/etc/caddy/Caddyfile:ro
         - caddy_data:/data
         - caddy_config:/config
       depends_on:
         - web

   volumes:
     postgres_data:
     caddy_data:
     caddy_config:
   ```
4. Remove (or comment out) the `ports: - "5000:5000"` line on the `web` service so it's only reachable through Caddy.
5. `docker compose up -d`. Caddy will fetch a Let's Encrypt cert on first request.

⚠️ **If you go this route, add basic auth.** This app has no login system — anyone who finds the URL can upload books and burn your OpenAI credit. Either keep it on Tailscale (Option A) or add Caddy basic auth:

```caddy
reading.yourdomain.com {
    basic_auth {
        you $2a$14$...   # generate with: caddy hash-password
    }
    reverse_proxy web:5000
}
```

---

## 4. Backups

Two things are worth backing up:

**The uploads folder** is just files on disk:
```bash
tar -czf uploads-backup-$(date +%F).tar.gz ./uploads
```

**The Postgres volume** is a Docker volume. Quickest backup:
```bash
docker compose exec db pg_dump -U "$DB_USER" "$DB_NAME" > db-backup-$(date +%F).sql
```

Stick those two commands in a weekly cron job and you're covered. To restore the DB:
```bash
cat db-backup-2026-05-04.sql | docker compose exec -T db psql -U "$DB_USER" "$DB_NAME"
```

---

## 5. Updating

When you change code:
```bash
docker compose up -d --build web
```

When you change just `.env`:
```bash
docker compose up -d   # no rebuild needed
```

When something is weird:
```bash
docker compose logs -f web
docker compose logs -f db
```

---

## Common pitfalls

| Symptom | Fix |
|---|---|
| `web` exits immediately, logs say "could not connect to db" | The `depends_on: condition: service_healthy` should prevent this, but if you hit it, just `docker compose up` again — Postgres is just slow on cold start. |
| Quiz generation hangs then 504s | Your book is probably hitting the model's context limit. Lower `MAX_BOOK_WORDS` or upgrade to `gpt-4o`. |
| Uploads page says "No file uploaded" but you picked one | The file is over 50 MB. Adjust `MAX_UPLOAD_BYTES` in `app.py`. |
| Postgres password change isn't taking effect | First-boot password is baked into the volume. `docker compose down -v` wipes it (deletes data!) or change it via `ALTER USER` from inside the container. |
| OpenAI returns a 401 | Key is wrong, expired, or the account has no credit. |
