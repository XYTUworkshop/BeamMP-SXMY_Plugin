#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# DBmode 数据库脚本：MySQL 数据表操作
# 用法：
#   python db.py ping          <host:port> <user> <pwd> <db>                      # 连接测试
#   python db.py create_table  <host:port> <user> <pwd> <db> <table> <schema>     # 创建数据表
#   python db.py drop_table    <host:port> <user> <pwd> <db> <table>              # 删除数据表
#   python db.py read          <host:port> <user> <pwd> <db> <table>              # 读取数据表（stdout）
#   python db.py write         <host:port> <user> <pwd> <db> <table> <set> <where> # 编辑数据表（UPDATE）
# 优先使用 pymysql，缺失时回退 mysql 命令行客户端（密码经 MYSQL_PWD 传递）
# 成功输出 OK（read 输出表数据），失败输出 ERR: <原因> 并退出码非 0

import os
import subprocess
import sys


def parse_addr(addr):
    if ":" in addr:
        host, port = addr.rsplit(":", 1)
        try:
            return host, int(port)
        except ValueError:
            return addr, 3306
    return addr, 3306


def esc_ident(s):
    return s.replace("`", "")


def run_pymysql(op, host, port, user, pwd, db, args):
    import pymysql
    conn = pymysql.connect(host=host, port=port, user=user, password=pwd, database=db)
    try:
        cur = conn.cursor()
        if op == "ping":
            cur.execute("SELECT 1")
        elif op == "create_table":
            cur.execute("CREATE TABLE `%s` (%s)" % (esc_ident(args[0]), args[1]))
        elif op == "drop_table":
            cur.execute("DROP TABLE IF EXISTS `%s`" % esc_ident(args[0]))
        elif op == "read":
            cur.execute("SELECT * FROM `%s`" % esc_ident(args[0]))
            for row in cur.fetchall():
                print("\t".join(str(x) if x is not None else "NULL" for x in row))
        elif op == "write":
            cur.execute("UPDATE `%s` SET %s WHERE %s" % (esc_ident(args[0]), args[1], args[2]))
        conn.commit()
        print("OK")
    finally:
        conn.close()


def run_mysql_cli(op, host, port, user, pwd, db, args):
    env = dict(os.environ)
    if pwd:
        env["MYSQL_PWD"] = pwd

    def q(sql):
        r = subprocess.run(
            ["mysql", "-h", host, "-P", str(port), "-u", user,
             "--connect-timeout=5", db, "-e", sql],
            env=env, capture_output=True, text=True,
        )
        if r.returncode != 0:
            sys.exit("ERR: " + (r.stderr or "").strip())
        return r.stdout

    if op == "ping":
        q("SELECT 1")
        print("OK")
    elif op == "create_table":
        q("CREATE TABLE `%s` (%s)" % (esc_ident(args[0]), args[1]))
        print("OK")
    elif op == "drop_table":
        q("DROP TABLE IF EXISTS `%s`" % esc_ident(args[0]))
        print("OK")
    elif op == "read":
        out = q("SELECT * FROM `%s`" % esc_ident(args[0]))
        sys.stdout.write(out)
    elif op == "write":
        q("UPDATE `%s` SET %s WHERE %s" % (esc_ident(args[0]), args[1], args[2]))
        print("OK")


def main():
    if len(sys.argv) < 6:
        print("usage: db.py <ping|create_table|drop_table|read|write> "
              "<host:port> <user> <pwd> <db> [table] [args...]")
        sys.exit(2)
    op = sys.argv[1]
    host, port = parse_addr(sys.argv[2])
    user = sys.argv[3]
    pwd = sys.argv[4]
    db = sys.argv[5]
    args = sys.argv[6:]
    try:
        import pymysql  # noqa: F401
        run_pymysql(op, host, port, user, pwd, db, args)
    except ImportError:
        run_mysql_cli(op, host, port, user, pwd, db, args)


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception as e:
        sys.exit("ERR: " + str(e))
