# terraform-landing-ru — crystolia.ru landing (D4.1)

Stands up `crystolia.ru` on S3 + CloudFront using the reusable
[`../modules/landing-domain`](../modules/landing-domain) module. Mirrors the
proven `crystolia.com` stack and adds a per-domain ACM cert + an edge function
(`www→apex` 301 and `/ → /ru`).

State: `s3://crystolia-tf-state-main/landing-ru/terraform.tfstate` (separate
from `.com`'s `landing/` key — fully isolated).

## Execution sequence (each step is gated/approved separately)

1. **Provision (no public DNS):**
   ```
   terraform init
   terraform apply            # go_live defaults to false
   ```
   Creates: bucket `crystolia-landing-ru`, ACM cert (apex+www, DNS-validated in
   the .ru zone), CloudFront distro + edge function. The apex/www A-ALIAS records
   are **not** created yet, so nothing resolves at crystolia.ru.

2. **Deploy content** (separate, from `crystolia-app/landing`):
   ```
   ./deploy-landing.sh --bucket crystolia-landing-ru        # (script needs the --bucket arg added)
   ```

3. **Validate on the CloudFront domain (before DNS):**
   ```
   curl -sI https://<cloudfront_domain>/ -H 'Host: crystolia.ru'        # 200, Russian home
   curl -sI https://<cloudfront_domain>/ -H 'Host: www.crystolia.ru'    # 301 -> https://crystolia.ru
   ```

4. **Go live (DNS):**
   ```
   terraform apply -var go_live=true     # adds apex + www A-ALIAS -> CloudFront
   ```

## Rollback
- Before step 4: `terraform destroy` (or just don't go live) — zero user impact (no DNS points here).
- After step 4: `terraform apply -var go_live=false` removes the A-ALIAS records → crystolia.ru returns to NXDOMAIN (its prior, not-serving state).

## Notes
- `api`/`admin` (Lightsail Caddy) are untouched.
- Backend CORS for crystolia.ru is a separate later step (edit the box's
  `/opt/crystolia/backend/.env.demo` + restart) — not part of this stack.
