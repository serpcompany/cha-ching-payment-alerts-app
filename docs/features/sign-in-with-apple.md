# Sign in with Apple

## User outcome

A user can establish and restore a Cha-Ching account using Apple's native authorization UI without creating a password.

## Behavior

- iOS requests name and email with a SHA-256 nonce.
- The Apple identity token and raw nonce are posted to Better Auth.
- Better Auth validates issuer, audience, age, signature, and nonce.
- The Better Auth bearer session is stored in the device Keychain.
- When Apple omits email on a later authorization, the Worker may recover it only from the already-linked local Better Auth account.
- Sign out invalidates the server session and clears Keychain state.

## Local Simulator development

Everyday Simulator work does not require an Apple Account. A Debug build on an
iOS Simulator displays **Use local Simulator account**. That action creates an
anonymous Better Auth session against the local Worker and stores its bearer
token in the Simulator Keychain.

This is a development session, not a fake Apple credential:

- the iOS entry point is excluded from Release and device builds at compile time;
- the Better Auth anonymous endpoint is registered only when
  `ENVIRONMENT=development` and `PUBLIC_BASE_URL` uses a loopback host;
- the Worker also rejects the endpoint unless the incoming request uses a
  loopback host, so exposing local Wrangler through a tunnel does not expose it;
- local Wrangler persists its own D1 state under `backend/.wrangler/state`;
- Apple IDs and passwords never belong in `.env`, `.dev.vars`, launch arguments,
  or source control;
- production and preview acceptance still use real Sign in with Apple.

See [Local Simulator authentication](../development/simulator-auth.md) for the
setup and test matrix. The boundary decision is recorded in
[ADR-0004](../adr/0004-local-simulator-authentication.md).

## Acceptance criteria

- A first-time authorized Apple user creates one D1 user and account.
- A returning Apple user resolves to the same user.
- An invalid token, nonce, issuer, or audience is rejected.
- Relaunch restores a valid session and rejects an expired one.
- No Apple private key or Better Auth secret is present in the app bundle or git.
- A Debug Simulator can create and restore a local Better Auth session without
  an Apple Account.
- The local session endpoint is absent on staging, preview, and production URLs.
