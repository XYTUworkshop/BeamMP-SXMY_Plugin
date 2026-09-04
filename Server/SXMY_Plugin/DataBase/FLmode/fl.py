#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# FLmode 文件模式脚本：操作 DataBase/.files 下的文件
# 用法：
#   python fl.py create <name> [content]   # 创建文件
#   python fl.py delete <name>             # 删除文件
#   python fl.py read <name>               # 读取文件（内容输出到 stdout）
#   python fl.py write <name> <content>    # 编辑/覆盖写入文件
# 成功输出 OK（read 输出内容），失败输出 ERR: <原因> 并退出码非 0

import os
import sys

BASE = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".files"))


def safe_name(name):
    # 防路径穿越：只允许安全文件名字符
    if not name:
        return None
    if "/" in name or "\\" in name or ".." in name:
        return None
    if name in (".", ".."):
        return None
    return name


def main():
    if len(sys.argv) < 3:
        print("usage: fl.py <create|delete|read|write> <name> [content]")
        sys.exit(2)
    op = sys.argv[1]
    name = safe_name(sys.argv[2])
    if name is None:
        sys.exit("ERR: invalid file name")
    path = os.path.join(BASE, name)
    content = sys.argv[3] if len(sys.argv) > 3 else ""

    if op == "create":
        if os.path.exists(path):
            sys.exit("ERR: file already exists")
        with open(path, "w", encoding="utf-8") as f:
            f.write(content)
        print("OK")
    elif op == "delete":
        if not os.path.exists(path):
            sys.exit("ERR: file not found")
        os.remove(path)
        print("OK")
    elif op == "read":
        if not os.path.exists(path):
            sys.exit("ERR: file not found")
        with open(path, "r", encoding="utf-8") as f:
            sys.stdout.write(f.read())
    elif op == "write":
        if not os.path.exists(path):
            sys.exit("ERR: file not found")
        with open(path, "w", encoding="utf-8") as f:
            f.write(content)
        print("OK")
    else:
        print("usage: fl.py <create|delete|read|write> <name> [content]")
        sys.exit(2)


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception as e:
        sys.exit("ERR: " + str(e))
