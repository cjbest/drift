#!/bin/bash
# Shared signing preflight. Source this file; it never chooses a certificate.

drift_require_signing_identity() {
  local kind="${1:-development}" identity_name cert_dir cert_file fingerprint subject
  local cert_team cert_owner found=0
  if [[ ! "${DRIFT_SIGNING_IDENTITY:-}" =~ ^[A-Fa-f0-9]{40}$ ]]; then
    echo "Set DRIFT_SIGNING_IDENTITY to the SHA-1 of an explicitly chosen personal signing certificate." >&2
    return 1
  fi
  if [[ ! "${DRIFT_APPLE_TEAM_ID:-}" =~ ^[A-Z0-9]{10}$ ]]; then
    echo "Set DRIFT_APPLE_TEAM_ID to the verified personal Apple Developer Team ID." >&2
    return 1
  fi
  # This is the company team previously used for local development. Drift's
  # releases and subsequent development builds must use the owner's own team.
  if [[ "$DRIFT_APPLE_TEAM_ID" == "7DGN24C3GR" ]]; then
    echo "The Substack Apple Developer team cannot be used for Drift signing." >&2
    return 1
  fi
  identity_name="$(/usr/bin/security find-identity -v -p codesigning |
    /usr/bin/awk -v wanted="$DRIFT_SIGNING_IDENTITY" 'toupper($2) == toupper(wanted) {
      sub(/^[^"]*"/, ""); sub(/"[[:space:]]*$/, ""); print
    }')" || return 1
  if [[ -z "$identity_name" || "$identity_name" == *$'\n'* ]]; then
    echo "The selected certificate must identify exactly one valid keychain signing identity." >&2
    return 1
  fi
  case "$kind:$identity_name" in
    development:"Apple Development:"*|development:"Developer ID Application:"*|developer-id:"Developer ID Application:"*|distribution:"Apple Distribution:"*|distribution:"iPhone Distribution:"*) ;;
    *)
      echo "The selected certificate is not valid for the requested signing type ($kind)." >&2
      return 1
      ;;
  esac

  # Inspect the actual public certificate, not just its editable keychain label.
  # Only public certificates are read; private keys and passwords stay in Keychain.
  cert_dir="$(mktemp -d "${TMPDIR:-/tmp}/drift-signing.XXXXXX")" || return 1
  if ! /usr/bin/security find-certificate -a -c "$identity_name" -p > "$cert_dir/certificates.pem"; then
    rm -rf "$cert_dir"
    return 1
  fi
  /usr/bin/awk -v directory="$cert_dir" '
    /-----BEGIN CERTIFICATE-----/ { n++; file = directory "/certificate-" n ".pem" }
    file { print > file }
    /-----END CERTIFICATE-----/ { close(file); file = "" }
  ' "$cert_dir/certificates.pem"
  for cert_file in "$cert_dir"/certificate-*.pem; do
    [[ -f "$cert_file" ]] || continue
    fingerprint="$(/usr/bin/openssl x509 -in "$cert_file" -noout -fingerprint -sha1 |
      /usr/bin/sed 's/.*=//; s/://g')" || continue
    if [[ "$(printf '%s' "$fingerprint" | /usr/bin/tr '[:lower:]' '[:upper:]')" != \
          "$(printf '%s' "$DRIFT_SIGNING_IDENTITY" | /usr/bin/tr '[:lower:]' '[:upper:]')" ]]; then
      continue
    fi
    subject="$(/usr/bin/openssl x509 -in "$cert_file" -noout -subject -nameopt sep_multiline,sname)" || break
    cert_team="$(printf '%s\n' "$subject" | /usr/bin/sed -n 's/^[[:space:]]*OU[[:space:]]*=[[:space:]]*//p')"
    cert_owner="$(printf '%s\n' "$subject" | /usr/bin/sed -n 's/^[[:space:]]*O[[:space:]]*=[[:space:]]*//p')"
    if [[ "$(printf '%s' "$cert_owner" | /usr/bin/tr '[:upper:]' '[:lower:]')" == *substack* ]]; then
      echo "Substack-owned certificates cannot be used for Drift signing." >&2
      break
    fi
    if [[ "$cert_team" != "$DRIFT_APPLE_TEAM_ID" ]]; then
      echo "The certificate's actual Team ID does not match DRIFT_APPLE_TEAM_ID." >&2
      break
    fi
    found=1
    break
  done
  rm -rf "$cert_dir"
  if [[ "$found" != 1 ]]; then
    echo "Personal signing certificate verification failed; no build was signed." >&2
    return 1
  fi
  DRIFT_APPLE_IDENTITY_NAME="$identity_name"
  export DRIFT_APPLE_IDENTITY_NAME
}
