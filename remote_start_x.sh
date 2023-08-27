#!/bin/bash
# ========================================================================
# IIC dockerイメージをX11で起動するスクリプト。
# SSHでリモート接続されているときに叩かれ、X11フォワーディングに対応。
# docker内のX11(6010:6050/tcp)がlocalhostに送られるのをDNATで転送する必要がある。
# DNATの設定はset_dnat_for_xforwarding.sh
#
# SPDX-FileCopyrightText: 2022-2023 Harald Pretl and Georg Zachl
# Johannes Kepler University, Institute for Integrated Circuits
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# SPDX-License-Identifier: Apache-2.0
# ========================================================================

if [ -n "${DRY_RUN}" ]; then
  echo "[INFO] 試し実行（ドライラン）です。本実行で実行されるべきコマンドが表示されますが実行はされません。"
  ECHO_IF_DRY_RUN="echo $"
fi

if [ -z ${CONTAINER_NAME+z} ]; then
  CONTAINER_NAME="iic-osic-tools_xserver_uid_"$(id -u)
fi

# コンテナが既に存在している、あるいはさらに実行中であるのをチェック
if [ "$(docker ps -q -f name="${CONTAINER_NAME}")" ]; then
  echo "[WARNING] コンテナが実行中です！"
  echo "          別の端末で付けっぱなしではありませんか？"
  echo "          何もせずそっとしておく(\"q\"uit)か、強制的に停止させる(\"s\"top)ことができます。"
  echo "          コンテナを削除(\"r\"emove)することもできます。"
  echo
  echo -n "\"q\"キーでquit、\"s\"キーでstop、\"r\"キーでremoveします："
  read -r -n 1 k <&1
  echo
  if [[ $k = s ]] ; then
    ${ECHO_IF_DRY_RUN} docker stop "${CONTAINER_NAME}"
    echo "[INFO] コンテナを停止しました。"
  elif [[ $k = r ]] ; then
    echo "[WARNING] コンテナを削除して再作成しようとしています！"
    echo "          大抵の場合は何の問題もなく、環境と心をリフレッシュできます。"
    echo "          designesディレクトリや共有ディレクトリの中身には影響しません。"
    echo "          それ以外の場所に重要な変更を加えた憶えがある場合は躊躇してください。"
    echo
    echo -n "\"n\"キーで終了、\"y\"キーで続行："
    read -r -n 1 kk <&1
    echo
    if [[ $kk = y ]] ; then
      ${ECHO_IF_DRY_RUN} docker stop "${CONTAINER_NAME}"
      ${ECHO_IF_DRY_RUN} docker rm "${CONTAINER_NAME}"
      echo "[INFO] コンテナを削除しました。"
    else
      echo "[INFO] スクリプトを終了します。"
      exit 1
    fi
  else
    echo "[INFO] スクリプトを終了します。"
    exit 1
  fi
fi

# デザインディレクトリの設定
if [ -z ${DESIGNS+z} ]; then
  DESIGNS=$HOME/eda/designs
  if [ ! -d "$DESIGNS" ]; then
    ${ECHO_IF_DRY_RUN} mkdir -p "$DESIGNS"
  fi
  echo "[INFO] デザインディレクトリ（作業フォルダ）が自動的に${DESIGNS}に設定されました。"
  echo "[HINT] $ export DESIGNS=\"path/to/dir\"を事前に指定することで変更できます。"
fi

# ローカルでカスタムしたイメージを使うのでこれはいらない
#if [ -z ${DOCKER_USER+z} ]; then
#  DOCKER_USER="hpretl"
#fi

if [ -z ${DOCKER_IMAGE+z} ]; then
  DOCKER_IMAGE="islab-osic-tools"
fi

if [ -z ${DOCKER_TAG+z} ]; then
  DOCKER_TAG="latest"
fi

PARAMS="--security-opt seccomp=unconfined"
if [[ "$OSTYPE" == "linux"* ]]; then
  echo "[INFO] 自動的にLinux環境を検知しました。"
  # Should also be a sensible default
  if [ -z ${CONTAINER_USER+z} ]; then
    CONTAINER_USER=$(id -u)
  fi

  if [ -z ${CONTAINER_GROUP+z} ]; then
    CONTAINER_GROUP=$(id -g)
  fi

  if [ -z ${DISP+z} ]; then
    if [ -z ${DISPLAY+z} ]; then
      echo "[ERROR] 環境変数DISPLAYが未設定です！"
      echo "        X11が使用可能な環境であることを確認してください。"
      exit 1
    else
      # 現在のDISPLAY変数の値を取得する
      CURRENT_DISPLAY="$DISPLAY"
      CURRENT_SCREEN_NUMBER=$(echo "$CURRENT_DISPLAY" | sed 's/.*:\(.*\)\..*/\1/')
      DISP="172.17.0.1:${CURRENT_SCREEN_NUMBER}"
      # バインド用ファイルに書き出す
      DISPLAY_TMPFILE="/tmp/.${CONTAINER_NAME}_display"
      echo $DISP > $DISPLAY_TMPFILE
      PARAMS="$PARAMS -v $DISPLAY_TMPFILE:/headless/.display:ro"
    fi
  fi

  if [ -z ${XAUTH+z} ]; then
    # XAUTHの設定
    # XAUTHORITYが未設定なら$HOME/.Xauthorityを使う。
    if [ -z ${XAUTHORITY+z} ]; then
      if [ -f "$HOME/.Xauthority" ]; then
        XAUTH="$HOME/.Xauthority"
      else
        echo "[ERROR] Xauthority が見つかりません！"
        exit 1
      fi
    else
      XAUTH=$XAUTHORITY
    fi

    # Xauth 空ファイル作成
    # Thanks to https://stackoverflow.com/a/25280523
    # ファミリーワイルド。16進数先頭4字を$FFFFとすることで、あらゆるDISPLAYに対してクッキーを有効化する
    XAUTH_TMP="/tmp/.${CONTAINER_NAME}_xauthority"
    ${ECHO_IF_DRY_RUN} echo -n > "${XAUTH_TMP}"
    if [ -z "${ECHO_IF_DRY_RUN}" ]; then
      xauth -f "${XAUTH}" nlist "${DISPLAY}" | sed -e 's/^..../ffff/' | xauth -f "${XAUTH_TMP}" nmerge -
    else
      ${ECHO_IF_DRY_RUN} "xauth -f ${XAUTH} nlist ${DISPLAY} | sed -e 's/^..../ffff/' | xauth -f ${XAUTH_TMP} nmerge -"
    fi
    XAUTH=${XAUTH_TMP}

    # グラフィックドライバ
    if [ -d "/dev/dri" ]; then
      echo "[INFO] /dev/dri を発見しました。GPUによるグラフィックアクセラレーションを適用します。"
      PARAMS="${PARAMS} --device=/dev/dri:/dev/dri"
    else
      echo "[INFO] /dev/driはありませんでした！"
      FORCE_LIBGL_INDIRECT=1
    fi
  fi
  PARAMS="$PARAMS -v $XAUTH:/headless/.xauthority:rw -e XAUTHORITY=/headless/.xauthority"
fi

if [ -n "${FORCE_LIBGL_INDIRECT}" ]; then
  echo "[INFO] 間接レンダリングを行います。"
  PARAMS="${PARAMS} -e LIBGL_ALWAYS_INDIRECT=1"
fi

if [ -n "${DOCKER_EXTRA_PARAMS}" ]; then
  PARAMS="${PARAMS} ${DOCKER_EXTRA_PARAMS}"
fi

# 1000以上の、ふつうのUIDおよびGIDであることを確かめる
if [[ ${CONTAINER_USER} -ne 0 ]]  &&  [[ ${CONTAINER_USER} -lt 1000 ]]; then
  prt_str="# [WARNING] Selected User ID ${CONTAINER_USER} is below 1000. This ID might interfere with User-IDs inside the container and cause undefined behavior! #"
  printf -- '#%.0s' $(seq 1 ${#prt_str})
  echo
  echo "${prt_str}"
  printf -- '#%.0s' $(seq 1 ${#prt_str})
  echo
fi

if [[ ${CONTAINER_GROUP} -ne 0 ]]  && [[ ${CONTAINER_GROUP} -lt 1000 ]]; then
  prt_str="# [WARNING] Selected Group ID ${CONTAINER_GROUP} is below 1000. This ID might interfere with Group-IDs inside the container and cause undefined behavior! #"
  printf -- '#%.0s' $(seq 1 ${#prt_str})
  echo
  echo "${prt_str}"
  printf -- '#%.0s' $(seq 1 ${#prt_str})
  echo
fi

# コンテナが存在しつつ待機状態にあれば、再始動できる。
if [ "$(docker ps -aq -f name="${CONTAINER_NAME}")" ]; then
  echo "[INFO] 待機状態のコンテナ ${CONTAINER_NAME} を再開します。"
  ## 追加処理ここから ##
  # 現在のDISPLAY変数の値を取得する
  CURRENT_DISPLAY="$DISPLAY"
  CURRENT_SCREEN_NUMBER=$(echo "$CURRENT_DISPLAY" | sed 's/.*:\(.*\)\..*/\1/')
  DISP="172.17.0.1:${CURRENT_SCREEN_NUMBER}"
  # バインド用ファイルに書き出す
  DISPLAY_TMPFILE="/tmp/.${CONTAINER_NAME}_display"
  echo $DISP > $DISPLAY_TMPFILE
  # XAUTHの再設定
  if [ -z ${XAUTHORITY+z} ]; then
    if [ -f "$HOME/.Xauthority" ]; then
      XAUTH="$HOME/.Xauthority"
    else
      echo "[ERROR] Xauthority が見つかりません！"
      exit 1
    fi
  else
    XAUTH=$XAUTHORITY
  fi
  XAUTH_TMP="/tmp/.${CONTAINER_NAME}_xauthority"
  ${ECHO_IF_DRY_RUN} echo -n > "${XAUTH_TMP}"
  if [ -z "${ECHO_IF_DRY_RUN}" ]; then
    xauth -f "${XAUTH}" nlist "${DISPLAY}" | sed -e 's/^..../ffff/' | xauth -f "${XAUTH_TMP}" nmerge -
  else
    ${ECHO_IF_DRY_RUN} "xauth -f ${XAUTH} nlist ${DISPLAY} | sed -e 's/^..../ffff/' | xauth -f ${XAUTH_TMP} nmerge -"
  fi
  ## 追加処理ここまで ##

  ${ECHO_IF_DRY_RUN} docker start "${CONTAINER_NAME}"

# コンテナが存在せず、新造する
else
  echo "[INFO] コンテナが存在しません。${CONTAINER_NAME} という名前で作成します..."
  #${ECHO_IF_DRY_RUN} docker pull "${DOCKER_USER}/${DOCKER_IMAGE}:${DOCKER_TAG}"
  ${ECHO_IF_DRY_RUN} docker run -d --user "${CONTAINER_USER}:${CONTAINER_GROUP}" \
    -e "DISPLAY=${DISP}" \
    -v "${DESIGNS}:/foss/designs:rw" \
    -v "/pdk:/foss/server_lib:ro" \
    -v "/user_share:/foss/user_share:rw" \
    ${PARAMS} \
    --name "${CONTAINER_NAME}" "${DOCKER_IMAGE}:${DOCKER_TAG}"
fi

