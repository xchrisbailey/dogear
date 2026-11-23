# Plain HTTP to a Server on Tailscale

Spec #1 made Dogear HTTPS only so a password never travels unencrypted. Most people reach a home Grimmory Server over Tailscale, where the Server answers plain HTTP on its tailnet address and HTTPS needs extra setup (`tailscale cert` or `tailscale serve`). Tailscale already encrypts everything between devices with WireGuard, so HTTP there doesn't expose the password.

Dogear accepts `http://` only for a Tailscale address and still refuses it anywhere else (`ServerAddress.isTailnet`):

- a MagicDNS name ending `.ts.net`, or a bare machine name (`http://grimmory:6060`);
- an address in 100.64.0.0/10 or fd7a:115c:a1e0::/48.

An address typed without a scheme means HTTP for those and HTTPS for anything else. `https://` still works for a tailnet Server set up with a certificate.

App Transport Security allows the same set: `NSAllowsLocalNetworking` for bare names, an `NSExceptionDomains` entry for `ts.net` and its subdomains, and numeric IP addresses, which ATS doesn't cover on iOS 10 and later.

## Considered Options

- **A "Use HTTPS" switch on sign-in for any address**: simpler to explain, but it would send a password in the clear on a coffee-shop network to a Server that isn't on a tailnet.
- **Also allow `.local` and private LAN addresses**: not asked for, and Wi-Fi on a LAN isn't encrypted end to end.

## Consequences

- A bare machine name is trusted as MagicDNS. On a LAN without Tailscale it could be an ordinary unencrypted host; that's the price of supporting short names.
- 100.64.0.0/10 is also carrier-grade NAT space, but a phone can't normally reach a Server at one of those addresses except over Tailscale, so in practice it is a tailnet address.
