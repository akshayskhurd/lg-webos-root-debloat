#!/bin/sh
# webos-debloat.sh: reversible, firmware-update-safe debloat for rooted LG webOS TVs.
# SPDX-License-Identifier: MIT
#
# DESIGN RULES:
# 1. NOTHING IS DELETED. No app directory is removed, no rootfs file is
#    written. The script only edits LG's own "blocked system app list" JSON,
#    the preload manager's policy and a few system settings.
# 2. Original files are backed up exactly once and never overwritten.
# 3. Every change is reversible (--restore, --preload-on, --settings-restore).
#
# WHAT IT CHANGES
# Hiding: /var/preferences/com.webos.applicationManager/blockedSystemAppList/<REGION>.json
# Preloads: stops preload manager from keeping apps resident in RAM.
# Settings: turns off home promotions, sports alerts, live promos, ACR.
#
# USAGE
#   sh webos-debloat.sh --list            # inventory installed apps
#   sh webos-debloat.sh --plan            # show what --apply would hide
#   sh webos-debloat.sh --apply           # hide the default categories
#   sh webos-debloat.sh --preload-off     # stop preloading apps into RAM
#   sh webos-debloat.sh --settings-off    # promos, alerts, recommendations, ACR
#   sh webos-debloat.sh --install-boot-hook  # keep applied across reboots
#   sh webos-debloat.sh --status
#   sh webos-debloat.sh --restore         # un-hide what this script hid
#   sh webos-debloat.sh --preload-on      # undo preload-off
#   sh webos-debloat.sh --settings-restore  # restore settings
#   (add --dry-run to preview any of these without changing anything)

set -u

APPS_DIR=/var/preferences/com.webos.applicationManager/blockedSystemAppList
BACKUP_DIR=/var/lib/webos-debloat
HOOK=/var/lib/webosbrew/init.d/50-debloat
STATE=$BACKUP_DIR/state
PRELOAD_STATE=$BACKUP_DIR/preload-off
PRELOAD_CONF=/var/preferences/webos-preload-manager-conf.json
PRELOAD_SVC=luna://com.webos.service.preloadmanager
SAM_SVC=luna://com.webos.service.applicationmanager
SETTINGS_SVC=luna://com.webos.settingsservice
SETTINGS_STATE=$BACKUP_DIR/settings-off

APP_BASES="
/media/system/apps/usr/palm/applications
/usr/palm/applications
/mnt/otncabi/usr/palm/applications
/mnt/otycabi/usr/palm/applications
"

DRY_RUN=0
CATS=""
EXTRA_IDS=""

# ---------------------------------------------------------------------------
# Never hide these. Each one has a known failure mode if it disappears.
# ---------------------------------------------------------------------------
PROTECTED_IDS='
com.webos.app.livetv
com.webos.app.home
com.webos.app.launcher
com.palm.app.settings
com.webos.app.settings
com.webos.app.quicksettings
com.webos.app.firstuse
com.webos.app.eula
com.webos.app.webapphost
com.webos.app.container
container
com.webos.app.inputcommon
inputcommon
com.webos.app.inputlist
com.webos.app.notificationcenter
com.webos.app.browser
com.webos.app.mediaplayer
com.webos.app.mvpd
com.webos.app.install
com.webos.app.screensaver
com.webos.app.volume
com.webos.app.epg
com.webos.app.tvguide
com.webos.app.hdmi1
com.webos.app.hdmi2
com.webos.app.hdmi3
com.webos.app.hdmi4
org.webosbrew.hbchannel
com.tvweb.dashboard
com.tvweb.home
'

# ---------------------------------------------------------------------------
# Curated bloat, grouped. IDs that aren't installed/known are skipped.
# ---------------------------------------------------------------------------
IDS_AD_ACR='
com.webos.app.acrcomponent
com.webos.app.acrhdmi1
com.webos.app.acrhdmi2
com.webos.app.acrhdmi3
com.webos.app.acrhdmi4
com.webos.app.acroverlay
com.webos.app.adoverlay
com.webos.app.adoverlayex
com.webos.app.adhdmi1
com.webos.app.adhdmi2
com.webos.app.adhdmi3
com.webos.app.adhdmi4
com.webos.app.fooddelivery
com.webos.app.fooddeliveryex
com.webos.app.fooddeliveryhdmi1
com.webos.app.fooddeliveryhdmi2
com.webos.app.fooddeliveryhdmi3
com.webos.app.fooddeliveryhdmi4
com.webos.app.overlaymembership
com.webos.app.videoads
com.webos.app.cmp-client
com.webos.app.newandhot
'

IDS_REMOTE='
com.webos.app.remoteservice
'

IDS_SDK='
com.webos.exampleapp.enyoapp.epg
com.webos.exampleapp.groupowner
com.webos.exampleapp.nav
com.webos.exampleapp.qmlapp.client.negative.one
com.webos.exampleapp.qmlapp.client.negative.two
com.webos.exampleapp.qmlapp.client.positive.one
com.webos.exampleapp.qmlapp.client.positive.two
com.webos.exampleapp.qmlapp.discover
com.webos.exampleapp.qmlapp.epg
com.webos.exampleapp.qmlapp.hbbtv
com.webos.exampleapp.qmlapp.livetv
com.webos.exampleapp.qmlapp.search
com.webos.exampleapp.systemui
'

IDS_DEMO='
com.webos.app.store-demo
com.webos.app.sync-demo
com.webos.app.factorywin
com.webos.app.svcdiagnostics
com.webos.app.quickrecovery
com.webos.app.renewupdate
'

IDS_PROMO='
com.webos.app.discovery
com.webos.app.lgchannels
com.webos.app.channelplus
com.webos.app.sportsevent
com.webos.app.music
com.webos.app.photovideo
com.webos.app.userguide
com.webos.app.help
com.webos.app.today
com.webos.app.recent
com.webos.app.accuweather
com.webos.app.tvplus
com.webos.app.manufacturer
'

IDS_VISIBLE='
com.webos.app.lgchannels
com.lge.app.viewster
com.webos.app.homeconnect
com.webos.app.lglink
com.webos.app.premium
com.webos.app.lifeonscreen
com.webos.app.lifeonscreen-legacy
com.webos.app.quicklinkcopilot
com.webos.app.sportsteamsettings
com.webos.app.discovery
com.webos.app.storagemanager
com.webos.app.camera
com.webos.app.multiviewsettings
com.webos.app.mediadiscovery
'

IDS_EXTRAS='
com.webos.app.adapp
com.webos.app.aiagent
com.webos.app.aiplatform
com.webos.app.aiplatformsupport
com.webos.app.aipromotion
com.webos.app.assistant
com.webos.app.voice
com.webos.app.beanbrowser
com.webos.app.crb
com.webos.app.livedmost
com.webos.app.liveginga
com.webos.app.livehbbtv
com.webos.app.liveinteractivecontent
com.webos.app.masterbrand
com.webos.app.magicnum
com.webos.app.cpcover
com.webos.app.store-streamer
com.webos.app.universalqcard
com.webos.app.totalmusic
com.webos.app.tvuserguide
com.webos.app.helpandtips
com.webos.app.membership
com.webos.app.minimalmembership
com.webos.app.familycare
com.webos.app.learning
com.webos.app.homeoffice
com.webos.app.sportsalarm
com.webos.app.self-diagnosis
com.webos.app.customersupport
com.webos.app.remotecontrolguide
com.webos.app.seniorhome
com.webos.app.simplecalendar
com.webos.app.similarlist
com.webos.app.homeconnect-overlay
com.webos.app.rdp
com.webos.app.mobileconnection
'

DEFAULT_CATS="ad,sdk,demo,remote"

# --preload-off targets: apps kept resident in RAM.
PRELOAD_OFF_IDS='
com.webos.app.lgchannels
com.webos.app.browser
'

# --settings-off targets as settings-service category:key
SETTINGS_OFF='
general:homePromotion
general:sportsAlarm
option:livePromotion
option:webOSPromotionVideo
option:promotionStreamer
option:livePlus
other:contentRecommendation
'

# ---------------------------------------------------------------------------
log() { printf '%s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
err() { printf 'ERROR: %s\n' "$*" >&2; }
die() { err "$*"; exit 1; }

require_root() { [ "$(id -u 2>/dev/null)" = "0" ] || die "must run as root on the TV"; }
has_cmd() { command -v "$1" >/dev/null 2>&1; }

usage() { awk 'NR > 1 { if (!/^#/) exit; sub(/^# /, ""); print }' "$0"; }

read_ids() {
  [ -f "$1" ] || return 0
  awk '
  { buf = buf $0 "\n" }
  END {
    i = index(buf, "\"blocked_system_applist\"")
    if (i > 0) {
      rest = substr(buf, i)
      j = index(rest, "[")
      if (j > 0) {
        rest = substr(rest, j + 1)
        k = index(rest, "]")
        if (k > 0) {
          arr = substr(rest, 1, k - 1)
          n = split(arr, parts, ",")
          for (p = 1; p <= n; p++) {
            s = parts[p]
            gsub(/[ \t\r\n]/, "", s)
            gsub(/"/, "", s)
            if (s != "") print s
          }
        }
      }
    }
  }' "$1"
}

write_ids() {
  file=$1; shift
  body=""
  for id in "$@"; do
    [ -n "$id" ] || continue
    if [ -n "$body" ]; then body="$body,\"$id\""; else body="\"$id\""; fi
  done
  tmp="$file.tmp.$$"
  printf '{"blocked_system_applist":[%s]}\n' "$body" > "$tmp" || die "cannot write $tmp"
  mv -f "$tmp" "$file" || die "cannot replace $file"
}

in_list() {
  needle=$1; shift
  for x in "$@"; do [ "$x" = "$needle" ] && return 0; done
  return 1
}

is_protected() { in_list "$1" $PROTECTED_IDS; }

app_present() {
  id=$1
  for base in $APP_BASES; do
    [ -f "$base/$id/appinfo.json" ] && return 0
  done
  [ -d "/media/cryptofs/apps/usr/palm/applications/$id" ] && return 0
  return 1
}

appinfo_field() {
  sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$1" 2>/dev/null | head -n 1
}

app_visible() {
  v=$(sed -n 's/.*"visible"[[:space:]]*:[[:space:]]*\(true\|false\).*/\1/p' "$1" 2>/dev/null | head -n 1)
  [ "$v" = "false" ] && printf 'no\n' || printf 'yes\n'
}

pick_list_file() {
  if [ -d "$APPS_DIR" ]; then
    for f in "$APPS_DIR"/*.json; do
      [ -e "$f" ] || continue
      printf '%s\n' "$f"
      return 0
    done
  fi
  region=${WEBOS_REGION:-USA}
  printf '%s/%s.json\n' "$APPS_DIR" "$region"
}

ensure_dir() {
  [ -d "$APPS_DIR" ] && return 0
  if [ "$DRY_RUN" = "1" ]; then
    warn "dry-run: would create $APPS_DIR"
    return 0
  fi
  mkdir -p "$APPS_DIR" 2>/dev/null || die "cannot create $APPS_DIR (is /var writable?)"
}

backup_once() {
  file=$1
  [ -f "$file" ] || return 0
  mkdir -p "$BACKUP_DIR" 2>/dev/null || true
  base=$(basename "$file")
  if [ ! -f "$BACKUP_DIR/$base.orig" ]; then
    cp "$file" "$BACKUP_DIR/$base.orig" || warn "could not back up $file"
    log "backed up original to $BACKUP_DIR/$base.orig"
  fi
}

# ---------------------------------------------------------------------------
cmd_list() {
  log "Installed apps (appid | visible | title | source dir)"
  log "--------------------------------------------------------------------"
  seen=""
  for base in $APP_BASES; do
    [ -d "$base" ] || continue
    for d in "$base"/*; do
      [ -d "$d" ] || continue
      [ -f "$d/appinfo.json" ] || continue
      id=$(appinfo_field "$d/appinfo.json" id)
      [ -n "$id" ] || id=$(basename "$d")
      case " $seen " in *" $id "*) continue;; esac
      seen="$seen $id"
      title=$(appinfo_field "$d/appinfo.json" title)
      vis=$(app_visible "$d/appinfo.json")
      printf '%-42s %-4s %-28s %s\n' "$id" "$vis" "${title:--}" "$(basename "$base")"
    done
  done
  log "--------------------------------------------------------------------"
  log "Total: $(printf '%s\n' $seen | wc -l | tr -d ' ') apps"
}

# ---------------------------------------------------------------------------
resolve_cats() {
  if [ -z "$CATS" ] && [ -n "$EXTRA_IDS" ]; then
    printf '%s\n' $EXTRA_IDS
    return 0
  fi
  [ -n "$CATS" ] || CATS=$DEFAULT_CATS
  wanted=""
  old_ifs=$IFS; IFS=','
  for c in $CATS; do
    case "$c" in
      ad) wanted="$wanted $IDS_AD_ACR" ;;
      remote) wanted="$wanted $IDS_REMOTE" ;;
      sdk) wanted="$wanted $IDS_SDK" ;;
      demo) wanted="$wanted $IDS_DEMO" ;;
      promo) wanted="$wanted $IDS_PROMO" ;;
      visible) wanted="$wanted $IDS_VISIBLE" ;;
      extras) wanted="$wanted $IDS_EXTRAS" ;;
      all) wanted="$wanted $IDS_AD_ACR $IDS_REMOTE $IDS_SDK $IDS_DEMO $IDS_PROMO $IDS_VISIBLE $IDS_EXTRAS" ;;
      *) warn "unknown category '$c' (known: ad, remote, sdk, demo, promo, visible, extras, all)" ;;
    esac
  done
  IFS=$old_ifs
  printf '%s\n' $wanted $EXTRA_IDS
}

our_ids() {
  orig=$(read_ids "$BACKUP_DIR/$(basename "$1").orig")
  if [ -z "$CATS" ] && [ -z "$EXTRA_IDS" ]; then
    ids=$(CATS=all resolve_cats)
  else
    ids=$(resolve_cats)
  fi
  for id in $ids; do
    in_list "$id" $orig || printf '%s\n' "$id"
  done
}

present_targets() {
  seen=""
  for id in $(resolve_cats); do
    case " $seen " in *" $id "*) continue;; esac
    seen="$seen $id"
    if is_protected "$id"; then
      continue
    fi
    if app_present "$id"; then
      printf '%s\n' "$id"
    fi
  done
}

# ---------------------------------------------------------------------------
cmd_plan() {
  file=$(pick_list_file)
  log "Target list file : $file"
  if [ -z "$CATS" ] && [ -n "$EXTRA_IDS" ]; then
    log "Selection : --id only ($EXTRA_IDS)"
  else
    log "Categories : ${CATS:-$DEFAULT_CATS}${EXTRA_IDS:+ + id:$EXTRA_IDS}"
  fi
  log ""
  n=0
  for id in $(present_targets); do
    title=""
    for base in $APP_BASES; do
      if [ -f "$base/$id/appinfo.json" ]; then
        title=$(appinfo_field "$base/$id/appinfo.json" title)
        break
      fi
    done
    printf ' hide %-42s %s\n' "$id" "${title:--}"
    n=$((n + 1))
  done
  log ""
  log "Would hide $n app(s). Nothing was changed."
  [ "$n" = "0" ] && warn "no target apps found - run --list to see what this TV actually has"
  return 0
}

# ---------------------------------------------------------------------------
cmd_apply() {
  require_root
  file=$(pick_list_file)
  ensure_dir
  backup_once "$file"

  existing=$(read_ids "$file" | grep -v '^$' || true)
  targets=$(present_targets)

  added=""
  for id in $targets; do
    if in_list "$id" $existing; then
      continue
    fi
    added="$added $id"
  done

  if [ -z "$added" ]; then
    log "Nothing new to hide."
    return 0
  fi

  merged=""
  for id in $existing $targets; do
    [ -n "$id" ] || continue
    in_list "$id" $merged && continue
    merged="$merged $id"
  done

  log "Hiding:"
  for id in $added; do printf '  + %s\n' "$id"; done

  if [ "$DRY_RUN" = "1" ]; then
    warn "dry-run: not writing $file"
    return 0
  fi

  write_ids "$file" $merged
  log "Wrote $file"

  mkdir -p "$BACKUP_DIR" 2>/dev/null || true
  printf 'applied=%s\nlast_run=%s\n' "$(date +%s 2>/dev/null || echo 0)" "$(date 2>/dev/null || echo unknown)" >> "$STATE"

  log ""
  log "Done. Open the launcher - tiles disappear without a reboot on most"
  log "firmware. If they do not, a reboot applies it."
  if [ -z "$CATS" ] && [ -n "$EXTRA_IDS" ]; then
    log "Undo with: sh $0 --restore --id $EXTRA_IDS"
  else
    log "Undo any time with: sh $0 --restore"
  fi
}

# ---------------------------------------------------------------------------
cmd_restore() {
  require_root
  file=$(pick_list_file)
  [ -f "$file" ] || { log "No list file at $file - nothing to restore."; return 0; }

  ours=$(our_ids "$file")
  keep=""
  removed=0
  for id in $(read_ids "$file"); do
    if in_list "$id" $ours; then
      removed=$((removed + 1))
      continue
    fi
    keep="$keep $id"
  done

  if [ "$removed" = "0" ]; then
    log "Nothing of ours is currently hidden."
    return 0
  fi

  log "Un-hiding $removed app(s)."
  if [ "$DRY_RUN" = "1" ]; then
    warn "dry-run: not writing $file"
    return 0
  fi

  write_ids "$file" $keep
  log "Wrote $file"
  [ -x "$HOOK" ] && warn "boot hook still installed and will re-hide at next boot; run --remove-boot-hook"
  return 0
}

# ---------------------------------------------------------------------------
cmd_status() {
  file=$(pick_list_file)
  log "List file: $file"
  if [ ! -f "$file" ]; then
    log "  (does not exist yet - nothing is hidden)"
    return 0
  fi
  ids=$(read_ids "$file")
  if [ -z "$ids" ]; then
    log "  (empty list)"
    return 0
  fi
  ours=$(our_ids "$file")
  n=0
  for id in $ids; do
    mark="LG/other"
    in_list "$id" $ours && mark="ours"
    printf '  %-42s %s\n' "$id" "$mark"
    n=$((n + 1))
  done
  log "Total hidden: $n"
  if [ -f "$BACKUP_DIR/$(basename "$file").orig" ]; then
    log "Backup    : $BACKUP_DIR/$(basename "$file").orig"
  fi
  if [ -x "$HOOK" ]; then
    log "Boot hook : installed ($HOOK)"
  else
    log "Boot hook : not installed"
  fi
  if [ -s "$PRELOAD_STATE" ]; then
    log "Preload off : $(tr '\n' ' ' < "$PRELOAD_STATE")"
  fi
  if [ -s "$SETTINGS_STATE" ]; then
    log "Settings   : originals saved for $(awk '{ print $2 }' "$SETTINGS_STATE" | tr '\n' ' ')"
  fi
}

# ---------------------------------------------------------------------------
cmd_preload_off() {
  require_root
  has_cmd luna-send || die "luna-send not found"
  ids=${EXTRA_IDS:-$PRELOAD_OFF_IDS}
  if [ "$DRY_RUN" = "1" ]; then
    for id in $ids; do log "dry-run: would disable preload for $id"; done
    return 0
  fi
  wait_preload_svc
  mkdir -p "$BACKUP_DIR" 2>/dev/null || true
  touch "$PRELOAD_STATE"
  for id in $ids; do
    set_preload "$id" false || continue
    set_allowed "$id" false
    log "preload off: $id"
    grep -qx "$id" "$PRELOAD_STATE" || printf '%s\n' "$id" >> "$PRELOAD_STATE"
    close_preloaded "$id"
  done
}

cmd_preload_on() {
  require_root
  has_cmd luna-send || die "luna-send not found"
  [ -f "$PRELOAD_STATE" ] || { log "Nothing of ours has preload disabled."; return 0; }
  ids=${EXTRA_IDS:-$(cat "$PRELOAD_STATE")}
  if [ "$DRY_RUN" = "1" ]; then
    for id in $ids; do log "dry-run: would re-enable preload for $id"; done
    return 0
  fi
  wait_preload_svc
  for id in $ids; do
    set_preload "$id" true || continue
    set_allowed "$id" true
    log "preload on: $id"
    grep -vx "$id" "$PRELOAD_STATE" > "$PRELOAD_STATE.tmp" || true
    mv -f "$PRELOAD_STATE.tmp" "$PRELOAD_STATE"
  done
  [ -s "$PRELOAD_STATE" ] || rm -f "$PRELOAD_STATE"
}

cmd_preload_sync() {
  [ -s "$PRELOAD_STATE" ] || return 0
  EXTRA_IDS=$(cat "$PRELOAD_STATE")
  cmd_preload_off
}

wait_preload_svc() {
  tries=0
  until luna-send -n 1 "$PRELOAD_SVC/getPreloadPolicy" '{}' 2>/dev/null | grep -q '"returnValue":[[:space:]]*true'; do
    tries=$((tries + 1))
    [ "$tries" -ge 30 ] && die "preload manager not responding"
    sleep 2
  done
}

set_preload() {
  r=$(luna-send -n 1 "$PRELOAD_SVC/setPreloadPolicy" "{\"application\":{\"id\":\"$1\",\"isEnabled\":$2}}" 2>&1)
  case "$r" in
    *'"returnValue":true'*) return 0 ;;
    *) warn "setPreloadPolicy $1: $r"; return 1 ;;
  esac
}

set_allowed() {
  [ -f "$PRELOAD_CONF" ] || return 0
  backup_once "$PRELOAD_CONF"
  id_re=$(printf '%s' "$1" | sed 's/\./\\./g')
  if [ "$2" = false ]; then from=true; else from=false; fi
  sed -i "s/\(\"$id_re\"[[:space:]]*:[[:space:]]*\)$from/\1$2/" "$PRELOAD_CONF"
}

close_preloaded() {
  fg=$(luna-send -n 1 "$SAM_SVC/getForegroundAppInfo" '{}' 2>/dev/null)
  case "$fg" in *"\"appId\":\"$1\""*) return 0 ;; esac
  luna-send -n 1 "$SAM_SVC/running" '{}' 2>/dev/null | grep -q "\"$1\"" || return 0
  luna-send -n 1 "$SAM_SVC/closeByAppId" "{\"id\":\"$1\"}" >/dev/null 2>&1 \
    && log "  closed resident $1"
}

# ---------------------------------------------------------------------------
get_setting() {
  luna-send -n 1 "$SETTINGS_SVC/getSystemSettings" "{\"category\":\"$1\",\"keys\":[\"$2\"]}" 2>/dev/null \
    | sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p"
}

set_setting() {
  r=$(luna-send -n 1 "$SETTINGS_SVC/setSystemSettings" "{\"category\":\"$1\",\"settings\":{\"$2\":\"$3\"}}" 2>&1)
  case "$r" in
    *'"returnValue":true'*) return 0 ;;
    *) warn "setSystemSettings $1/$2: $r"; return 1 ;;
  esac
}

cmd_settings_off() {
  require_root
  has_cmd luna-send || die "luna-send not found"
  mkdir -p "$BACKUP_DIR" 2>/dev/null || true
  for ck in $SETTINGS_OFF; do
    category=${ck%%:*} key=${ck#*:}
    cur=$(get_setting "$category" "$key")
    if [ -z "$cur" ]; then
      log "  skip $category/$key (not on this firmware)"
      continue
    fi
    if [ "$cur" = off ]; then
      log "  $category/$key already off"
      continue
    fi
    if [ "$DRY_RUN" = "1" ]; then
      log "dry-run: would turn off $category/$key (now $cur)"
      continue
    fi
    grep -q "^$category $key " "$SETTINGS_STATE" 2>/dev/null \
      || printf '%s %s %s\n' "$category" "$key" "$cur" >> "$SETTINGS_STATE"
    set_setting "$category" "$key" off && log "setting off: $category/$key (was $cur)"
  done
}

cmd_settings_restore() {
  require_root
  has_cmd luna-send || die "luna-send not found"
  [ -s "$SETTINGS_STATE" ] || { log "No settings of ours to restore."; return 0; }
  while read -r category key val; do
    [ -n "$val" ] || continue
    if [ "$DRY_RUN" = "1" ]; then
      log "dry-run: would set $category/$key back to $val"
      continue
    fi
    set_setting "$category" "$key" "$val" && log "setting restored: $category/$key = $val"
  done < "$SETTINGS_STATE"
  [ "$DRY_RUN" = "1" ] || rm -f "$SETTINGS_STATE"
}

# ---------------------------------------------------------------------------
cmd_install_hook() {
  require_root
  mkdir -p "$BACKUP_DIR" 2>/dev/null || die "cannot create $BACKUP_DIR"
  mkdir -p "$(dirname "$HOOK")" 2>/dev/null || die "cannot create $(dirname "$HOOK")"

  self_src=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/$(basename -- "$0")
  [ -f "$self_src" ] || self_src=$0
  persistent="$BACKUP_DIR/webos-debloat.sh"
  if [ "$self_src" != "$persistent" ]; then
    cp "$self_src" "$persistent" || die "cannot copy script to $persistent"
    chmod 0755 "$persistent"
    log "Installed script copy at $persistent"
  fi

  apply_args=""
  [ -n "$CATS" ] && apply_args="--only $CATS"

  cat > "$HOOK" <<EOF
#!/bin/sh
# Re-assert the debloat list at boot: the application manager can rewrite
# blockedSystemAppList on its own after a component update.
# Installed by webos-debloat.sh. Remove with --remove-boot-hook.
sleep 5
[ -x "$persistent" ] && "$persistent" --apply $apply_args >>"$BACKUP_DIR/boot.log" 2>&1
[ -x "$persistent" ] && "$persistent" --preload-sync >>"$BACKUP_DIR/boot.log" 2>&1
exit 0
EOF
  chmod 0755 "$HOOK"
  log "Installed boot hook at $HOOK (re-applies: ${apply_args:-default categories})"
}

cmd_remove_hook() {
  require_root
  if [ -f "$HOOK" ]; then
    rm -f "$HOOK" && log "Removed $HOOK"
  else
    log "No boot hook installed."
  fi
}

# ---------------------------------------------------------------------------
CMD=""
while [ $# -gt 0 ]; do
  case "$1" in
    --list) CMD=list ;;
    --plan) CMD=plan ;;
    --apply) CMD=apply ;;
    --restore) CMD=restore ;;
    --status) CMD=status ;;
    --install-boot-hook) CMD=hook ;;
    --remove-boot-hook) CMD=unhook ;;
    --preload-off) CMD=preload_off ;;
    --preload-on) CMD=preload_on ;;
    --preload-sync) CMD=preload_sync ;;
    --settings-off) CMD=settings_off ;;
    --settings-restore) CMD=settings_restore ;;
    --dry-run) DRY_RUN=1 ;;
    --only) shift; CATS=${1:-} ;;
    --id) shift; EXTRA_IDS="$EXTRA_IDS ${1:-}" ;;
    --region) shift; WEBOS_REGION=${1:-} ;;
    -h|--help)
      usage; exit 0 ;;
    *) die "unknown option: $1 (try --help)" ;;
  esac
  shift
done

[ -n "$CMD" ] || { usage; exit 1; }

case "$CMD" in
  list) cmd_list ;;
  plan) cmd_plan ;;
  apply) cmd_apply ;;
  restore) cmd_restore ;;
  status) cmd_status ;;
  hook) cmd_install_hook ;;
  unhook) cmd_remove_hook ;;
  preload_off) cmd_preload_off ;;
  preload_on) cmd_preload_on ;;
  preload_sync) cmd_preload_sync ;;
  settings_off) cmd_settings_off ;;
  settings_restore) cmd_settings_restore ;;
esac
