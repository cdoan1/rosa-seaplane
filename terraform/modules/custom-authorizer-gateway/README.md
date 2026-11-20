# custom-authorizer-gateway

Public REST API whose authentication is the `seaplane-authorizer` Lambda
(REQUEST-type custom authorizer) instead of `AWS_IAM`. Phase 4 PoC of the
UI login flows design (`docs/preflight-and-ui-login-flows.md` /
`docs/poc/preflight-ui-login/` in rosa-seaplane-api).

## What it creates

- REST API (`CUSTOM` authorization, `{proxy+}` + root, OPTIONS mock for
  CORS preflights) → VPC Link v2 → internal ALB → platform-api pods
- The `seaplane-authorizer` Lambda (image built from rosa-seaplane-api)
  with a least-privilege role: read the linking table + logs
- The **linking table** (D-T4 schema: PK `sub`, SK `arn`) — PoC-owned
  here; production moves it to authz-storage with retention. Deletion
  protection follows `enable_retention` (wired to
  `authz_dynamodb_deletion_protection` by the regional config), so
  production RCs cannot lose the org↔account mappings to an accidental
  destroy; PITR and SSE are always on
- The PoC **console ALB** (see security notes below)

## Security notes (PoC limitations)

- **Console ALB is HTTP-only, open to 0.0.0.0/0.** The PoC web console is
  served over plain HTTP on a public internet-facing ALB. The PKCE token
  exchange and the gateway's CORS `Access-Control-Allow-Origin`
  (`http://<console-alb-dns>`) are both `http://`, so tokens are
  **unencrypted in flight** on the browser↔console and browser↔gateway
  legs. Acceptable for the PoC only. Before production: put CloudFront
  with an ACM cert in front of the console (mirroring `keycloak.tf`),
  redirect HTTP→HTTPS, and move the CORS origin to `https://`.
- **Gateway authorizer caching is off.** `authorizer_result_ttl_in_seconds
= 0`; every request invokes the Lambda. The Lambda keeps an in-process
  decision cache (keyed `(token, arn)`, TTL bounded by token validity), so
  this is a latency/cost concern only at load. Production should enable
  gateway-level caching with a 60–300s TTL once request rates and the
  link-revocation story are reconciled.

## Identity header parity

The integration maps the authorizer's context to the same headers the
`AWS_IAM` gateway produces (`X-Amz-Caller-Arn`, `X-Amz-Account-Id`,
`X-Amz-User-Id` from `context.authorizer.*`; `X-Amz-Source-Ip`,
`X-Amz-Request-Id` from native gateway context). `X-Amz-Principal-Org-Id`
is intentionally absent (decision D-T1). The authoritative table is
`identity-header-contract.md` in rosa-seaplane-api's PoC docs.

## Usage

```hcl
module "custom_authorizer_gateway" {
  source = "../../modules/custom-authorizer-gateway"

  regional_id            = var.regional_id
  vpc_id                 = module.vpc.vpc_id
  private_subnet_ids     = module.vpc.private_subnet_ids
  node_security_group_id = module.regional_cluster.node_security_group_id
  cluster_name           = module.regional_cluster.cluster_name

  authorizer_image_uri = "<ecr-uri>/seaplane-authorizer:<tag>"
  rh_token_issuer      = "https://<cloudfront-hostname>"
  rh_token_jwks_url    = "https://<cloudfront-hostname>/realms/poc/protocol/openid-connect/certs"
}
```

The platform API also needs `LINKING_TABLE`, `RH_TOKEN_ISSUER`,
`RH_TOKEN_JWKS_URL` (and optionally `RH_TOKEN_AUDIENCE`) pointing at the
same values, so its linking endpoints share the authorizer's
configuration.
