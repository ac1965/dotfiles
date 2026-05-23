#!/bin/bash
# biometric_auth.sh — LocalAuthentication経由で生体認証し、
#                     成功時にKeychainからパスフレーズを取得してfd:3に渡す
# 依存: swift (Xcode CLT), security コマンド
set -euo pipefail

SERVICE="com.encrypt.aes256gcm"
ACCOUNT="${1:-default}"

# ── Swift ワンライナーで LocalAuthentication を呼ぶ ─────────────
# 標準出力に "OK" または "FAIL: <reason>" を返す
AUTH_RESULT=$(swift <(cat <<'SWIFT'
import LocalAuthentication
import Foundation

let ctx = LAContext()
var err: NSError?

guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err) else {
    print("FAIL: \(err?.localizedDescription ?? "Biometrics unavailable")")
    exit(1)
}

let sem = DispatchSemaphore(value: 0)
var authOK = false
var authErr: String = ""

ctx.evaluatePolicy(
    .deviceOwnerAuthenticationWithBiometrics,
    localizedReason: "Decrypt encrypted file"
) { success, error in
    authOK = success
    authErr = error?.localizedDescription ?? ""
    sem.signal()
}
sem.wait()

if authOK {
    print("OK")
} else {
    print("FAIL: \(authErr)")
    exit(1)
}
SWIFT
) 2>/dev/null)

if [ "$AUTH_RESULT" != "OK" ]; then
  echo "❌ Biometric authentication failed: $AUTH_RESULT" >&2
  exit 1
fi

# ── 認証成功 → Keychainからパスフレーズ取得 ─────────────────────
# -w: パスワードのみ出力（プロンプトなし）
PASS=$(security find-generic-password \
  -s "$SERVICE" \
  -a "$ACCOUNT" \
  -w 2>/dev/null) || {
    echo "❌ Passphrase not found in Keychain. Run keychain_store.sh first." >&2
    exit 1
  }

# fd:3 に書き出して呼び出し元へ渡す
exec 3<<<"$PASS"

# メモリクリア
PASS=$(openssl rand -base64 20)
unset PASS
