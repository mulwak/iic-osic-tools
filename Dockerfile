#######################################################################
# スタートアップスクリプトが一時ファイル経由でDISPLAYを拾うようにする
# klayout+CentOS固有の問題を解決
#######################################################################
FROM hpretl/iic-osic-tools:2023.08
COPY --chmod=755 images/iic-osic-tools/skel/dockerstartup/scripts/ui_startup.sh /dockerstartup/scripts
USER 0:0
RUN strip --remove-section=.note.ABI-tag /usr/lib/x86_64-linux-gnu/libQt5Core.so.5
USER 1000:1000

