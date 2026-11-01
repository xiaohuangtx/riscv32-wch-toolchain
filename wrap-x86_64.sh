#!/bin/sh
# 把工具链目录下的 x86_64 可执行文件改名为 *.x86_64, 原位置换成调用 qemu 的同名脚本.
# gcc 会再去调用 cc1/as/collect2/ld/lto-wrapper 等子程序, 子程序也是 x86_64 的,
# 没有 binfmt 时内核无法直接执行, 所以每个可执行文件都要包一层.
# x86_64 的 .so(如 liblto_plugin.so)由 qemu 里的 x86_64 程序加载, 不需要处理.
set -eu

root=$1
count=0

find "$root" -type f -perm -u+x ! -name '*.x86_64' > /tmp/wrap-list
while IFS= read -r f; do
    info=$(file -b "$f")
    case "$info" in
        *x86-64*) ;;
        *) continue ;;
    esac
    case "$info" in
        *executable*|*interpreter*) ;;
        *) continue ;;
    esac

    mv "$f" "$f.x86_64"
    # -0 "$0": 保持 argv[0] 为原路径, gcc 依赖它定位 libexec/ 等目录
    cat > "$f" <<EOF
#!/bin/sh
exec qemu-x86_64-static -0 "\$0" "$f.x86_64" "\$@"
EOF
    chmod 755 "$f"
    count=$((count + 1))
done < /tmp/wrap-list
rm -f /tmp/wrap-list

echo "wrapped $count x86_64 executables under $root"
[ "$count" -gt 0 ]
