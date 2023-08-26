#!/bin/bash
# ========================================================================
# dockerコンテナでX11フォワーディングをするための準備
# 一回やればいい
# Xが自動で割り当てられる6010:6050/tcpをホストに転送する
# https://qiita.com/nobrin/items/59b9b645e5595365c4ac のブリッジネットワークの章
# ========================================================================
sysctl -w net.ipv4.conf.all.route_localnet=1
iptables -t nat -I PREROUTING 1 -i docker0 -p tcp -m multiport --dports 6010:6050 -j DNAT --to-destination 127.0.0.1

