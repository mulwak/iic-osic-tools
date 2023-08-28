#######################################################################
# skelの内容を反映
#######################################################################
FROM hpretl/iic-osic-tools:2023.08
COPY --chmod=755 images/iic-osic-tools/skel/dockerstartup/scripts/ui_startup.sh /dockerstartup/scripts

