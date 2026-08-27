#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ============================================================
# dbclient.py - BeamMP-SXMY_Plugin 自研数据库客户端（MySQL）
# Self-made MySQL client for the SXMY plugin (pure Python stdlib)
#
# 协议（被 modules/database.lua 调用，所有输出走 stdout，错误以 ERROR 开头）/
# protocol (invoked by modules/database.lua; all output on stdout, errors start with ERROR):
#   dbclient --host H --port P --db D --user U --pass W <init|load T|set T K V|del T K>
#   init                  -> create the three tables if missing (no output on success)
#   load T                -> print "key = value" lines for every row of table T
#   set T K V             -> upsert row (key K, value V) into table T
#   del T K               -> delete row (key K) from table T
# 表结构（统一 key-value 两列，内容格式与本地文件一致）/
# table schema (uniform key-value columns; the value matches the local file format):
#   sxmy_auth / sxmy_opusers / sxmy_banusers (bk VARCHAR(191) PRIMARY KEY, bv TEXT NOT NULL)
# ============================================================

import sys
import socket
import struct
import hashlib
import argparse
import os

DEBUG = os.environ.get("DBCLIENT_DEBUG") == "1"

def dbg(*args):
    if DEBUG:
        sys.stderr.write("[dbclient] " + " ".join(str(a) for a in args) + "\n")

VERSION = "0.1.0"

# ---------- low-level protocol helpers / 底层协议 ----------

def recv_exact(sock, n):
    buf = b""
    while len(buf) < n:
        chunk = sock.recv(n - len(buf))
        if not chunk:
            raise ConnectionError("connection closed by server")
        buf += chunk
    return buf


def read_packet(sock):
    hdr = recv_exact(sock, 4)
    plen = hdr[0] | (hdr[1] << 8) | (hdr[2] << 16)
    seq = hdr[3]
    return seq, recv_exact(sock, plen)


def write_packet(sock, seq, data):
    payload = struct.pack("<I", len(data))[:3] + bytes([seq & 0xFF]) + data
    sock.sendall(payload)
    return (seq + 1) & 0xFF


def read_lenenc(data, pos):
    first = data[pos]
    pos += 1
    if first < 0xFB:
        return first, pos
    if first == 0xFB:
        return None, pos  # NULL / 空值
    if first == 0xFC:
        return struct.unpack_from("<H", data, pos)[0], pos + 2
    if first == 0xFD:
        v = data[pos] | (data[pos + 1] << 8) | (data[pos + 2] << 16)
        return v, pos + 3
    if first == 0xFE:
        return struct.unpack_from("<Q", data, pos)[0], pos + 8
    raise ValueError("invalid length-encoded integer 0x%02X" % first)


def read_lenenc_str(data, pos):
    length, pos = read_lenenc(data, pos)
    return data[pos:pos + length], pos + length


def cstring(data, pos):
    end = data.find(b"\x00", pos)
    if end < 0:
        end = len(data)
    return data[pos:end], end + 1


# ---------- authentication / 认证 ----------

def sha1(b):
    if isinstance(b, str):
        b = b.encode("utf-8")
    return hashlib.sha1(b).digest()


def native_password_token(password, salt):
    # token = SHA1(pwd) XOR SHA1(salt + SHA1(SHA1(pwd))) / mysql_native_password 认证令牌
    p1 = sha1(password)
    p2 = sha1(p1)
    h = sha1(salt + p2)
    return bytes(a ^ b for a, b in zip(p1, h))


def mgf1(seed, length, digest=hashlib.sha1):
    out = b""
    counter = 0
    while len(out) < length:
        out += digest(seed + struct.pack(">I", counter)).digest()
        counter += 1
    return out[:length]


def rsa_oaep_encrypt(n, e, message):
    # RSAES-OAEP (SHA-1) 加密，用于 caching_sha2_password 快速认证 / RSAES-OAEP (SHA-1) used by the caching_sha2 fast auth
    k = (n.bit_length() + 7) // 8
    h_len = 20  # SHA-1
    if len(message) > k - 2 * h_len - 2:
        raise ValueError("message too long for RSA-OAEP")
    label_hash = hashlib.sha1(b"").digest()
    ps = b"\x00" * (k - len(message) - 2 * h_len - 2)
    db = label_hash + ps + b"\x01" + message
    seed = os.urandom(h_len)
    db_mask = mgf1(seed, k - h_len - 1)
    masked_db = bytes(a ^ b for a, b in zip(db, db_mask))
    seed_mask = mgf1(masked_db, h_len)
    masked_seed = bytes(a ^ b for a, b in zip(seed, seed_mask))
    em = b"\x00" + masked_seed + masked_db
    m_int = int.from_bytes(em, "big")
    c_int = pow(m_int, e, n)
    return c_int.to_bytes(k, "big")


def parse_pem_public_key(pem):
    lines = pem.splitlines()
    b64 = b"".join(l.strip() for l in lines if l and not l.startswith(b"-----"))
    der = __import__("base64").b64decode(b64)
    return parse_der_pubkey(der)


def parse_der_pubkey(der):
    # 解析 X.509 SubjectPublicKeyInfo 中的 RSA (n, e) / extract RSA (n, e) from an X.509 SubjectPublicKeyInfo
    def read_tlv(data, pos):
        tag = data[pos]
        pos += 1
        length = data[pos]
        pos += 1
        if length & 0x80:
            num = length & 0x7F
            length = int.from_bytes(data[pos:pos + num], "big")
            pos += num
        return tag, data[pos:pos + length], pos + length

    _, _, pos = read_tlv(der, 0)  # SEQUENCE
    _, spki, pos = read_tlv(der, pos)  # SEQUENCE (SPKI)
    # skip AlgorithmIdentifier
    _, _, ap = read_tlv(spki, 0)
    # BIT STRING -> inner RSAPublicKey
    _, bitstr, _ = read_tlv(spki, ap)
    rsa = bitstr[1:]  # skip unused-bits byte
    _, _, rp = read_tlv(rsa, 0)
    _, nbytes, _ = read_tlv(rsa, rp)
    _, _, ep = read_tlv(rsa, _)
    _, ebytes, _ = read_tlv(rsa, ep)
    n = int.from_bytes(nbytes, "big")
    e = int.from_bytes(ebytes, "big")
    return n, e


def auth_switch_caching_sha2(sock, seq, salt, user, password):
    # 先尝试快速认证：请求 RSA 公钥并发送 OAEP 加密的 密码+0x00 XOR salt / fast auth: request the RSA key and send OAEP(pwd||0) XOR salt
    seq = write_packet(sock, seq, b"\x02")  # COM_PUBLIC_KEY_REQUEST
    sseq, pkt = read_packet(sock)
    seq = sseq + 1
    if pkt[:1] == b"\xff":
        raise RuntimeError("public key request rejected: " + pkt.decode("utf-8", "replace"))
    n, e = parse_pem_public_key(pkt)
    data = password + b"\x00"
    enc = bytes(a ^ b for a, b in zip(rsa_oaep_encrypt(n, e, data), salt))
    seq = write_packet(sock, seq, enc)
    return seq


def connect(host, port, user, password, db):
    sock = socket.create_connection((host, port), timeout=15)
    seq, handshake = read_packet(sock)
    if handshake[:1] == b"\xff":
        raise RuntimeError("server rejected connection: " + handshake.decode("utf-8", "replace"))
    proto = handshake[0]
    if proto != 0x0A:
        raise RuntimeError("unsupported protocol version %d" % proto)
    _, pos = cstring(handshake, 1)  # server version
    thread_id = struct.unpack_from("<I", handshake, pos)[0]
    pos += 4
    salt1 = handshake[pos:pos + 8]
    pos += 9  # salt1 + filler
    cap_low = struct.unpack_from("<H", handshake, pos)[0]
    pos += 2
    pos += 1  # charset
    pos += 2  # status
    cap_high = struct.unpack_from("<H", handshake, pos)[0]
    pos += 2
    cap = cap_low | (cap_high << 16)
    auth_len = handshake[pos]
    pos += 1
    pos += 10  # reserved
    salt2 = b""
    if cap & 0x0008:  # CLIENT_SECURE_CONNECTION
        salt2 = handshake[pos:pos + max(12, auth_len - 9)]
        pos += max(12, auth_len - 9)
    plugin = b""
    if cap & 0x00080000:  # CLIENT_PLUGIN_AUTH
        plugin, _ = cstring(handshake, pos)
    salt = (salt1 + salt2)[:20]
    plugin = plugin.decode("utf-8", "replace") or "mysql_native_password"
    dbg("handshake cap=0x%08X auth_len=%d plugin=%s salt_len=%d" % (cap, auth_len, plugin, len(salt)))

    # 组装握手响应 / build the handshake response
    # LONG_PASSWORD|CONNECT_WITH_DB|SECURE_CONNECTION|PLUGIN_AUTH|PROTOCOL_41|LONG_FLAG
    flags = 0x00000200 | 0x00000008 | 0x00008000 | 0x00080000 | 0x00002000 | 0x00000001
    if not db:
        flags &= ~0x00000008  # CONNECT_WITH_DB only when a database is given / 有库名才带 CONNECT_WITH_DB
    if plugin == "caching_sha2_password":
        auth_token = b"\x00" * 32  # placeholder; the real token is sent after the public-key exchange below
    else:
        auth_token = native_password_token(password, salt)
    enc_user = user.encode("utf-8") + b"\x00"
    enc_db = (db.encode("utf-8") + b"\x00") if db else b""
    resp = struct.pack("<I", flags) + struct.pack("<I", 16777216) + b"\x21" + b"\x00" * 23
    resp += enc_user
    if plugin == "caching_sha2_password":
        # 长度编码空令牌（32 字节 0），随后服务器请求公钥进行快速认证 / lenenc empty token (32 zero bytes); the server then asks for the public-key fast auth
        resp += b"\x20" + b"\x00" * 32
    else:
        resp += bytes([len(auth_token)]) + auth_token
    resp += enc_db
    resp += plugin.encode("utf-8") + b"\x00"
    seq = write_packet(sock, seq + 1, resp)  # 握手包 seq=0，响应必须 seq=1 / the handshake packet is seq 0, the response must be seq 1
    dbg("sent handshake response, plugin=%s, seq=%d" % (plugin, seq - 1))

    # 读取认证结果（可能多次 AuthSwitchRequest / AuthMoreData）/ read the auth result (possible AuthSwitchRequest / AuthMoreData)
    fast_auth_sent = False
    for _ in range(6):
        sseq, pkt = read_packet(sock)
        seq = sseq + 1
        hdr = pkt[:1]
        dbg("auth recv seq=%d hdr=0x%02X len=%d" % (sseq, ord(hdr) if hdr else -1, len(pkt)))
        if hdr == b"\x00" or (hdr == b"\xfe" and len(pkt) < 9):  # OK
            dbg("auth OK")
            return sock
        if hdr == b"\xff":  # ERR
            errno = struct.unpack_from("<H", pkt, 1)[0]
            msg = pkt[3:].decode("utf-8", "replace")
            raise RuntimeError("MySQL error %d: %s" % (errno, msg))
        if hdr == b"\xfe":  # AuthSwitchRequest
            sw_plugin, pos = cstring(pkt, 1)
            sw_salt = pkt[pos:pos + 20]
            sw_plugin = sw_plugin.decode("utf-8", "replace")
            if sw_plugin == "mysql_native_password":
                token = native_password_token(password, sw_salt)
                seq = write_packet(sock, seq, token)
            elif sw_plugin == "caching_sha2_password":
                if not fast_auth_sent:
                    seq = auth_switch_caching_sha2(sock, seq, sw_salt, user, password)
                    fast_auth_sent = True
                else:
                    # 快速认证被拒；完整认证需要 TLS 或明文，出于安全不做明文 / fast auth rejected; full auth needs TLS or cleartext, which we do not do for safety
                    raise RuntimeError("caching_sha2_password fast auth was rejected; enable TLS on the MySQL account or switch it to mysql_native_password")
            else:
                raise RuntimeError("unsupported auth plugin: " + sw_plugin)
        elif hdr == b"\x01":  # AuthMoreData
            kind = pkt[1:2]
            if kind == b"\x02":  # server asks for the public key -> send the fast auth / 服务器请求公钥 → 发送快速认证
                if not fast_auth_sent:
                    seq = auth_switch_caching_sha2(sock, seq, salt, user, password)
                    fast_auth_sent = True
                else:
                    raise RuntimeError("unexpected second public-key request")
            elif kind == b"\x03":  # fast auth OK
                continue
            elif kind == b"\x04":  # fast auth failed -> full auth required
                raise RuntimeError("caching_sha2_password full auth required (enable TLS on the MySQL account or switch it to mysql_native_password)")
            else:
                raise RuntimeError("unexpected auth data 0x%02X" % ord(pkt[1]) if len(pkt) > 1 else "empty auth data")
        else:
            raise RuntimeError("unexpected auth packet header 0x%02X" % ord(hdr))
    raise RuntimeError("auth handshake did not complete")


# ---------- query execution / 查询执行 ----------

def escape(value):
    s = str(value).encode("utf-8")
    out = bytearray()
    for b in s:
        if b in (0x00, 0x0A, 0x0D, 0x1A, 0x22, 0x27, 0x5C):
            out.append(0x5C)
        out.append(b)
    return out.decode("utf-8")


def run_query(sock, sql):
    # 每条命令独立编号：COM_QUERY 总是 seq=0，响应 seq 从 1 起 / each command restarts at seq 0 (COM_QUERY), responses count up from 1
    seq = write_packet(sock, 0, b"\x03" + sql.encode("utf-8"))
    seq, pkt = read_packet(sock)
    hdr = pkt[:1]
    if hdr == b"\x00" or (hdr == b"\xfe" and len(pkt) < 9):
        return None  # OK packet / 成功无结果集
    if hdr == b"\xff":
        errno = struct.unpack_from("<H", pkt, 1)[0]
        msg = pkt[3:].decode("utf-8", "replace")
        raise RuntimeError("MySQL error %d: %s" % (errno, msg))
    # 结果集 / result set
    ncols, pos = read_lenenc(pkt, 0)
    for _ in range(ncols):
        _, pkt = read_packet(sock)  # column definition
    _, pkt = read_packet(sock)  # EOF after columns
    rows = []
    while True:
        _, pkt = read_packet(sock)
        if pkt[:1] == b"\xfe" and len(pkt) < 9:
            break  # EOF after rows
        rpos = 0
        row = []
        for _ in range(ncols):
            length, rpos = read_lenenc(pkt, rpos)
            if length is None:
                row.append(None)
            else:
                row.append(pkt[rpos:rpos + length].decode("utf-8", "replace"))
                rpos += length
        rows.append(row)
    return rows


# ---------- commands / 命令 ----------

TABLES = {
    "users": "sxmy_auth",
    "opusers": "sxmy_opusers",
    "banusers": "sxmy_banusers",
}

DDL = [
    # sxmy_auth: one account per row with separate columns (nick/hash/ip) / 账户表：每行一个账户，字段分列
    "CREATE TABLE IF NOT EXISTS sxmy_auth (nick VARCHAR(191) NOT NULL PRIMARY KEY, hash TEXT NOT NULL, ip VARCHAR(45) NULL) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",
    "CREATE TABLE IF NOT EXISTS sxmy_opusers (bk VARCHAR(191) NOT NULL PRIMARY KEY, bv TEXT NOT NULL) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",
    "CREATE TABLE IF NOT EXISTS sxmy_banusers (bk VARCHAR(191) NOT NULL PRIMARY KEY, bv TEXT NOT NULL) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",
]


def cmd_init(sock):
    for ddl in DDL:
        run_query(sock, ddl)
    # 旧结构迁移（bk/bv -> nick/hash/ip），幂等 / migrate the legacy schema (bk/bv -> nick/hash/ip), idempotent
    try:
        run_query(sock, "ALTER TABLE sxmy_auth ADD COLUMN ip VARCHAR(45) NULL")
    except Exception:
        pass  # already has ip / 已有 ip 列
    try:
        run_query(sock, "ALTER TABLE sxmy_auth CHANGE COLUMN bk nick VARCHAR(191) NOT NULL, CHANGE COLUMN bv hash TEXT NOT NULL")
    except Exception:
        pass  # already migrated / 已迁移
    sys.stdout.write("OK\n")


def cmd_load(sock, table):
    if table not in TABLES:
        raise RuntimeError("unknown table: %s" % table)
    if table == "users":
        # 每行一个账户，输出 "nick = hash [ip]"（协议与 Lua 端一致）/ one account per row, print "nick = hash [ip]"
        rows = run_query(sock, "SELECT nick, hash, ip FROM sxmy_auth")
        for nick, hashv, ip in rows or []:
            sys.stdout.write("%s = %s%s\n" % (nick, hashv, (" " + ip) if ip else ""))
        return
    rows = run_query(sock, "SELECT bk, bv FROM %s" % TABLES[table])
    if rows:
        for bk, bv in rows:
            sys.stdout.write("%s = %s\n" % (bk, bv))


def cmd_set(sock, table, key, value):
    if table not in TABLES:
        raise RuntimeError("unknown table: %s" % table)
    if table == "users":
        # 值格式 "hash [ip]"：拆分为两列存储 / value "hash [ip]" is split into the hash and ip columns
        parts = value.split(" ", 1)
        hashv = parts[0]
        ip = parts[1] if len(parts) > 1 else ""
        ip_sql = "'%s'" % escape(ip) if ip else "NULL"
        sql = "INSERT INTO sxmy_auth (nick, hash, ip) VALUES ('%s', '%s', %s) ON DUPLICATE KEY UPDATE hash = VALUES(hash), ip = VALUES(ip)" % (
            escape(key), escape(hashv), ip_sql)
    else:
        sql = "INSERT INTO %s (bk, bv) VALUES ('%s', '%s') ON DUPLICATE KEY UPDATE bv = VALUES(bv)" % (
            TABLES[table], escape(key), escape(value))
    run_query(sock, sql)
    sys.stdout.write("OK\n")


def cmd_del(sock, table, key):
    if table not in TABLES:
        raise RuntimeError("unknown table: %s" % table)
    if table == "users":
        run_query(sock, "DELETE FROM sxmy_auth WHERE nick = '%s'" % escape(key))
    else:
        run_query(sock, "DELETE FROM %s WHERE bk = '%s'" % (TABLES[table], escape(key)))
    sys.stdout.write("OK\n")


def main():
    parser = argparse.ArgumentParser(prog="dbclient", add_help=False)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", default="3306")
    parser.add_argument("--db", default="")
    parser.add_argument("--user", default="")
    parser.add_argument("--pass", dest="password", default="")
    args, rest = parser.parse_known_args()
    if not rest:
        print("ERROR: missing command (init|load|set|del)")
        return 1
    cmd = rest[0]
    try:
        sock = connect(args.host, int(args.port), args.user, args.password, args.db)
        try:
            if cmd == "init":
                cmd_init(sock)
            elif cmd == "load":
                if len(rest) < 2:
                    raise RuntimeError("load requires a table name")
                cmd_load(sock, rest[1])
            elif cmd == "set":
                if len(rest) < 4:
                    raise RuntimeError("set requires table, key and value")
                cmd_set(sock, rest[1], rest[2], rest[3])
            elif cmd == "del":
                if len(rest) < 3:
                    raise RuntimeError("del requires table and key")
                cmd_del(sock, rest[1], rest[2])
            else:
                raise RuntimeError("unknown command: %s" % cmd)
        finally:
            try:
                sock.close()
            except Exception:
                pass
        return 0
    except Exception as exc:  # noqa: BLE001 - 统一输出 ERROR 前缀 / unified ERROR prefix on stdout
        print("ERROR: %s" % str(exc))
        return 1


if __name__ == "__main__":
    sys.exit(main())
