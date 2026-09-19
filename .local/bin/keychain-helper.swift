// keychain-helper.swift — encrypt/decrypt 専用の Keychain アクセスヘルパー
//
// 目的: `security find-generic-password` はどのスクリプトから呼んでも常に
// 同じバイナリ(/usr/bin/security)からのアクセスとして扱われるため、
// Keychain の「信頼アプリのみ許可」ACLでは「このシェルスクリプトだけ許可」
// を区別できない。このヘルパーはレガシーな SecKeychainItemCreateFromContent
// + SecAccessCreate API を使い、アイテム作成時に「このヘルパーバイナリ自身」
// だけを信頼アプリとして登録する。以後 get/set は無確認で通るが、
// `security` CLI 等の別プロセスからのアクセスは(信頼リストに無いため)
// 確認ダイアログの対象になる。
//
// 使い方:
//   keychain-helper get      [account]              パスフレーズを標準出力に印字
//   keychain-helper set      [-f|--force] [account]  標準入力の1行をパスフレーズとして登録
//   keychain-helper generate [-f|--force] [account]  ランダム生成して登録
//   keychain-helper label    [account]               表示名(ラベル)を設定/更新
//
// account 省略時は "default"。ビルド: `swiftc keychain-helper.swift -o keychain-helper`
//
// キーチェーンアクセス.app で見つけやすいよう、新規作成時は自動でラベルを
// 付与する。ラベル無しで作られた既存項目には `label` サブコマンドで後から
// 付与できる。

import Foundation
import Security

let SERVICE = "com.encrypt.aes256gcm"

// The classic FourCharCode constants (kSecServiceItemAttr='svce' etc.) aren't
// bridged into the Swift Security overlay, so recompute them from their
// well-known 4-character codes.
func fourCharCode(_ s: String) -> UInt32 {
    var result: UInt32 = 0
    for c in s.utf8 { result = (result << 8) | UInt32(c) }
    return result
}
let kSecServiceItemAttr_: SecKeychainAttrType = fourCharCode("svce")
let kSecAccountItemAttr_: SecKeychainAttrType = fourCharCode("acct")
let kSecLabelItemAttr_: SecKeychainAttrType = fourCharCode("labl")
let kSecGenericPasswordItemClass_ = SecItemClass(rawValue: fourCharCode("genp"))!

func defaultLabel(account: String) -> String {
    "dotfiles encrypt/decrypt (\(account))"
}

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
    exit(1)
}

func trustedAppSelf() -> SecTrustedApplication {
    var app: SecTrustedApplication?
    let status = SecTrustedApplicationCreateFromPath(nil, &app)
    guard status == errSecSuccess, let a = app else {
        fail("SecTrustedApplicationCreateFromPath failed: \(status)")
    }
    return a
}

func makeSelfOnlyAccess(label: String) -> SecAccess {
    let app = trustedAppSelf()
    var access: SecAccess?
    let trustedList = [app] as CFArray
    let status = SecAccessCreate(label as CFString, trustedList, &access)
    guard status == errSecSuccess, let acc = access else {
        fail("SecAccessCreate failed: \(status)")
    }
    return acc
}

func findItem(account: String) -> SecKeychainItem? {
    var itemRef: SecKeychainItem?
    let status = SecKeychainFindGenericPassword(
        nil,
        UInt32(SERVICE.utf8.count), SERVICE,
        UInt32(account.utf8.count), account,
        nil, nil,
        &itemRef
    )
    return status == errSecSuccess ? itemRef : nil
}

func getPassword(account: String) -> String {
    var length: UInt32 = 0
    var dataPtr: UnsafeMutableRawPointer?
    var itemRef: SecKeychainItem?
    let status = SecKeychainFindGenericPassword(
        nil,
        UInt32(SERVICE.utf8.count), SERVICE,
        UInt32(account.utf8.count), account,
        &length, &dataPtr,
        &itemRef
    )
    guard status == errSecSuccess, let ptr = dataPtr else {
        fail("Not found in Keychain (service=\(SERVICE), account=\(account)): status=\(status)")
    }
    let data = Data(bytes: ptr, count: Int(length))
    SecKeychainItemFreeContent(nil, ptr)
    guard let str = String(data: data, encoding: .utf8) else {
        fail("Stored value is not valid UTF-8")
    }
    return str
}

func setPassword(account: String, password: String, force: Bool) {
    let pwBytes = Array(password.utf8)

    if let item = findItem(account: account) {
        if !force {
            fail("Entry already exists (service=\(SERVICE), account=\(account)). Use --force to overwrite.")
        }
        // Deliberately delete-then-recreate rather than modify in place: an
        // item created by something other than this helper (e.g. the plain
        // `security` CLI) keeps whatever ACL it was created with when merely
        // modified, silently skipping the self-only restriction. Recreating
        // it here guarantees the restricted ACL applies even when replacing
        // a pre-existing, non-helper-created entry.
        let delStatus = SecKeychainItemDelete(item)
        guard delStatus == errSecSuccess else {
            fail("Failed to delete existing item before overwrite: \(delStatus)")
        }
    }

    let access = makeSelfOnlyAccess(label: SERVICE)

    var svcAttr = SecKeychainAttribute(tag: kSecServiceItemAttr_, length: 0, data: nil)
    var acctAttr = SecKeychainAttribute(tag: kSecAccountItemAttr_, length: 0, data: nil)
    var lblAttr = SecKeychainAttribute(tag: kSecLabelItemAttr_, length: 0, data: nil)

    var status: OSStatus = errSecSuccess
    var svc = Array(SERVICE.utf8)
    var acct = Array(account.utf8)
    var lbl = Array(defaultLabel(account: account).utf8)
    svc.withUnsafeMutableBytes { svcBuf in
        acct.withUnsafeMutableBytes { acctBuf in
            lbl.withUnsafeMutableBytes { lblBuf in
                svcAttr.length = UInt32(svcBuf.count)
                svcAttr.data = svcBuf.baseAddress
                acctAttr.length = UInt32(acctBuf.count)
                acctAttr.data = acctBuf.baseAddress
                lblAttr.length = UInt32(lblBuf.count)
                lblAttr.data = lblBuf.baseAddress
                var attrs = [svcAttr, acctAttr, lblAttr]
                attrs.withUnsafeMutableBufferPointer { attrsBuf in
                    var attrList = SecKeychainAttributeList(count: UInt32(attrsBuf.count), attr: attrsBuf.baseAddress)
                    var newItem: SecKeychainItem?
                    status = SecKeychainItemCreateFromContent(
                        kSecGenericPasswordItemClass_,
                        &attrList,
                        UInt32(pwBytes.count),
                        pwBytes,
                        nil,
                        access,
                        &newItem
                    )
                }
            }
        }
    }
    guard status == errSecSuccess else {
        fail("Failed to create item: \(status)")
    }
}

func setLabel(account: String, label: String) {
    guard let item = findItem(account: account) else {
        fail("Not found in Keychain (service=\(SERVICE), account=\(account))")
    }
    var status: OSStatus = errSecSuccess
    var lbl = Array(label.utf8)
    lbl.withUnsafeMutableBytes { buf in
        var labelAttr = SecKeychainAttribute(tag: kSecLabelItemAttr_, length: UInt32(buf.count), data: buf.baseAddress)
        var attrs = [labelAttr]
        attrs.withUnsafeMutableBufferPointer { attrsBuf in
            var attrList = SecKeychainAttributeList(count: UInt32(attrsBuf.count), attr: attrsBuf.baseAddress)
            status = SecKeychainItemModifyContent(item, &attrList, 0, nil)
        }
    }
    guard status == errSecSuccess else {
        fail("Failed to set label: \(status)")
    }
}

// --- CLI ---
let args = CommandLine.arguments
guard args.count >= 2 else {
    fail("Usage: \(args[0]) get|set|generate [-f|--force] [account]")
}

let cmd = args[1]
var force = false
var account = "default"
for a in args.dropFirst(2) {
    if a == "-f" || a == "--force" { force = true }
    else { account = a }
}

switch cmd {
case "get":
    print(getPassword(account: account))
case "set":
    guard let line = readLine(strippingNewline: true), !line.isEmpty else {
        fail("No password provided on stdin")
    }
    setPassword(account: account, password: line, force: force)
    FileHandle.standardError.write("Stored in Keychain (self-only access): service=\(SERVICE), account=\(account)\n".data(using: .utf8)!)
case "generate":
    var bytes = [UInt8](repeating: 0, count: 32)
    let result = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    guard result == errSecSuccess else { fail("SecRandomCopyBytes failed") }
    let pass = Data(bytes).base64EncodedString()
    setPassword(account: account, password: pass, force: force)
    FileHandle.standardError.write("Generated and stored in Keychain (self-only access): service=\(SERVICE), account=\(account)\n".data(using: .utf8)!)
case "label":
    setLabel(account: account, label: defaultLabel(account: account))
    FileHandle.standardError.write("Label set: service=\(SERVICE), account=\(account)\n".data(using: .utf8)!)
default:
    fail("Unknown command: \(cmd)")
}
