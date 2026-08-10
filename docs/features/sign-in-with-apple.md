# Sign in with Apple

## User outcome

A user can establish and restore a Sales Ping account using Apple's native authorization UI without creating a password.

## Behavior

- iOS requests name and email with a SHA-256 nonce.
- The Apple identity token and raw nonce are posted to Better Auth.
- Better Auth validates issuer, audience, age, signature, and nonce.
- The Better Auth bearer session is stored in the device Keychain.
- When Apple omits email on a later authorization, the Worker may recover it only from the already-linked local Better Auth account.
- Sign out invalidates the server session and clears Keychain state.

## Acceptance criteria

- A first-time authorized Apple user creates one D1 user and account.
- A returning Apple user resolves to the same user.
- An invalid token, nonce, issuer, or audience is rejected.
- Relaunch restores a valid session and rejects an expired one.
- No Apple private key or Better Auth secret is present in the app bundle or git.
